import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static StreamSubscription<String>? _tokenSubscription;
  static String? _boundUid;
  static String? _tokenDocId;
  static bool _initialized = false;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'game_party_notifications',
    'Game Party Notifications',
    description: 'การแจ้งเตือนข้อความใหม่จาก Game Party',
    importance: Importance.max,
  );

  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _local.initialize(settings: settings);
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Request permission after the signed-in app starts using notifications.
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) return;
      final title = message.notification?.title ??
          message.data['title']?.toString() ??
          'Game Party';
      final body = message.notification?.body ??
          message.data['body']?.toString() ??
          'คุณมีการแจ้งเตือนใหม่';
      unawaited(showLocalNotification(title: title, body: body));
    });

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    _initialized = true;
  }

  /// Registers this device's private FCM token for server-side chat push.
  static Future<void> bindUser(String uid) async {
    if (kIsWeb || uid.isEmpty || _boundUid == uid) return;
    await initialize();
    await _tokenSubscription?.cancel();
    _boundUid = uid;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(uid, token);
    } catch (error) {
      debugPrint('Could not register FCM token: $error');
    }
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (newToken) => unawaited(_saveTokenSafely(uid, newToken)),
      onError: (Object error) => debugPrint('FCM token refresh failed: $error'),
    );
  }

  static Future<void> unbindUser() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    final uid = _boundUid;
    final tokenDocId = _tokenDocId;
    if (uid != null && tokenDocId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('devices')
            .doc(tokenDocId)
            .delete();
      } on FirebaseException catch (error) {
        debugPrint('Could not remove signed-out device token: ${error.code}');
      }
    }
    _boundUid = null;
    _tokenDocId = null;
  }

  static Future<void> _saveToken(String uid, String token) async {
    if (_boundUid != uid) return;
    final tokenDocId = base64Url.encode(utf8.encode(token)).replaceAll('=', '');
    final previousTokenDocId = _tokenDocId;
    _tokenDocId = tokenDocId;
    if (previousTokenDocId != null && previousTokenDocId != tokenDocId) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(previousTokenDocId)
          .delete();
    }
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(tokenDocId)
        .set({
      'token': token,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> _saveTokenSafely(String uid, String token) async {
    try {
      await _saveToken(uid, token);
    } on FirebaseException catch (error) {
      debugPrint('Could not update FCM token (${error.code})');
    }
  }

  static Future<void> showLocalNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    await _local.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}
