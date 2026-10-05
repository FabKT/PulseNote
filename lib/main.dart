import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/supabase_config.dart';
import 'services/foreground_service.dart';
import 'services/auth_service.dart';
import 'state/app_state.dart';
import 'app.dart';

// Le callback du service foreground est défini dans foreground_service.dart
// (_startCallback) et référencé directement depuis ForegroundService.start().
// Cette architecture évite l'import circulaire et garde le code du service
// dans son propre fichier.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeCrashReporting();
  _installErrorHandling();
  if (SupabaseConfig.isConfigured) {
    await AuthService.initializeSupabase();
  }
  await AuthService.initializeGoogleSignIn();

  // Configure le service foreground (notification, options) au démarrage
  await ForegroundService.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const AudioRecorderApp(),
    ),
  );
}

bool _crashlyticsReady = false;

Future<void> _initializeCrashReporting() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await Firebase.initializeApp();
    const enabled = bool.fromEnvironment(
      'CRASHLYTICS_ENABLED',
      defaultValue: kReleaseMode,
    );
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
    _crashlyticsReady = enabled;
  } catch (error, stack) {
    debugPrint('Crashlytics initialization failed: $error\n$stack');
  }
}

void _installErrorHandling() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (_crashlyticsReady) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    }
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    if (_crashlyticsReady) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'Ultimate Audio Recorder',
        ),
      );
    }
    return true;
  };
  ErrorWidget.builder = (_) => const Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: Color(0xFF07080D),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: Color(0xFFF7C948),
                    size: 42,
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Cette section a rencontré un problème.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Revenez à la page précédente puis réessayez.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
