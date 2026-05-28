import 'package:flutter/material.dart';

import '../ui/app_theme.dart';
import 'flat_number_picker.dart';

class CustomTimePicker {
  static Future<({TimeOfDay start, TimeOfDay end})?> show(
    BuildContext context, {
    TimeOfDay? initialStart,
    TimeOfDay? initialEnd,
  }) {
    return showModalBottomSheet<({TimeOfDay start, TimeOfDay end})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TimePickerSheet(
        initialStart: initialStart ?? const TimeOfDay(hour: 18, minute: 0),
        initialEnd: initialEnd ?? const TimeOfDay(hour: 22, minute: 0),
      ),
    );
  }
}

class _TimePickerSheet extends StatefulWidget {
  final TimeOfDay initialStart;
  final TimeOfDay initialEnd;

  const _TimePickerSheet({
    required this.initialStart,
    required this.initialEnd,
  });

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  late int _sh;
  late int _sm;
  late int _eh;
  late int _em;

  @override
  void initState() {
    super.initState();
    _sh = widget.initialStart.hour;
    _sm = widget.initialStart.minute;
    _eh = widget.initialEnd.hour;
    _em = widget.initialEnd.minute;
  }

  String get _duration {
    var diff = (_eh * 60 + _em) - (_sh * 60 + _sm);
    if (diff <= 0) diff += 1440;
    final h = diff ~/ 60;
    final m = diff % 60;
    return m == 0 ? '${h}h' : '${h}h ${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Choisir les horaires',
            style: TextStyle(
              color: AppTheme.text,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _TimeColumn(
                  label: 'DÉBUT',
                  hour: _sh,
                  minute: _sm,
                  onChanged: (h, m) => setState(() {
                    _sh = h;
                    _sm = m;
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(children: [
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _duration,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: _TimeColumn(
                  label: 'FIN',
                  hour: _eh,
                  minute: _em,
                  onChanged: (h, m) => setState(() {
                    _eh = h;
                    _em = m;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: AppTheme.line),
                  foregroundColor: AppTheme.textMuted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Annuler'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, (
                  start: TimeOfDay(hour: _sh, minute: _sm),
                  end: TimeOfDay(hour: _eh, minute: _em),
                )),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Confirmer'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  final String label;
  final int hour;
  final int minute;
  final void Function(int h, int m) onChanged;

  const _TimeColumn({
    required this.label,
    required this.hour,
    required this.minute,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 176,
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.line),
          ),
          child: Stack(children: [
            Center(
              child: Container(
                height: 56,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            Row(children: [
              Expanded(
                child: FlatNumberPicker(
                  value: hour,
                  max: 23,
                  onChanged: (v) => onChanged(v, minute),
                ),
              ),
              const Text(
                ':',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 34,
                  fontWeight: FontWeight.w300,
                ),
              ),
              Expanded(
                child: FlatNumberPicker(
                  value: minute,
                  max: 59,
                  onChanged: (v) => onChanged(hour, v),
                ),
              ),
            ]),
          ]),
        ),
      ],
    );
  }
}
