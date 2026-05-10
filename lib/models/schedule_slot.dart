import 'package:flutter/material.dart';

class ScheduleSlot {
  final String id;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final List<int> daysOfWeek; // 1=Lundi ... 7=Dimanche (DateTime.weekday)
  final bool isActive;

  const ScheduleSlot({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
    this.isActive = true,
  });

  // Retourne true si l'heure actuelle est dans ce créneau
  bool isCurrentlyActive() {
    if (!isActive) return false;
    final now = DateTime.now();
    if (!daysOfWeek.contains(now.weekday)) return false;

    final current = now.hour * 60 + now.minute;
    final start = startTime.hour * 60 + startTime.minute;
    final end = endTime.hour * 60 + endTime.minute;

    // Créneau traversant minuit (ex: 23:00–01:00)
    if (start > end) return current >= start || current < end;
    return current >= start && current < end;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startHour': startTime.hour,
        'startMinute': startTime.minute,
        'endHour': endTime.hour,
        'endMinute': endTime.minute,
        'daysOfWeek': daysOfWeek,
        'isActive': isActive,
      };

  factory ScheduleSlot.fromJson(Map<String, dynamic> json) => ScheduleSlot(
        id: json['id'] as String,
        startTime: TimeOfDay(
            hour: json['startHour'] as int, minute: json['startMinute'] as int),
        endTime: TimeOfDay(
            hour: json['endHour'] as int, minute: json['endMinute'] as int),
        daysOfWeek: List<int>.from(json['daysOfWeek'] as List),
        isActive: json['isActive'] as bool,
      );

  ScheduleSlot copyWith({
    String? id,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    List<int>? daysOfWeek,
    bool? isActive,
  }) =>
      ScheduleSlot(
        id: id ?? this.id,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        daysOfWeek: daysOfWeek ?? this.daysOfWeek,
        isActive: isActive ?? this.isActive,
      );
}
