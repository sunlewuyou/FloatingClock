import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/time_precision.dart';
import '../models/time_source.dart';

/// A high-frequency clock display isolated from the surrounding page tree.
///
/// The parent owns [tick] and updates it at the selected display precision.
/// Only this widget rebuilds for each tick; controls, source lists and cards
/// elsewhere on the page are not rebuilt 10 or 100 times per second.
class ClockTimeText extends StatelessWidget {
  const ClockTimeText({
    super.key,
    required this.tick,
    required this.source,
    required this.precision,
    required this.fractionColor,
    this.style,
    this.textAlign,
  });

  final ValueListenable<int> tick;
  final TimeSource source;
  final TimePrecision precision;
  final Color fractionColor;
  final TextStyle? style;
  final TextAlign? textAlign;

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tick,
      builder: (context, _, child) {
        final now = DateTime.now().add(
          Duration(milliseconds: source.offsetMillis),
        );
        final fraction = precision == TimePrecision.centisecond
            ? (now.millisecond ~/ 10).toString().padLeft(2, '0')
            : (now.millisecond ~/ 100).toString();
        final prefix =
            '${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}';

        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$prefix.'),
              TextSpan(
                text: fraction,
                style: (style ?? const TextStyle()).copyWith(
                  color: fractionColor,
                ),
              ),
            ],
          ),
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        );
      },
    );
  }
}
