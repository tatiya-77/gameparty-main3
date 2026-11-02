/// หน้าสมัครและเข้าสู่ระบบด้วย Firebase Authentication รวมถึงการขอรีเซ็ตรหัสผ่าน.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// เก็บค่าฟอร์มและสถานะกำลังทำงาน; controller ทั้งหมดต้อง dispose เมื่อปิดหน้า.
class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();

  bool _isRegister = false;
  bool _isBusy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  /// ตรวจข้อมูลก่อน แล้วเลือกสมัครบัญชีหรือเข้าสู่ระบบตาม _isRegister จากนั้นรายงานผลให้ผู้ใช้.
  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final displayName = _displayName.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('กรุณากรอกอีเมลและรหัสผ่าน');
      return;
    }

    if (_isRegister && displayName.isEmpty) {
      _showMessage('กรุณากรอกชื่อที่แสดง');
      return;
    }

    if (_isRegister && displayName.length < 2) {
      _showMessage('ชื่อที่แสดงควรมีอย่างน้อย 2 ตัวอักษร');
      return;
    }

    setState(() => _isBusy = true);

    try {
      final auth = FirebaseAuth.instance;

      if (_isRegister) {
        final credential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final user = credential.user;

        if (user == null) {
          throw Exception('ไม่พบข้อมูลบัญชีหลังสมัครสมาชิก');
        }

        // บันทึกชื่อใน Firebase Authentication
        await user.updateDisplayName(displayName);

        // บันทึกข้อมูลโปรไฟล์ด้วย UID ของเจ้าของบัญชี
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'displayName': displayName,
          'email': email,
          'isPrivate': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await user.reload();

        if (!mounted) return;
        _showMessage('สมัครสมาชิกสำเร็จ 🎉');
      } else {
        await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'invalid-email':
          message = 'รูปแบบอีเมลไม่ถูกต้อง';
          break;
        case 'user-not-found':
          message = 'ไม่พบบัญชีนี้';
          break;
        case 'wrong-password':
        case 'invalid-credential':
          message = 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
          break;
        case 'email-already-in-use':
          message = 'อีเมลนี้ถูกใช้งานแล้ว';
          break;
        case 'weak-password':
          message = 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
          break;
        case 'network-request-failed':
          message = 'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้';
          break;
        case 'too-many-requests':
          message = 'ดำเนินการบ่อยเกินไป กรุณารอสักครู่';
          break;
        case 'operation-not-allowed':
          message = 'กรุณาเปิดใช้งาน Email/Password ใน Firebase';
          break;
        default:
          message = e.message ?? 'ดำเนินการไม่สำเร็จ';
      }

      _showMessage(message);
    } on FirebaseException catch (e) {
      if (!mounted) return;

      if (e.code == 'permission-denied') {
        _showMessage(
          'สมัครบัญชีแล้ว แต่ไม่มีสิทธิ์บันทึกโปรไฟล์ใน Firestore '
          'กรุณาตรวจสอบ Firestore Rules',
        );
      } else {
        _showMessage('บันทึกข้อมูลไม่สำเร็จ (${e.code})');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('เกิดข้อผิดพลาด กรุณาลองใหม่');
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// ส่งอีเมลลิงก์รีเซ็ตรหัสผ่านผ่าน Firebase Auth หลังตรวจรูปแบบอีเมลเบื้องต้น.
  Future<void> _resetPassword() async {
    final email = _email.text.trim();

    if (email.isEmpty) {
      _showMessage('กรุณากรอกอีเมลก่อนรีเซ็ตรหัสผ่าน');
      return;
    }

    setState(() => _isBusy = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      _showMessage(
        'หากอีเมลนี้ลงทะเบียนไว้ คุณจะได้รับลิงก์รีเซ็ตรหัสผ่าน '
        'กรุณาตรวจสอบกล่องจดหมายและ Spam',
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'invalid-email':
          message = 'รูปแบบอีเมลไม่ถูกต้อง';
          break;
        case 'user-not-found':
          message = 'ไม่พบบัญชีที่ใช้อีเมลนี้';
          break;
        case 'too-many-requests':
          message = 'ส่งคำขอบ่อยเกินไป กรุณารอสักครู่';
          break;
        case 'network-request-failed':
          message = 'เชื่อมต่ออินเทอร์เน็ตไม่ได้';
          break;
        case 'operation-not-allowed':
          message = 'กรุณาตรวจสอบการตั้งค่า Email/Password ใน Firebase';
          break;
        default:
          message = 'ส่งลิงก์รีเซ็ตรหัสผ่านไม่สำเร็จ กรุณาลองใหม่';
      }

      _showMessage(message);
    } catch (_) {
      if (mounted) {
        _showMessage('เกิดข้อผิดพลาด กรุณาลองใหม่');
      }
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// แสดงผลสำเร็จหรือข้อผิดพลาดใน SnackBar บนหน้าปัจจุบัน.
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C13),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9B7CFF),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C63FF).withValues(
                            alpha: 0.20,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.groups_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Game Party',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFF7F5FF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isRegister
                        ? 'สร้างบัญชีแล้วมาเล่นด้วยกัน 🎮'
                        : 'เข้าสู่ระบบเพื่อพบเพื่อนใน Game Party',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    elevation: 0,
                    color: const Color(0xFF171621),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: Color(0xFF2A2938)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _isRegister ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (_isRegister) ...[
                            TextField(
                              controller: _displayName,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'ชื่อที่แสดง',
                                hintText: 'เช่น Gamer123',
                                prefixIcon: const Icon(
                                  Icons.person_outline_rounded,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF191824),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'อีเมล',
                              hintText: 'example@email.com',
                              prefixIcon: const Icon(Icons.email_outlined),
                              filled: true,
                              fillColor: const Color(0xFF191824),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _password,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!_isBusy) _submit();
                            },
                            decoration: InputDecoration(
                              labelText: 'รหัสผ่าน',
                              hintText: 'อย่างน้อย 6 ตัวอักษร',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                              filled: true,
                              fillColor: const Color(0xFF191824),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          if (!_isRegister)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _isBusy ? null : _resetPassword,
                                child: const Text(
                                  'ลืมรหัสผ่าน?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFB69EFF),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: _isBusy ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF9B7CFF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isBusy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isRegister
                                          ? 'สมัครสมาชิก'
                                          : 'เข้าสู่ระบบ',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _isBusy
                                ? null
                                : () {
                                    setState(() {
                                      _isRegister = !_isRegister;
                                    });
                                  },
                            child: Text(
                              _isRegister
                                  ? 'มีบัญชีแล้ว? เข้าสู่ระบบ'
                                  : 'ยังไม่มีบัญชี? สมัครสมาชิก',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Game Party • Play • Meet • Have Fun 🎮',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
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
