import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';

void main() {
  testWidgets('app boots without crashing', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Basic sanity: MaterialApp exists
    expect(find.byType(MaterialApp), findsOneWidget);

    // Basic sanity: we have at least one Scaffold on screen
    expect(find.byType(Scaffold), findsWidgets);
  });
}
