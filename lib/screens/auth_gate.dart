/// ตัวคัดกรองสถานะบัญชีผู้ใช้ ฟัง Firebase Auth แล้วเลือกหน้าเข้าสู่ระบบหรือหน้าแอป.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'login_screen.dart';

/// ใช้ authStateChanges เป็นแหล่งสถานะจริง จึงเปลี่ยนหน้าอัตโนมัติเมื่อ login/logout.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // --------------------------------
        // กำลังตรวจสอบสถานะ Login
        // --------------------------------
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoadingScreen();
        }

        // --------------------------------
        // กรณี Firebase Auth เกิด Error
        // --------------------------------
        if (snapshot.hasError) {
          return _AuthErrorScreen(
            error: snapshot.error.toString(),
          );
        }

        // --------------------------------
        // ยังไม่ได้ Login
        // --------------------------------
        if (snapshot.data == null) {
          return const LoginScreen();
        }

        // --------------------------------
        // Login สำเร็จ
        // --------------------------------
        return const HomeScreen();
      },
    );
  }
}

// ======================================================
// Loading Screen
// ======================================================

/// หน้าระหว่างรอ Firebase ตรวจสอบ session ที่อาจบันทึกไว้จากครั้งก่อน.
class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C13),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: const Color(0xFF9B7CFF),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9B7CFF).withValues(
                      alpha: 0.20,
                    ),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.groups_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Game Party',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFFF7F5FF),
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'กำลังเตรียมพื้นที่สำหรับคุณ...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 28),

            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF9B7CFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================
// Error Screen
// ======================================================

/// แสดงข้อผิดพลาดจากการตรวจ session เพื่อไม่ปล่อยหน้าว่างเมื่อ Auth มีปัญหา.
class _AuthErrorScreen extends StatelessWidget {
  final String error;

  const _AuthErrorScreen({
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C13),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(
                        alpha: 0.10,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.red,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'เกิดข้อผิดพลาด',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'ไม่สามารถตรวจสอบสถานะบัญชีได้',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const AuthGate(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.refresh_rounded,
                    ),
                    label: const Text('ลองอีกครั้ง'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
