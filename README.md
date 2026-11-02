# Game Party

Flutter app for finding teammates, creating game posts, sending join requests, chatting, reacting to posts, and reporting inappropriate content. Administrators can review reports and manage members.

## Requirements

- Flutter SDK compatible with Dart 3.3 or newer
- Android Studio with Android SDK, or Xcode on macOS for iOS builds
- A Firebase project configured for Android, iOS, and Web as needed
- Node.js for Firebase Cloud Functions

## Run locally

```sh
flutter pub get
flutter run
```

The app uses the Firebase settings in `lib/firebase_options.dart` and the Android Firebase configuration in `android/app/google-services.json`. Replace these with configuration from your own Firebase project before using this code with a different backend.

## Android APK

Build an installable release APK:

```sh
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

The current Android release configuration signs with the debug key. Configure a private release keystore before distributing the APK publicly or through Google Play. Do not commit keystores or signing passwords.

## iOS and TestFlight

iOS builds and TestFlight uploads require macOS with Xcode, an Apple Developer Program team, a unique bundle identifier, and valid signing/provisioning settings. On the Mac:

1. Configure the iOS Firebase app and `ios/Runner/GoogleService-Info.plist` for your Firebase project.
2. Set the bundle identifier and signing team in Xcode (`ios/Runner.xcworkspace`).
3. Run `flutter build ipa --release`.
4. Upload the generated IPA using Xcode Organizer or Transporter, then add it to a TestFlight group in App Store Connect.

## Firebase setup

Deploy Firestore rules and Cloud Functions from the project root:

```sh
firebase deploy --only firestore:rules,functions
```

Create an `admins/{Firebase Auth UID}` document in Firestore to grant admin access. A report creates a notification for the post owner and triggers an admin notification through Cloud Functions. Pending reports are counted on the admin shield badge.

## Project layout

- `lib/` — Flutter application
- `firestore.rules` — Firestore access rules
- `functions/` — Firebase Cloud Functions
- `android/` — Android project
- `web/` — Web project

## Notes

Do not commit private service-account keys, signing credentials, or local environment files. Firebase client configuration is included for this project; apply appropriate Firebase Security Rules and API restrictions for production.
