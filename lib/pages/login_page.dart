import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_auth_provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AppAuthProvider>(context);

    // MITE-inspired warm campus palette
    const bg = Color(0xFF121212);
    const card = Color(0xFF1C1C1C);

    const accent = Color(0xFFFFA000); // amber CTA
    const accentRed = Color(0xFFD32F2F); // institute red
    const accentYellow = Color(0xFFFBC02D); // institute yellow

    const titleText = Color(0xFFFFF3C0);
    const subtitleText = Color(0xFFFFA000);

    const fieldBg = Color(0xFF1E1E1E);
    const fieldText = Color(0xFFF5F5F5);
    const labelText = Color(0xFFFFE082);

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accentRed.withOpacity(0.25)),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 20,
                  color: Colors.black54,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "ICQS Login",
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    color: titleText,
                    fontSize: 30,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Sign in to continue",
                  style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w500,
                    color: subtitleText,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 24),

                // EMAIL
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: fieldText),
                  decoration: InputDecoration(
                    labelText: "Email",
                    labelStyle: const TextStyle(color: labelText),
                    filled: true,
                    fillColor: fieldBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // PASSWORD
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  style: const TextStyle(color: fieldText),
                  decoration: InputDecoration(
                    labelText: "Password",
                    labelStyle: const TextStyle(color: labelText),
                    filled: true,
                    fillColor: fieldBg,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: accentRed.withOpacity(0.25)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: accent, width: 2),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                if (loading) const CircularProgressIndicator(),

                if (!loading)
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () async {
                            setState(() => loading = true);
                            try {
                              await auth.login(
                                emailCtrl.text.trim(),
                                passCtrl.text.trim(),
                              );
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                            if (mounted) setState(() => loading = false);
                          },
                          child: const Text("Login"),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentYellow,
                            side: const BorderSide(
                                color: accentYellow, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            setState(() => loading = true);
                            try {
                              await auth.register(
                                emailCtrl.text.trim(),
                                passCtrl.text.trim(),
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        "Registered. Verification email sent. Please verify and then log in."),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                            if (mounted) setState(() => loading = false);
                          },
                          child: const Text("Register"),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () async {
                          if (emailCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Enter your college email first.')),
                            );
                            return;
                          }
                          setState(() => loading = true);
                          try {
                            await auth.sendPasswordReset(emailCtrl.text.trim());
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Password reset email sent.')),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          }
                          if (mounted) setState(() => loading = false);
                        },
                        child: const Text(
                          "Forgot password?",
                          style: TextStyle(color: accentYellow),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () async {
                          setState(() => loading = true);
                          try {
                            await auth.loginWithGoogle();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          }
                          if (mounted) setState(() => loading = false);
                        },
                        child: const Text(
                          "Sign in with Google",
                          style: TextStyle(color: accentYellow),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
