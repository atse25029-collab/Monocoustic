import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:timezone/timezone.dart';

export 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
export 'package:timezone/timezone.dart';

enum NotificationUpdateResult {
  success,
  error,
  notFound,
}

enum WindowsNotificationDuration {
  long,
  short,
}

enum WindowsNotificationScenario {
  reminder,
  alarm,
  incomingCall,
  urgent,
}

class WindowsInitializationSettings {
  const WindowsInitializationSettings({
    required this.appName,
    required this.appUserModelId,
    required this.guid,
    this.iconPath,
  });

  final String appName;
  final String appUserModelId;
  final String guid;
  final String? iconPath;
}

class WindowsNotificationDetails {
  const WindowsNotificationDetails();
}

abstract class WindowsNotificationsBase extends FlutterLocalNotificationsPlatform {
  Future<bool> initialize({
    required WindowsInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  });

  void dispose();

  Future<void> showRawXml({
    required int id,
    required String xml,
    Map<String, String> bindings = const <String, String>{},
  });

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
    WindowsNotificationDetails? notificationDetails,
  });

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required TZDateTime scheduledDate,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    WindowsNotificationDetails? notificationDetails,
  });

  Future<void> zonedScheduleRawXml({
    required int id,
    required String xml,
    required TZDateTime scheduledDate,
  });

  Future<NotificationUpdateResult> updateBindings({
    required int id,
    required Map<String, String> bindings,
  });

  bool isValidXml(String xml);
}

class FlutterLocalNotificationsWindows extends WindowsNotificationsBase {
  static void registerWith() {
    FlutterLocalNotificationsPlatform.instance = FlutterLocalNotificationsWindows();
  }

  @override
  Future<bool> initialize({
    required WindowsInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
  }) async => true;

  @override
  void dispose() {}

  @override
  Future<void> cancel({required int id}) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => <ActiveNotification>[];

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async => null;

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async => <PendingNotificationRequest>[];

  @override
  Future<void> periodicallyShow({
    required int id,
    String? title,
    String? body,
    String? payload,
    required RepeatInterval repeatInterval,
    WindowsNotificationDetails? notificationDetails,
  }) async {}

  @override
  Future<void> periodicallyShowWithDuration({
    required int id,
    String? title,
    String? body,
    required Duration repeatDurationInterval,
  }) async {}

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
    WindowsNotificationDetails? notificationDetails,
  }) async {}

  @override
  Future<void> showRawXml({
    required int id,
    required String xml,
    Map<String, String> bindings = const <String, String>{},
  }) async {}

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required TZDateTime scheduledDate,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    WindowsNotificationDetails? notificationDetails,
  }) async {}

  @override
  Future<void> zonedScheduleRawXml({
    required int id,
    required String xml,
    required TZDateTime scheduledDate,
  }) async {}

  @override
  Future<NotificationUpdateResult> updateBindings({
    required int id,
    required Map<String, String> bindings,
  }) async => NotificationUpdateResult.success;

  @override
  bool isValidXml(String xml) => false;
}
