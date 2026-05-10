import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/foreground_service.dart';
import 'state/app_state.dart';
import 'app.dart';

// Le callback du service foreground est défini dans foreground_service.dart
// (_startCallback) et référencé directement depuis ForegroundService.start().
// Cette architecture évite l'import circulaire et garde le code du service
// dans son propre fichier.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure le service foreground (notification, options) au démarrage
  await ForegroundService.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const AudioRecorderApp(),
    ),
  );
}
