import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../ui/app_theme.dart';

class AudioWaveform extends StatefulWidget {
  final List<double> samples;
  final double liveLevel;
  final bool active;
  final bool circular;
  final double height;
  final Color color;
  final double progress;
  final ValueChanged<double>? onSeekFraction;

  const AudioWaveform({
    super.key,
    required this.samples,
    this.liveLevel = 0,
    this.active = false,
    this.circular = false,
    this.height = 96,
    this.color = AppTheme.primary,
    this.progress = 0,
    this.onSeekFraction,
  });

  @override
  State<AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waveform = SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) => CustomPaint(
          painter: _WaveformPainter(
            samples: widget.samples,
            liveLevel: widget.liveLevel,
            active: widget.active,
            circular: widget.circular,
            progress: _pulse.value,
            playbackProgress: widget.progress,
            color: widget.color,
          ),
        ),
      ),
    );

    if (widget.onSeekFraction == null || widget.circular) return waveform;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _seek(details.localPosition.dx, context),
      onHorizontalDragUpdate: (details) =>
          _seek(details.localPosition.dx, context),
      child: waveform,
    );
  }

  void _seek(double dx, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return;
    widget.onSeekFraction?.call((dx / box.size.width).clamp(0.0, 1.0));
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final double liveLevel;
  final bool active;
  final bool circular;
  final double progress;
  final double playbackProgress;
  final Color color;

  const _WaveformPainter({
    required this.samples,
    required this.liveLevel,
    required this.active,
    required this.circular,
    required this.progress,
    required this.playbackProgress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (circular) {
      _paintCircular(canvas, size);
    } else {
      _paintLinear(canvas, size);
    }
  }

  void _paintCircular(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final shortest = math.min(size.width, size.height);
    final radius = shortest * 0.25;
    final outerRadius = shortest * 0.47;
    final level = active ? liveLevel.clamp(0.0, 1.0) : 0.12;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: active ? 0.22 : 0.10);

    for (var i = 0; i < 3; i++) {
      final wave = ((progress + i / 3) % 1.0);
      canvas.drawCircle(
        center,
        radius + wave * shortest * 0.15 + level * shortest * 0.08,
        ringPaint..color = color.withValues(alpha: (1 - wave) * 0.18),
      );
    }

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: active ? 0.28 + level * 0.22 : 0.12),
          AppTheme.blue.withValues(alpha: active ? 0.12 : 0.04),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 2.2));
    canvas.drawCircle(center, radius * 2.1, glowPaint);

    final discPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppTheme.surfaceHigh,
          AppTheme.surface,
          color.withValues(alpha: active ? 0.22 : 0.08),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius + level * 12, discPaint);

    final bars = _displaySamples(72);
    final barPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;

    for (var i = 0; i < bars.length; i++) {
      final angle = (i / bars.length) * math.pi * 2 - math.pi / 2;
      final sample = bars[i];
      final animatedLift =
          active ? math.sin(progress * math.pi * 2 + i) * 0.06 : 0;
      final value = (sample + level * 0.6 + animatedLift).clamp(0.06, 1.0);
      final startRadius = radius + shortest * 0.10;
      final endRadius =
          math.min(startRadius + shortest * (0.06 + value * 0.16), outerRadius);
      final start = Offset(
        center.dx + math.cos(angle) * startRadius,
        center.dy + math.sin(angle) * startRadius,
      );
      final end = Offset(
        center.dx + math.cos(angle) * endRadius,
        center.dy + math.sin(angle) * endRadius,
      );
      barPaint.color = Color.lerp(
        color.withValues(alpha: 0.32),
        AppTheme.accent.withValues(alpha: 0.86),
        value,
      )!;
      canvas.drawLine(start, end, barPaint);
    }

    final iconPaint = Paint()
      ..color = active ? color : AppTheme.textMuted.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 7 + level * 5, iconPaint);
  }

  void _paintLinear(Canvas canvas, Size size) {
    final bars = _displaySamples(56);
    final centerY = size.height / 2;
    const gap = 3.0;
    final barWidth =
        math.max(2.0, (size.width - gap * (bars.length - 1)) / bars.length);
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < bars.length; i++) {
      final value = bars[i].clamp(0.04, 1.0);
      final height = 8 + value * (size.height - 14);
      final x = i * (barWidth + gap) + barWidth / 2;
      final played = i / bars.length <= playbackProgress.clamp(0.0, 1.0);
      paint
        ..strokeWidth = barWidth
        ..color = played
            ? Color.lerp(
                color.withValues(alpha: 0.78),
                AppTheme.accent.withValues(alpha: 0.96),
                value,
              )!
            : Color.lerp(
                AppTheme.line.withValues(alpha: 0.62),
                color.withValues(alpha: 0.36),
                value,
              )!;
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  List<double> _displaySamples(int count) {
    if (samples.isEmpty) return _fallbackSamples(count);
    if (samples.length == count) return samples;
    return List.generate(count, (index) {
      final source = (index / count * samples.length).floor();
      return samples[source.clamp(0, samples.length - 1)];
    });
  }

  List<double> _fallbackSamples(int count) {
    return List.generate(count, (i) {
      final base = math.sin(i * 0.55) * 0.26 + math.sin(i * 0.17) * 0.18;
      final pulse = active
          ? liveLevel * (0.35 + math.sin(progress * math.pi * 2 + i) * 0.12)
          : 0;
      return (0.24 + base.abs() + pulse).clamp(0.04, 1.0);
    });
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.liveLevel != liveLevel ||
        oldDelegate.active != active ||
        oldDelegate.progress != progress ||
        oldDelegate.playbackProgress != playbackProgress ||
        oldDelegate.color != color ||
        oldDelegate.circular != circular;
  }
}
