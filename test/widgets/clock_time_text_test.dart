import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:floating_clock/models/time_precision.dart';
import 'package:floating_clock/models/time_source.dart';
import 'package:floating_clock/widgets/clock_time_text.dart';

void main() {
  group('ClockTimeText', () {
    late ValueNotifier<int> tick;

    setUp(() {
      tick = ValueNotifier<int>(0);
    });

    tearDown(() {
      tick.dispose();
    });

    Future<String> renderText(
      WidgetTester tester, {
      required TimePrecision precision,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ClockTimeText(
                tick: tick,
                source: TimeSource.system(),
                precision: precision,
                fractionColor: Colors.red,
              ),
            ),
          ),
        ),
      );
      final richText = tester.widget<RichText>(find.byType(RichText));
      return richText.text.toPlainText();
    }

    testWidgets('centisecond precision renders two fractional digits',
        (tester) async {
      final text = await renderText(
        tester,
        precision: TimePrecision.centisecond,
      );

      expect(text, matches(RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{2}$')));
    });

    testWidgets('decisecond precision renders one fractional digit',
        (tester) async {
      final text = await renderText(
        tester,
        precision: TimePrecision.decisecond,
      );

      expect(text, matches(RegExp(r'^\d{2}:\d{2}:\d{2}\.\d$')));
    });

    testWidgets('a tick refreshes the clock display subtree', (tester) async {
      await renderText(tester, precision: TimePrecision.centisecond);
      tick.value++;
      await tester.pump();

      expect(find.byType(ClockTimeText), findsOneWidget);
      expect(find.byType(RichText), findsOneWidget);
    });
  });
}
