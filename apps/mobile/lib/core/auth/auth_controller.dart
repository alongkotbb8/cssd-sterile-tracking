import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../models/models.dart';

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

  Future<void> logout() async {
    state = const AuthState.unauthenticated();
    await ref.read(secureStorageProvider).delete(key: kTokenKey);
    await ref.read(sharedPreferencesProvider).remove(kUserKey);
  }
}
