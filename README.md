# Game Party

แอป Flutter สำหรับหาเพื่อนร่วมทีม สร้างโพสต์ชวนเล่นเกม ส่งคำขอเข้าร่วมทีม แชต แสดงความรู้สึกต่อโพสต์ และรายงานเนื้อหาที่ไม่เหมาะสม ผู้ดูแลระบบสามารถตรวจสอบรายงานและจัดการสมาชิกได้

## สิ่งที่ต้องมี

- Flutter SDK ที่ใช้ Dart 3.3 ขึ้นไป
- Android Studio พร้อม Android SDK หรือ Xcode บน macOS สำหรับสร้างแอป iOS
- โปรเจกต์ Firebase ที่ตั้งค่าสำหรับ Android, iOS และ Web ตามแพลตฟอร์มที่ต้องการ
- Node.js สำหรับ Firebase Cloud Functions

## เริ่มใช้งานในเครื่อง

```sh
flutter pub get
flutter run
```

แอปใช้การตั้งค่า Firebase จาก `lib/firebase_options.dart` และไฟล์ Firebase สำหรับ Android ที่ `android/app/google-services.json` หากต้องการเชื่อมกับ Firebase โปรเจกต์อื่น ให้เปลี่ยนไฟล์เหล่านี้เป็นค่าจากโปรเจกต์ของคุณ

## สร้างไฟล์ APK สำหรับ Android

ใช้คำสั่งนี้เพื่อสร้างไฟล์ติดตั้ง APK:

```sh
flutter build apk --release
```

ไฟล์ที่ได้อยู่ที่ `build/app/outputs/flutter-apk/app-release.apk`

ขณะนี้การตั้งค่า Android ใช้ debug key ในการเซ็นไฟล์ release หากต้องการเผยแพร่แอปจริงหรือส่งขึ้น Google Play ให้ตั้งค่า release keystore ส่วนตัวก่อน ห้ามนำ keystore หรือรหัสผ่านสำหรับเซ็นไฟล์ขึ้น Git

## iOS และ TestFlight

การสร้างแอป iOS และอัปโหลดขึ้น TestFlight ต้องใช้ macOS ที่ติดตั้ง Xcode, บัญชี Apple Developer Program, Bundle ID ที่ไม่ซ้ำ และการตั้งค่า signing กับ provisioning profile บนเครื่อง Mac:

1. ตั้งค่า Firebase สำหรับแอป iOS และเพิ่มไฟล์ `ios/Runner/GoogleService-Info.plist` ของ Firebase โปรเจกต์ที่ใช้
2. ตั้ง Bundle ID และทีม signing ใน Xcode (`ios/Runner.xcworkspace`)
3. สร้างไฟล์ IPA ด้วย `flutter build ipa --release`
4. อัปโหลด IPA ผ่าน Xcode Organizer หรือ Transporter จากนั้นเพิ่มแอปให้กลุ่มทดสอบใน App Store Connect

## ตั้งค่า Firebase

รันคำสั่งต่อไปนี้จากโฟลเดอร์หลักของโปรเจกต์เพื่อ deploy Firestore Rules และ Cloud Functions:

```sh
firebase deploy --only firestore:rules,functions
```

สร้างเอกสาร `admins/{Firebase Auth UID}` ใน Firestore เพื่อให้สิทธิ์ผู้ดูแลระบบ เมื่อมีผู้รายงานโพสต์ ระบบจะแจ้งเจ้าของโพสต์และส่งการแจ้งเตือนไปยังผู้ดูแลผ่าน Cloud Functions ส่วน badge บนไอคอนโล่แอดมินจะแสดงจำนวนรายงานที่รอตรวจสอบ

## โครงสร้างโปรเจกต์

- `lib/` — โค้ดแอป Flutter
- `firestore.rules` — กฎการเข้าถึง Firestore
- `functions/` — Firebase Cloud Functions
- `android/` — โปรเจกต์ Android
- `web/` — โปรเจกต์ Web

## หมายเหตุ

ห้าม commit service-account key, signing credentials หรือไฟล์ environment ที่มีข้อมูลลับ ไฟล์ตั้งค่า Firebase ฝั่งแอปถูกรวมไว้ในโปรเจกต์นี้แล้ว สำหรับการใช้งานจริง ควรตั้งค่า Firebase Security Rules และข้อจำกัด API ให้เหมาะสม
