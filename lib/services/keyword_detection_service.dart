import 'dart:async';
import 'dart:math';
import '../models/keyword_model.dart';
import 'audio_service.dart';

// Service de détection de mots-clés.
//
// PROTOTYPE : déclenchement par seuil d'amplitude.
// Pour passer en production, remplacer detectKeyword() par :
//   - Picovoice Porcupine (wake-word offline)
//   - Vosk (speech-to-text offline)
//   - Un modèle TFLite personnalisé
class KeywordDetectionService {
  final AudioService _audioService;
  Timer? _timer;
  bool _active = false;
  int _consecutivePeaks = 0;

  static const double _amplitudeThreshold = -20.0; // dB
  static const int _peaksRequired = 4;
  static const Duration _interval = Duration(milliseconds: 300);

  KeywordDetectionService(this._audioService);

  bool get isActive => _active;

  // ─── Point d'extension pour la vraie détection ────────────────────────────
  //
  // Remplacer ce corps par un appel au SDK de reconnaissance vocale.
  // [audioBuffer] : données PCM brutes (null dans la version prototype)
  // [keywords]    : liste des mots-clés à détecter avec leurs échantillons
  // Retourne : le texte du mot-clé détecté, ou null si aucun.
  Future<String?> detectKeyword(
    dynamic audioBuffer,
    List<KeywordModel> keywords,
  ) async {
    // Simulation : on choisit aléatoirement un mot-clé parmis ceux enregistrés.
    // Dans la vraie implémentation, comparer audioBuffer aux échantillons.
    final recorded = keywords.where((k) => k.isRecorded).toList();
    if (recorded.isEmpty) return null;
    return recorded[Random().nextInt(recorded.length)].text;
  }

  // Lance l'écoute. [onDetected] est appelé avec le texte du mot-clé trouvé.
  Future<void> startListening({
    required List<KeywordModel> keywords,
    required void Function(String keyword) onDetected,
  }) async {
    if (_active || keywords.isEmpty) return;
    _active = true;
    _consecutivePeaks = 0;
    await _audioService.startMonitoring();

    _timer = Timer.periodic(_interval, (_) async {
      if (!_active) return;
      try {
        final db = await _audioService.getAmplitude();
        if (db >= _amplitudeThreshold) {
          _consecutivePeaks++;
          if (_consecutivePeaks >= _peaksRequired) {
            _consecutivePeaks = 0;
            final detected = await detectKeyword(null, keywords);
            if (detected != null) {
              await stop();
              onDetected(detected);
            }
          }
        } else {
          if (_consecutivePeaks > 0) _consecutivePeaks--;
        }
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _consecutivePeaks = 0;
    await _audioService.stopMonitoring();
  }
}
