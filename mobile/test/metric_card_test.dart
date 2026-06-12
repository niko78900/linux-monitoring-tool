import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_tablet/core/widgets/metric_card.dart';

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
}
