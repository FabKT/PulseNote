import 'dart:async';
import 'audio_service.dart';

// Détection de mot-clé par seuil d'amplitude.
//
// Prototype : au lieu d'un vrai moteur de reconnaissance vocale,
// on détecte un pic sonore soutenu (≥ N échantillons consécutifs
// au-dessus du seuil) comme signal de déclenchement.
//
// Pour intégrer un vrai modèle (ex. Picovoice/Porcupine), remplacer
// _monitorLoop() par l'API du SDK choisi.
class KeywordDetector {
  final AudioService _audioService;
  Timer? _timer;
  bool _active = false;
  int _consecutivePeaks = 0;

  // Seuil d'amplitude en dB (typiquement -20 dB pour la voix)
  static const double _threshold = -20.0;

  // Nombre de pics consécutifs requis pour éviter les faux positifs
  static const int _peaksRequired = 4;

  // Intervalle entre chaque mesure d'amplitude
  static const Duration _interval = Duration(milliseconds: 250);

  KeywordDetector(this._audioService);

  bool get isActive => _active;

  // Lance la détection. Appelle [onDetected] quand le seuil est atteint.
  Future<void> start({required void Function() onDetected}) async {
    if (_active) return;
    _active = true;
    _consecutivePeaks = 0;

    await _audioService.startMonitoring();

    _timer = Timer.periodic(_interval, (_) async {
      if (!_active) return;

      try {
        final db = await _audioService.getAmplitude();
        if (db >= _threshold) {
          _consecutivePeaks++;
          if (_consecutivePeaks >= _peaksRequired) {
            // Déclenchement : arrêt de la détection, lancement de l'enregistrement
            await stop();
            onDetected();
          }
        } else {
          // Décroissance progressive pour éviter les redéclenchements
          if (_consecutivePeaks > 0) _consecutivePeaks--;
        }
      } catch (_) {
        // Micro temporairement indisponible — on continue
      }
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
