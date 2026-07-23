import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../../l10n/app_localizations.dart';

/// ต้องเป็น top-level function (ไม่ผูกกับ instance) — ตามข้อกำหนดของ
/// firebase_messaging สำหรับ handler ที่ทำงานตอนแอปอยู่ background/ถูกปิด
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ไม่ต้องทำอะไรเพิ่ม — ระบบ OS แสดง notification ให้เองจาก payload "notification"
}

const _kChannelId = 'cssd_reminders';

/// ชื่อ/รายละเอียด channel มาจาก i18n ตาม locale ของเครื่อง (สร้างตอน init)
/// เลือก locale ที่รองรับ (th/en) จาก device locale, fallback th
Future<AppLocalizations> _channelL10n() {
  final sys = ui.PlatformDispatcher.instance.locale;
  final supported = AppLocalizations.supportedLocales
      .any((l) => l.languageCode == sys.languageCode);
  return AppLocalizations.delegate
      .load(supported ? ui.Locale(sys.languageCode) : const ui.Locale('th'));
}

/// ครอบ Firebase Cloud Messaging ทั้งหมดไว้ที่เดียว — ถ้ายังไม่มีไฟล์ตั้งค่า
/// Firebase จริง (google-services.json / GoogleService-Info.plist) การ init
/// จะ throw แล้วเรา catch ไว้ ให้แอปทำงานต่อได้ตามปกติโดยไม่มี push notification
/// (เทียบเท่า pattern MockPrinterAdapter — ทำงานได้โดยไม่ต้องมีของจริงพร้อม)
class FcmService {
  static bool _initialized = false;
  static bool isAvailable = false;

  /// channel ที่ localize แล้ว (สร้างใน init) — ใช้ตอนแสดง foreground notification
  static AndroidNotificationChannel? _channel;

  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[FcmService] Firebase ยังไม่ได้ตั้งค่า — ปิดการแจ้งเตือน push ($e)');
      return;
    }

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    final l10n = await _channelL10n();
    _channel = AndroidNotificationChannel(
      _kChannelId,
      l10n.fcmChannelName,
      description: l10n.fcmChannelDesc,
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel!);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await FirebaseMessaging.instance.requestPermission();

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    isAvailable = true;
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
            _kChannelId, _channel?.name ?? 'CSSD',
            channelDescription: _channel?.description,
            importance: Importance.high),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static Future<String?> getToken() async {
    if (!isAvailable) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[FcmService] getToken failed: $e');
      return null;
    }
  }
}

/// ลงทะเบียน token กับ backend — เรียกหลัง login สำเร็จ (เงียบเมื่อไม่มี Firebase)
/// รับ WidgetRef เพราะเรียกจาก ConsumerWidget.build (ดู main.dart)
Future<void> registerFcmToken(WidgetRef ref) async {
  final token = await FcmService.getToken();
  if (token == null) return;
  try {
    // dart:io Platform.operatingSystem throws บนเว็บ — ต้องเช็ค kIsWeb ก่อนเสมอ
    final platformLabel = kIsWeb ? 'web' : Platform.operatingSystem;
    await ref.read(dioProvider).post('/notifications/fcm-token', data: {
      'token': token,
      'deviceId': '$platformLabel-${identityHashCode(token)}',
    });
  } catch (e) {
    debugPrint('[FcmService] ลงทะเบียน token ไม่สำเร็จ: $e');
  }
}

/// ยกเลิก token ตอน logout — กันไม่ให้เครื่องเดิมได้รับ push หลังออกจากระบบ
Future<void> unregisterFcmToken(Ref ref) async {
  final token = await FcmService.getToken();
  if (token == null) return;
  try {
    await ref.read(dioProvider).delete('/notifications/fcm-token', data: {'token': token});
  } catch (e) {
    debugPrint('[FcmService] ยกเลิก token ไม่สำเร็จ: $e');
  }
}
