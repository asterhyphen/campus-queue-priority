import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../app_auth_provider.dart';
import '../queue_provider.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final nameCtrl = TextEditingController();
  final cashierCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final qp = Provider.of<QueueProvider>(context);
    final auth = Provider.of<AppAuthProvider>(context, listen: false);

    // MITE-inspired warm campus palette
    const bg           = Color(0xFF121212);
    const card         = Color(0xFF1C1C1C);

    const accent       = Color(0xFFFFA000); // amber
    const accentRed    = Color(0xFFD32F2F); // institute red
    const accentYellow = Color(0xFFFBC02D); // institute yellow

    const titleText    = Color(0xFFFFF3C0);
    const subtleText   = Color(0xFFFFE082);
    const fieldBg      = Color(0xFF1E1E1E);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        title: const Text(
          "Admin • Queues",
          style: TextStyle(color: titleText),
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await auth.logout();
            },
            icon: const Icon(Icons.logout, color: accentYellow),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accentRed.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Create Queue",
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w700,
                      color: titleText,
                      fontSize: 21,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Queue name (e.g. Canteen)",
                      labelStyle: const TextStyle(color: subtleText),
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
                  const SizedBox(height: 8),
                  TextField(
                    controller: cashierCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Cashier email",
                      labelStyle: const TextStyle(color: subtleText),
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
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        final cashier = cashierCtrl.text.trim();
                        if (name.isEmpty || cashier.isEmpty) return;

                        final user = FirebaseAuth.instance.currentUser;
                        String debugInfo =
                            'User: ${user?.email ?? "null"}\nUID: ${user?.uid ?? "null"}\n';

                        try {
                          final token = await user?.getIdToken(true);
                          debugInfo +=
                              'Token: ${token != null ? "${token.substring(0, 20)}..." : "null"}\n';

                          await qp.createQueue(name, cashier);
                          nameCtrl.clear();
                          cashierCtrl.clear();

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Queue created successfully",
                                style: const TextStyle(color: Colors.black),
                              ),
                              backgroundColor: accentYellow,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: accentRed,
                              content: Text(
                                e.toString(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text("Create"),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: qp.queues.length,
                itemBuilder: (_, i) {
                  final q = qp.queues[i];
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accentRed.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          q.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Inter',
                            color: titleText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Cashier: ${q.cashierEmail}",
                          style: const TextStyle(
                            color: subtleText,
                            fontSize: 13,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
