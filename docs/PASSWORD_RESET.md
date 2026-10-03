# Password reset

On Sign In, choose **Forgot Password?**. The sheet prefills the entered email.
Submit a registered email, then check the inbox and spam folder. Open the link,
choose a new password on Firebase's hosted reset page, and return to Sign In.
No app deep link is required for this flow.

The confirmation is intentionally conditional: Firebase projects with email
enumeration protection may accept an unknown email without sending anything.
The app gives the same response if an older project returns `user-not-found`.
Network, rate-limit, and configuration errors remain failures and can be retried.

## Firebase setup and delivery checks

- Configure the target platform with `flutterfire configure` using the same
  Firebase project as account registration. Android and web currently target
  `gym-manager-e2002`; iOS, macOS, and Windows still have placeholder options in
  `lib/firebase_options.dart` and need their own registered Firebase apps.
- In Firebase Authentication, enable the Email/Password provider.
- In Authentication > Templates > Password reset, check the sender and action
  URL. The default handler is
  `https://gym-manager-e2002.firebaseapp.com/__/auth/action`. If using a custom
  handler, it must verify the action code and confirm the new password.
- Use a registered test account to verify receipt, changing the password, and
  signing in with the new password. Confirm that the old password fails, and
  that a used or expired reset link is rejected. If no email arrives, check spam,
  project/account selection, throttling, and Firebase template configuration.

The repository checks use a fake Firebase platform and do not send real emails
or change real accounts. They cover validation, recipient consistency, keyboard
submission, retryable failures, safe dismissal, and small-screen layouts.

```sh
flutter test test/forgot_password_test.dart
flutter test test/back_navigation_test.dart --plain-name "forgot password closes back to sign in"
```

References: [Flutter password reset](https://firebase.google.com/docs/auth/flutter/manage-users#send_a_password_reset_email)
and [email enumeration protection](https://cloud.google.com/identity-platform/docs/admin/email-enumeration-protection).
