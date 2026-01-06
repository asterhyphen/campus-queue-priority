import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_auth_provider.dart';
import '../queue_provider.dart';
import 'student_qr_page.dart';

class StudentPage extends StatefulWidget {
  const StudentPage({super.key});

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  final Set<String> _booking = {};

  @override
  Widget build(BuildContext context) {
    final qp = Provider.of<QueueProvider>(context);
    final auth = Provider.of<AppAuthProvider>(context);
    final email = auth.email ?? "";

    // MITE-inspired warm campus palette
    const bg = Color(0xFF121212);
    const card = Color(0xFF1C1C1C);

    const accent = Color(0xFFFFA000); // amber
    const accentRed = Color(0xFFD32F2F); // institute red
    const accentYellow = Color(0xFFFBC02D); // institute yellow

    const titleText = Color(0xFFFFF3C0);
    const subtleText = Color(0xFFFFE082);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        title: const Text(
          "Student Dashboard",
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
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: qp.queues.length,
        itemBuilder: (context, i) {
          final q = qp.queues[i];

          final tokensRef = FirebaseFirestore.instance
              .collection('queues')
              .doc(q.id)
              .collection('tokens');

          final currentRef = FirebaseFirestore.instance
              .collection('queues')
              .doc(q.id)
              .collection('current')
              .doc('token');

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accentRed.withOpacity(0.25)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StreamBuilder<QuerySnapshot>(
                stream: tokensRef.snapshots(),
                builder: (context, tokenSnap) {
                  final waiting = tokenSnap.data?.docs ?? [];

                  final alreadyWaiting = waiting.any(
                    (d) => (d.data() as Map<String, dynamic>)['email'] == email,
                  );

                  return StreamBuilder<DocumentSnapshot>(
                    stream: currentRef.snapshots(),
                    builder: (context, currentSnap) {
                      final snap = currentSnap.data;
                      final currentData = snap != null
                          ? snap.data() as Map<String, dynamic>?
                          : null;

                      final currentEmail = currentData?['email'] as String?;
                      final isCurrent = currentEmail == email;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.queue, color: Colors.white24),
                              const SizedBox(width: 8),
                              Text(
                                q.name,
                                style: const TextStyle(
                                  fontFamily: 'Montserrat',
                                  fontWeight: FontWeight.w700,
                                  color: titleText,
                                  fontSize: 20,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Waiting: ${waiting.length}",
                            style: const TextStyle(
                              color: subtleText,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              if (!alreadyWaiting && !isCurrent)
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accentYellow,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: _booking.contains(q.id)
                                      ? null
                                      : () async {
                                          setState(() => _booking.add(q.id));
                                          try {
                                            await qp.bookToken(q.id);
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  "Token booked for ${q.name}.",
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(e.toString())),
                                            );
                                          }
                                          if (mounted)
                                            setState(
                                                () => _booking.remove(q.id));
                                        },
                                  child: _booking.contains(q.id)
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Text('Booking...'),
                                          ],
                                        )
                                      : const Text("Book"),
                                ),
                              if (alreadyWaiting && !isCurrent)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: accentYellow.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: accentYellow,
                                    ),
                                  ),
                                  child: const Text(
                                    "Waiting…",
                                    style: TextStyle(
                                      color: accentYellow,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              if (isCurrent)
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => StudentQRPage(
                                          queueId: q.id,
                                          email: email,
                                          queueName: q.name,
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text("Show QR"),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
