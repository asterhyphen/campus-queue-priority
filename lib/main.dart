import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'app_auth_provider.dart';
import 'queue_provider.dart';

import 'pages/login_page.dart';
import 'pages/admin_page.dart';
import 'pages/cashier_page.dart';
import 'pages/student_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MITE-inspired warm campus palette
    const bg           = Color(0xFF121212);
    const surface      = Color(0xFF1C1C1C);

    const primary      = Color(0xFFFBC02D); // institute yellow
    const secondary    = Color(0xFFFFA000); // amber
    const errorRed     = Color(0xFFD32F2F); // institute red

    const titleText    = Color(0xFFFFF3C0);
    const bodyText     = Color(0xFFF5F5F5);
    const subtleText   = Color(0xFFFFE082);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppAuthProvider()),
        ChangeNotifierProvider(create: (_) => QueueProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "In-Campus Queue System",
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          fontFamily: 'Inter',
          scaffoldBackgroundColor: bg,
          cardColor: surface,
          canvasColor: surface,
          appBarTheme: const AppBarTheme(
            backgroundColor: surface,
            foregroundColor: titleText,
            titleTextStyle: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: titleText,
            ),
            elevation: 0,
          ),
          colorScheme: const ColorScheme.dark(
            primary: primary,
            secondary: secondary,
            error: errorRed,
            background: bg,
            surface: surface,
          ),
          textTheme: const TextTheme(
            displayLarge: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w900,
              color: titleText,
            ),
            headlineLarge: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w700,
              color: bodyText,
            ),
            titleLarge: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w600,
              color: titleText,
            ),
            bodyLarge: TextStyle(
              fontFamily: 'Inter',
              fontSize: 17,
              color: bodyText,
              fontWeight: FontWeight.w400,
            ),
            bodyMedium: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              color: Colors.white70,
              fontWeight: FontWeight.w400,
            ),
            bodySmall: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: subtleText,
            ),
            labelLarge: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w500,
              color: primary,
              fontSize: 14,
            ),
            labelSmall: TextStyle(
              fontFamily: 'Inter',
              color: errorRed,
              fontWeight: FontWeight.w400,
              fontSize: 12,
            ),
          ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LoginPage();

        final user = snapshot.data!;

        return FutureBuilder(
          future: user.getIdToken(true),
          builder: (context, tokenSnap) {
            if (tokenSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection("users")
                  .doc(user.uid)
                  .get(),
              builder: (context, roleSnap) {
                if (!roleSnap.hasData) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final data =
                    roleSnap.data!.data() as Map<String, dynamic>? ?? {};
                final role = data["role"] ?? "student";

                if (role == "admin") return const AdminPage();
                if (role == "cashier") return const CashierPage();
                return const StudentPage();
              },
            );
          },
        );
      },
    );
  }
}
