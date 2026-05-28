import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum AudioPlaybackRecurrence { once, weekly }

class AudioPlaybackScheduleModel {
  final String id;
  final String recordingId;
  final TimeOfDay time;
  final AudioPlaybackRecurrence recurrence;
  final DateTime? date;
  final List<int> weekdays;
  final bool isActive;
  final String? lastPlayedDateKey;

  const AudioPlaybackScheduleModel({
    required this.id,
    required this.recordingId,
    required this.time,
    this.recurrence = AudioPlaybackRecurrence.once,
    this.date,
    this.weekdays = const [],
    this.isActive = true,
    this.lastPlayedDateKey,
  });

  bool shouldPlayAt(DateTime now) {
    if (!isActive) return false;
    if (time.hour != now.hour || time.minute != now.minute) return false;
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    if (lastPlayedDateKey == todayKey) return false;

    return switch (recurrence) {
      AudioPlaybackRecurrence.once =>
        date != null && DateFormat('yyyy-MM-dd').format(date!) == todayKey,
      AudioPlaybackRecurrence.weekly => weekdays.contains(now.weekday),
    };
  }

  String get occurrenceLabel {
    final timeLabel =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    if (recurrence == AudioPlaybackRecurrence.once) {
      final dateLabel = date == null
          ? 'Date non d\u00e9finie'
          : DateFormat('dd/MM/yyyy').format(date!);
      return '$dateLabel \u00e0 $timeLabel';
    }
    final labels = weekdays.map(_weekdayLabel).join(', ');
    return '${labels.isEmpty ? 'Aucun jour' : labels} \u00e0 $timeLabel';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'recordingId': recordingId,
        'hour': time.hour,
        'minute': time.minute,
        'recurrence': recurrence.name,
        'date': date == null ? null : DateFormat('yyyy-MM-dd').format(date!),
        'weekdays': weekdays,
        'isActive': isActive,
        'lastPlayedDateKey': lastPlayedDateKey,
      };

  factory AudioPlaybackScheduleModel.fromJson(Map<String, dynamic> json) {
    final recurrence = AudioPlaybackRecurrence.values.firstWhere(
      (r) => r.name == json['recurrence'],
      orElse: () => AudioPlaybackRecurrence.weekly,
    );
    final dateValue = json['date'] as String?;
    return AudioPlaybackScheduleModel(
      id: json['id'] as String,
      recordingId: json['recordingId'] as String,
      time: TimeOfDay(
        hour: json['hour'] as int,
        minute: json['minute'] as int,
      ),
      recurrence: recurrence,
      date: dateValue == null ? null : DateTime.tryParse(dateValue),
      weekdays: List<int>.from(
        json['weekdays'] as List? ?? const [1, 2, 3, 4, 5, 6, 7],
      ),
      isActive: json['isActive'] as bool? ?? true,
      lastPlayedDateKey: json['lastPlayedDateKey'] as String?,
    );
  }

  AudioPlaybackScheduleModel copyWith({
    String? id,
    String? recordingId,
    TimeOfDay? time,
    AudioPlaybackRecurrence? recurrence,
    DateTime? date,
    List<int>? weekdays,
    bool? isActive,
    String? lastPlayedDateKey,
  }) =>
      AudioPlaybackScheduleModel(
        id: id ?? this.id,
        recordingId: recordingId ?? this.recordingId,
        time: time ?? this.time,
        recurrence: recurrence ?? this.recurrence,
        date: date ?? this.date,
        weekdays: weekdays ?? this.weekdays,
        isActive: isActive ?? this.isActive,
        lastPlayedDateKey: lastPlayedDateKey ?? this.lastPlayedDateKey,
      );

  static String _weekdayLabel(int day) => switch (day) {
        1 => 'Lun',
        2 => 'Mar',
        3 => 'Mer',
        4 => 'Jeu',
        5 => 'Ven',
        6 => 'Sam',
        7 => 'Dim',
        _ => '',
      };
}
