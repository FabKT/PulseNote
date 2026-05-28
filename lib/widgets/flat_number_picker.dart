import 'package:flutter/material.dart';

import '../ui/app_theme.dart';

class FlatNumberPicker extends StatefulWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  const FlatNumberPicker({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  State<FlatNumberPicker> createState() => _FlatNumberPickerState();
}

class _FlatNumberPickerState extends State<FlatNumberPicker> {
  static const int _initialLoop = 500;
  late PageController _controller;

  int get _span => widget.max + 1;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      initialPage: _pageFor(widget.value),
      viewportFraction: 0.34,
    );
  }

  @override
  void didUpdateWidget(covariant FlatNumberPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.max != widget.max) {
      _controller.dispose();
      _controller = PageController(
        initialPage: _pageFor(widget.value),
        viewportFraction: 0.34,
      );
      return;
    }
    if (!_controller.hasClients) return;
    final page = _controller.page?.round() ?? _pageFor(oldWidget.value);
    if (_valueFor(page) == widget.value) return;
    _controller
        .jumpToPage(page + _shortestDelta(_valueFor(page), widget.value));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _pageFor(int value) => _span * _initialLoop + value;

  int _valueFor(int page) {
    final value = page % _span;
    return value < 0 ? value + _span : value;
  }

  int _shortestDelta(int from, int to) {
    var delta = to - from;
    if (delta > _span / 2) delta -= _span;
    if (delta < -_span / 2) delta += _span;
    return delta;
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      scrollDirection: Axis.vertical,
      physics: const BouncingScrollPhysics(),
      onPageChanged: (page) {
        final value = _valueFor(page);
        if (value != widget.value) widget.onChanged(value);
      },
      itemBuilder: (_, page) {
        final value = _valueFor(page);
        final selected = value == widget.value;
        return Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 120),
            style: TextStyle(
              color: selected
                  ? AppTheme.text
                  : AppTheme.textMuted.withValues(alpha: 0.28),
              fontSize: selected ? 42 : 34,
              fontWeight: selected ? FontWeight.w400 : FontWeight.w300,
              height: 1,
            ),
            child: Text(
              value.toString().padLeft(2, '0'),
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}
