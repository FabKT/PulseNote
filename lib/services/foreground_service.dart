import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// Gestion du service foreground Android.
// Le service maintient un processus vivant même écran éteint et
// envoie un "tick" périodique à l'application principale pour
// déclencher la vérification des créneaux planifiés.
class ForegroundService {
  // Configure les options une seule fois au démarrage de l'app.
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'audio_recorder_channel',
        channelName: 'Ultimate Audio Recorder',
        channelDescription: 'Service d\'écoute audio actif en arrière-plan',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Tick toutes les 30 secondes pour vérifier les créneaux
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // Démarre le service foreground avec notification persistante.
  // Retourne void — ServiceRequestResult n'est pas exposé à l'app.
  static Future<void> start() async {
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Mode écoute actif',
      notificationText: 'L\'application surveille le son en arrière-plan',
      callback: _startCallback,
    );
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  // Met à jour le texte de la notification selon l'état courant
  static Future<void> updateNotification(String title, String text) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }
}

// Callback d'entrée du TaskHandler — doit être top-level + @pragma
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(AudioTaskHandler());
}

// Handler exécuté dans le contexte du service foreground.
class AudioTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Tick périodique → signal à l'isolate principal pour vérifier les créneaux
    FlutterForegroundTask.sendDataToMain({
      'event': 'tick',
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(dynamic data) {}
}
