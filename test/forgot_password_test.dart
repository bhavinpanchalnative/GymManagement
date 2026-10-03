import 'dart:async';

import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym/screens/auth/auth_screen.dart';
import 'package:gym/screens/auth/forgot_password_sheet.dart';
import 'package:gym/services/auth_service.dart';
import 'package:gym/utils/email_validator.dart';

class _ResetAuthPlatform extends FirebaseAuthPlatform {
  final emails = <String>[];
  Future<void> Function()? send;

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) => this;

  @override
  UserPlatform? get currentUser => null;

  @override
  Future<void> sendPasswordResetEmail(
    String email, [
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    emails.add(email);
    await send?.call();
  }
}

Future<void> _openSheet(WidgetTester tester, {String? email}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                ForgotPasswordSheet.show(context, initialEmail: email),
            child: const Text('Open reset'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open reset'));
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  final button = find.widgetWithText(ElevatedButton, 'Send Reset Instructions');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = _ResetAuthPlatform();

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = auth;
  });

  setUp(() {
    auth.emails.clear();
    auth.send = null;
  });

  test('reset service trims the email before sending to Firebase', () async {
    await AuthService().sendPasswordResetEmail(email: ' owner@example.com ');
    expect(auth.emails, ['owner@example.com']);
  });

  test(
    'email validation supports apostrophes and international domain encoding',
    () {
      expect(isValidEmailAddress("o'connor@example.com"), true);
      expect(isValidEmailAddress('owner@example.xn--p1ai'), true);
    },
  );

  testWidgets('valid plus-addressed email can request a reset', (tester) async {
    await _openSheet(tester, email: ' owner+gym@example.com ');
    await _submit(tester);
    await tester.pumpAndSettle();

    expect(auth.emails, ['owner+gym@example.com']);
    expect(find.text('Check Your Email'), findsOneWidget);
    expect(find.textContaining('owner+gym@example.com'), findsOneWidget);
  });

  for (final email in [
    '',
    'owner',
    'owner@@example.com',
    'owner @example.com',
    'owner..name@example.com',
    'owner@example',
    'owner@-example.com',
  ]) {
    testWidgets('invalid email "$email" does not send a reset', (tester) async {
      await _openSheet(tester, email: email);
      await _submit(tester);
      await tester.pumpAndSettle();

      expect(auth.emails, isEmpty);
      expect(find.textContaining('Please enter'), findsOneWidget);
    });
  }

  testWidgets('pending reset freezes email and prevents repeated submission', (
    tester,
  ) async {
    final pending = Completer<void>();
    auth.send = () => pending.future;
    await _openSheet(tester, email: 'owner@example.com');
    final submitFromKeyboard = tester
        .widget<TextField>(find.byType(TextField))
        .onSubmitted!;
    await _submit(tester);

    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      false,
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    submitFromKeyboard('owner@example.com');
    await tester.pump();
    expect(auth.emails, ['owner@example.com']);

    // A late controller/autofill update must not change the confirmation.
    tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text =
        'other@example.com';

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('owner@example.com'), findsOneWidget);
    await tester.tap(find.text('Back to Sign In'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordSheet), findsNothing);
  });

  testWidgets('keyboard Done submits a reset request', (tester) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextFormField), 'owner@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(auth.emails, ['owner@example.com']);
  });

  for (final code in ['network-request-failed', 'too-many-requests']) {
    testWidgets('$code is readable and the request can be retried', (
      tester,
    ) async {
      auth.send = () async => throw FirebaseAuthException(code: code);
      await _openSheet(tester, email: 'owner@example.com');
      await _submit(tester);
      await tester.pumpAndSettle();

      expect(
        find.text(
          AuthService().getReadableErrorMessage(
            FirebaseAuthException(code: code),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Check Your Email'), findsNothing);
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        true,
      );

      auth.send = null;
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(auth.emails, ['owner@example.com', 'owner@example.com']);
      expect(find.text('Check Your Email'), findsOneWidget);
    });
  }

  testWidgets('unknown account gets the same neutral confirmation', (
    tester,
  ) async {
    auth.send = () async => throw FirebaseAuthException(code: 'user-not-found');
    await _openSheet(tester, email: 'unknown@example.com');
    await _submit(tester);
    await tester.pumpAndSettle();
    expect(find.text('Check Your Email'), findsOneWidget);
    expect(find.textContaining('If an account exists'), findsOneWidget);
    expect(find.textContaining('No account found'), findsNothing);
  });

  for (final error in [
    FirebaseAuthException(code: 'invalid-api-key'),
    FirebaseAuthException(code: 'operation-not-allowed'),
    FirebaseException(
      plugin: 'firebase_auth',
      message: 'internal configuration',
    ),
  ]) {
    testWidgets('${error.code} fails without a false success or raw error', (
      tester,
    ) async {
      auth.send = () async => throw error;
      await _openSheet(tester, email: 'owner@example.com');
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Check Your Email'), findsNothing);
      expect(find.textContaining('Firebase'), findsNothing);
      expect(find.textContaining('Offline Mode'), findsNothing);
      expect(find.textContaining('internal configuration'), findsNothing);
      expect(find.textContaining('Please'), findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
    });
  }

  for (final tab in ['Sign In', 'Sign Up']) {
    testWidgets(
      '$tab accepts the same plus-addressed email as password reset',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
        await tester.pumpAndSettle();
        if (tab == 'Sign Up') {
          await tester.tap(find.text('Create Account').first);
          await tester.pumpAndSettle();
        }
        final emailField = find.widgetWithText(TextFormField, 'Email Address');
        await tester.enterText(emailField, 'owner+gym@example.com');
        expect(
          tester.state<FormFieldState<String>>(emailField).validate(),
          true,
        );
        expect(auth.emails, isEmpty);
      },
    );
  }

  for (final fails in [false, true]) {
    testWidgets(
      'closing during a ${fails ? 'failed' : 'successful'} request is safe',
      (tester) async {
        final pending = Completer<void>();
        auth.send = () => pending.future;
        await _openSheet(tester, email: 'owner@example.com');
        await _submit(tester);
        await tester.tap(find.byIcon(Icons.close_rounded));
        // A pending request keeps animating its spinner while the route exits.
        await tester.pumpAndSettle();
        expect(find.byType(ForgotPasswordSheet), findsNothing);

        if (fails) {
          pending.completeError(
            FirebaseAuthException(code: 'network-request-failed'),
          );
        } else {
          pending.complete();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('reset remains usable on a small phone with the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await _openSheet(tester, email: 'owner@example.com');
    await _submit(tester);
    await tester.pumpAndSettle();
    expect(auth.emails, ['owner@example.com']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-in Forgot Password prefills the entered email', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'owner@example.com',
    );
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordSheet), findsOneWidget);
    final field = find.descendant(
      of: find.byType(ForgotPasswordSheet),
      matching: find.byType(TextFormField),
    );
    expect(
      tester.widget<TextFormField>(field).controller!.text,
      'owner@example.com',
    );
  });
}
