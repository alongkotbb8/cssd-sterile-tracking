import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../notifications/fcm_service.dart';

const kTokenKey = 'access_token';
const kUserKey = 'auth_user';

enum AuthStatus { unknown, unauthenticated, authenticated }

@immutable
class AuthState {
  final AuthStatus status;
  final AppUser? user;
  // เก็บ token ไว้ใน memory เป็นแหล่งความจริงหลักที่ dio interceptor อ่าน
  // (อ่านจาก secure storage แบบ async ทุก request มีโอกาส race กับตอนเพิ่งเขียนเสร็จ)
  final String? token;

  const AuthState._(this.status, this.user, this.token);

  const AuthState.unknown() : this._(AuthStatus.unknown, null, null);
  const AuthState.unauthenticated() : this._(AuthStatus.unauthenticated, null, null);
  const AuthState.authenticated(AppUser user, String token)
      : this._(AuthStatus.authenticated, user, token);
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    _restore();
    return const AuthState.unknown();
  }

  Future<void> _restore() async {
    AuthState result = const AuthState.unauthenticated();
    try {
      final token = await ref.read(secureStorageProvider).read(key: kTokenKey);
      final userJson =
          ref.read(sharedPreferencesProvider).getString(kUserKey);
      if (token != null && token.isNotEmpty && userJson != null) {
        result = AuthState.authenticated(
          AppUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>),
          token,
        );
      }
    } catch (_) {
      // storage อ่านไม่ได้ → ถือว่ายังไม่ล็อกอิน
    }
    // _restore() ไม่ await ตอนถูกเรียกจาก build() ถ้าผู้ใช้กด login เสร็จ
    // ก่อน _restore() จะอ่าน storage เสร็จ ห้ามให้ผลลัพธ์เก่านี้ทับ state ปัจจุบัน
    if (state.status == AuthStatus.unknown) {
      state = result;
    }
  }

  /// คืน null เมื่อสำเร็จ, คืนข้อความ error เมื่อล้มเหลว
  Future<String?> login(String employeeCode, String password) async {
    try {
      final res = await ref.read(dioProvider).post<Map<String, dynamic>>(
        '/auth/login',
        data: {'employeeCode': employeeCode.trim(), 'password': password},
      );
      final data = res.data!;
      final token = data['accessToken'] as String;
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);

      // อัปเดต state (มี token ใน memory ทันที) ก่อน แล้วค่อยเขียนลง storage
      // เพื่อกันไม่ให้ request ถัดไปหลัง login แข่งกับการเขียน storage ที่ยังไม่เสร็จ
      state = AuthState.authenticated(user, token);

      await ref.read(secureStorageProvider).write(key: kTokenKey, value: token);
      await ref
          .read(sharedPreferencesProvider)
          .setString(kUserKey, jsonEncode(user.toJson()));

      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return 'รหัสพนักงานหรือรหัสผ่านไม่ถูกต้อง';
      }
      return apiErrorMessage(e);
    } catch (e) {
      return apiErrorMessage(e);
    }
  }

  /// เคลียร์ session เฉพาะเครื่องนี้ — **ไม่ยิง API ใด ๆ** จึงปลอดภัยที่จะเรียกจาก
  /// dio 401 interceptor โดยไม่เกิดลูป (401 → logout → ยิง API → 401 → ...)
  /// idempotent: ถ้าเคลียร์ไปแล้วเรียกซ้ำจะไม่ทำอะไร (กัน logout ซ้อน)
  Future<void> clearLocalSession() async {
    if (state.status == AuthStatus.unauthenticated && state.token == null) {
      return;
    }
    // ตั้ง state ก่อน (sync) — ตัด token ที่ interceptor แนบ + เป็น guard กันเรียกซ้อน
    state = const AuthState.unauthenticated();
    try {
      await ref.read(secureStorageProvider).delete(key: kTokenKey);
      await ref.read(sharedPreferencesProvider).remove(kUserKey);
    } catch (_) {
      // storage เคลียร์ไม่ได้ก็ไม่บล็อกการออกจากระบบ (best-effort)
    }
  }

  /// ออกจากระบบ (ผู้ใช้กดเอง) — ยกเลิก FCM token ตอน token ยัง **ใช้ได้** ก่อน
  /// แล้วค่อยเคลียร์ session เครื่องนี้
  Future<void> logout() async {
    await _safeUnregisterFcm();
    await clearLocalSession();
  }

  /// ออกจากระบบทุกอุปกรณ์ — เพิกถอน token ทั้งหมดฝั่ง server (เพิ่ม tokenVersion)
  ///
  /// ลำดับสำคัญ (กันลูป 401): ยกเลิก FCM **ก่อน** revoke (ตอน token ยังใช้ได้) →
  /// เรียก /auth/logout-all (หลังจากนี้ token ปัจจุบันใช้ไม่ได้แล้ว) → เคลียร์ local
  /// ด้วย clearLocalSession() ที่ **ไม่ยิง API** จึงไม่เกิด 401 ซ้ำ/ลูป
  /// เครื่องอื่นจะโดน 401 แล้ว auto-logout (interceptor → clearLocalSession) เอง
  Future<void> logoutAllDevices() async {
    await _safeUnregisterFcm(); // token ยังใช้ได้ตรงนี้
    try {
      await ref.read(dioProvider).post<Map<String, dynamic>>('/auth/logout-all');
    } catch (_) {
      // ต่อ server ไม่ได้ก็ยังออกจากระบบเครื่องนี้ต่อ (best-effort)
    }
    await clearLocalSession(); // ไม่ยิง API → ไม่ unregister ซ้ำด้วย token ที่ถูกเพิกถอน
  }

  Future<void> _safeUnregisterFcm() async {
    try {
      await unregisterFcmToken(ref);
    } catch (_) {
      // ไม่ให้ FCM พังบล็อกการออกจากระบบ
    }
  }
}
