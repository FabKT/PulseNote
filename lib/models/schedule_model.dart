import 'package:flutter/material.dart';

enum ScheduleMode { autoRecord, keywordTrigger }

class ScheduleModel {
  final String id;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final ScheduleMode mode;
  final List<String>
      keywordIds; // IDs des mots-clés actifs (mode keywordTrigger)
  final List<int> daysOfWeek; // 1=Lundi … 7=Dimanche
  final bool isActive;

  const ScheduleModel({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.mode,
    this.keywordIds = const [],
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
    this.isActive = true,
  });

  // Retourne true si l'heure actuelle est dans la fenêtre de ce créneau.
  bool isCurrentlyActive() {
    if (!isActive) return false;
    final now = DateTime.now();
    if (!daysOfWeek.contains(now.weekday)) return false;
    final current = now.hour * 60 + now.minute;
    final start = startTime.hour * 60 + startTime.minute;
    final end = endTime.hour * 60 + endTime.minute;
    if (start > end) {
      return current >= start || current < end; // traverse minuit
    }
    return current >= start && current < end;
  }

  String get modeLabel => switch (mode) {
        ScheduleMode.autoRecord => 'Enregistrement auto',
        ScheduleMode.keywordTrigger => 'Déclenchement mot-clé',
      };

  String get modeLabelShort => switch (mode) {
        ScheduleMode.autoRecord => 'Auto',
        ScheduleMode.keywordTrigger => 'Mot-clé',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'startHour': startTime.hour,
        'startMinute': startTime.minute,
        'endHour': endTime.hour,
        'endMinute': endTime.minute,
        'mode': mode.name,
        'keywordIds': keywordIds,
        'daysOfWeek': daysOfWeek,
        'isActive': isActive,
      };

  factory ScheduleModel.fromJson(Map<String, dynamic> json) => ScheduleModel(
        id: json['id'] as String,
        startTime: TimeOfDay(
            hour: json['startHour'] as int, minute: json['startMinute'] as int),
        endTime: TimeOfDay(
            hour: json['endHour'] as int, minute: json['endMinute'] as int),
        mode: ScheduleMode.values
            .firstWhere((m) => m.name == json['mode'] as String),
        keywordIds: List<String>.from(json['keywordIds'] as List? ?? []),
        daysOfWeek: List<int>.from(json['daysOfWeek'] as List),
        isActive: json['isActive'] as bool,
      );

  ScheduleModel copyWith({
    String? id,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    ScheduleMode? mode,
    List<String>? keywordIds,
    List<int>? daysOfWeek,
    bool? isActive,
  }) =>
      ScheduleModel(
        id: id ?? this.id,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        mode: mode ?? this.mode,
        keywordIds: keywordIds ?? this.keywordIds,
        daysOfWeek: daysOfWeek ?? this.daysOfWeek,
        isActive: isActive ?? this.isActive,
      );
}
