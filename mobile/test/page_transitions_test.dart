import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:homelab_tablet/core/routing/page_transitions.dart';

void main() {
  testWidgets('fade slide transition page renders route content', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => buildFadeSlidePage(
            state: state,
            child: const Text('Animated route'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Animated route'), findsOneWidget);
  });
}
