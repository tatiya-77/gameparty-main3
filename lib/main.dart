import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (!kIsWeb) {
    try {
      await NotificationService.initialize();
    } catch (error, stackTrace) {
      debugPrint('Game Party notification setup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  runApp(const GamePartyApp());
}

class GamePartyApp extends StatelessWidget {
  const GamePartyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF9B7CFF);

    return MaterialApp(
      title: 'Game Party',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.25,
            colors: [Color(0xFF272044), Color(0xFF101018), Color(0xFF0B0B11)],
            stops: [0, .48, 1],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),

      // -----------------------------
      // Theme ของแอป
      // -----------------------------
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0C0C13),
        cardColor: const Color(0xFF171621),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Color(0xFFF7F5FF),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: const EdgeInsets.symmetric(
            horizontal: 0,
            vertical: 6,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF2A2938)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF191824),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
          vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF302E3D)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF302E3D)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: primaryColor,
              width: 1.5,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: const Color(0xFF9272F7),
            foregroundColor: const Color(0xFFF7F5FF),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF9272F7),
            foregroundColor: const Color(0xFFF7F5FF),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFC5AFFF),
            side: const BorderSide(color: Color(0xFF51436F)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: const Color(0xFF252332),
          selectedColor: const Color(0xFF332A4E),
          labelStyle: const TextStyle(color: Color(0xFFF7F5FF)),
          side: const BorderSide(color: Color(0xFF302E3D)),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
          iconTheme: WidgetStatePropertyAll(IconThemeData(size: 21)),
        ),
        dividerTheme: const DividerThemeData(
          space: 1,
          thickness: 0.5,
        ),
      ),

      // -----------------------------
      // เริ่มต้นแอป
      // -----------------------------
      home: const AuthGate(),
    );
  }
}
