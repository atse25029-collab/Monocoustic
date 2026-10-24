import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/models/playback_state.dart';

typedef NotificationActionHandler = void Function(String actionId);

class RemoteNotificationService {
  static final RemoteNotificationService instance = RemoteNotificationService._();
  RemoteNotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  NotificationActionHandler? onAction;

  static const String channelId = 'monocoustic_media_playback';
  static const String channelName = 'Monocoustic Playback Control';
  static const String channelDescription =
      'Real-time controls and song info for Monocoustic remote playback';
  static const int notificationId = 8801;

  static const String actionPrev = 'action_prev';
  static const String actionPlayPause = 'action_play_pause';
  static const String actionNext = 'action_next';

  Future<void> initialize({NotificationActionHandler? handler}) async {
    if (_initialized) return;
    onAction = handler;

    // Only configure notifications on Android/iOS
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    try {
      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final actionId = response.actionId;
          if (actionId != null && actionId.isNotEmpty) {
            onAction?.call(actionId);
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      // Create notification channel with low importance (no sound/vibration) but visible on lockscreen
      final androidPlatform = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlatform != null) {
        await androidPlatform.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );

        // Request POST_NOTIFICATIONS permission on Android 13+
        await androidPlatform.requestNotificationsPermission();
      }

      _initialized = true;
    } catch (e) {
      debugPrint('Failed to initialize local notifications: $e');
    }
  }

  /// Updates or shows the persistent media playback notification
  Future<void> updateNotification({
    required PlaybackStateSnapshot state,
    required bool isConnected,
  }) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (!_initialized) {
      await initialize(handler: onAction);
    }

    if (!isConnected) {
      await cancelNotification();
      return;
    }

    final song = state.currentSong;
    final title = song?.title ?? 'Connected to Laptop';
    final artist = song != null
        ? (song.album.isNotEmpty ? '${song.artist} • ${song.album}' : song.artist)
        : 'Monocoustic Remote Active';

    final isPlaying = state.isPlaying;

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      showWhen: false,
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          actionPrev,
          'Prev',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          actionPlayPause,
          isPlaying ? 'Pause' : 'Play',
          showsUserInterface: false,
          cancelNotification: false,
        ),
        const AndroidNotificationAction(
          actionNext,
          'Next',
          showsUserInterface: false,
          cancelNotification: false,
        ),
      ],
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    try {
      await _notificationsPlugin.show(
        id: notificationId,
        title: title,
        body: artist,
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint('Error showing notification: $e');
    }
  }

  /// Cancels the media notification when disconnected
  Future<void> cancelNotification() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      await _notificationsPlugin.cancel(id: notificationId);
    } catch (_) {}
  }
}

/// Global top-level callback for background notification action taps
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final actionId = response.actionId;
  if (actionId != null && actionId.isNotEmpty) {
    RemoteNotificationService.instance.onAction?.call(actionId);
  }
}
