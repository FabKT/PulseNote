import '../models/schedule_model.dart';

// Logique de planification : trouve le créneau actif et le prochain créneau.
class ScheduleService {
  // Retourne le premier créneau actif à l'heure actuelle, ou null.
  ScheduleModel? findActiveSchedule(List<ScheduleModel> schedules) {
    for (final s in schedules) {
      if (s.isCurrentlyActive()) return s;
    }
    return null;
  }

  // Retourne le prochain créneau à venir (dans les 24h), ou null.
  ScheduleModel? findNextSchedule(List<ScheduleModel> schedules) {
    final now = DateTime.now();
    final nowMins = now.hour * 60 + now.minute;

    ScheduleModel? next;
    int minDiff = 99999;

    for (final s in schedules) {
      if (!s.isActive) continue;
      final startMins = s.startTime.hour * 60 + s.startTime.minute;
      var diff = startMins - nowMins;
      if (diff <= 0) diff += 24 * 60; // prochain jour si déjà passé
      if (diff < minDiff) {
        minDiff = diff;
        next = s;
      }
    }
    return next;
  }

  // Formate un TimeOfDay en chaîne HH:MM.
  static String formatTime(dynamic time) {
    // Compatible TimeOfDay (Flutter) ou heures/minutes brutes
    final h = (time.hour as int).toString().padLeft(2, '0');
    final m = (time.minute as int).toString().padLeft(2, '0');
    return '$h:$m';
  }
}
