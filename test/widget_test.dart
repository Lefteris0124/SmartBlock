import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_block/main.dart' show LoginScreen;

void main() {
  testWidgets('login screen renders and switches language', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('SmartBlock'), findsOneWidget);
    expect(find.text('Σύνδεση'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Building management, made simple.'), findsOneWidget);
  });

  testWidgets('login screen can open account creation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    final createAccountLink = find.text('New to SmartBlock? Create an account');
    await tester.ensureVisible(createAccountLink);
    await tester.tap(createAccountLink);
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
  });
}
