import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/widgets/metric_card.dart';
import 'package:homelab_tablet/core/widgets/status_tone.dart';

void main() {
  testWidgets('metric card allows opt-in multiline values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: MetricCard(
              title: 'Model',
              value: 'NVIDIA GeForce GTX 1070',
              maxValueLines: 2,
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('NVIDIA GeForce GTX 1070'));

    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('metric card can color the value independently', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MetricCard(
            title: 'CPU Usage',
            value: '88%',
            valueTone: StatusTone.critical,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('88%'));

    expect(text.style?.color, toneColor(StatusTone.critical));
  });
}
