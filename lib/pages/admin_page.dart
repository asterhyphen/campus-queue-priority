import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  final Set<String> _adminBusyQueues = {};
  bool _blockingInProgress = false;

  @override
  Widget build(BuildContext context) {
    final qp = Provider.of<QueueProvider>(context);
    final auth = Provider.of<AppAuthProvider>(context, listen: false);

    // MITE-inspired warm campus palette
    const bg = Color(0xFF121212);
    const card = Color(0xFF1C1C1C);

    const accent = Color(0xFFFFA000); // amber
    const accentRed = Color(0xFFD32F2F); // institute red
    const accentYellow = Color(0xFFFBC02D); // institute yellow

    const titleText = Color(0xFFFFF3C0);
    const subtleText = Color(0xFFFFE082);
    const fieldBg = Color(0xFF1E1E1E);

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

                        try {
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

            // Blocked users management
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accentRed.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Blocked Users",
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w700,
                      color: titleText,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cashierCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: "Block user email",
                            labelStyle: const TextStyle(color: subtleText),
                            filled: true,
                            fillColor: fieldBg,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                  color: accentRed.withOpacity(0.25)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: accentRed,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _blockingInProgress
                            ? null
                            : () async {
                                final email = cashierCtrl.text.trim();
                                if (email.isEmpty) return;
                                setState(() => _blockingInProgress = true);
                                try {
                                  await qp.addBlockedUser(email);
                                  cashierCtrl.clear();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('User blocked.')),
                                  );
                                  setState(() {});
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                                if (mounted)
                                  setState(() => _blockingInProgress = false);
                              },
                        child: _blockingInProgress
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Block'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder(
                    future: qp.listBlockedUsers(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const SizedBox();
                      final list = snap.data as List;
                      if (list.isEmpty) return const Text('No blocked users.');
                      return Column(
                        children: list.map<Widget>((d) {
                          final data =
                              (d as dynamic).data() as Map<String, dynamic>;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(data['email'] ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                try {
                                  await qp.removeBlockedUser((d as dynamic).id);
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Blocked user removed.')),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              },
                            ),
                          );
                        }).toList(),
                      );
                    },
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
                        Row(
                          children: [
                            Expanded(
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
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_calendar_outlined),
                              color: accentYellow,
                              onPressed: () async {
                                final ctrl = TextEditingController();
                                final current = (await FirebaseFirestore
                                        .instance
                                        .collection('queues')
                                        .doc(q.id)
                                        .get())
                                    .data();
                                ctrl.text =
                                    ((current?['noShowTimeoutSeconds']) ?? 120)
                                        .toString();
                                final val = await showDialog<String?>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title:
                                        const Text('No-show timeout (seconds)'),
                                    content: TextField(
                                      controller: ctrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                          hintText: 'Seconds'),
                                    ),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, null),
                                          child: const Text('Cancel')),
                                      TextButton(
                                          onPressed: () => Navigator.pop(
                                              context, ctrl.text.trim()),
                                          child: const Text('Save')),
                                    ],
                                  ),
                                );
                                if (val != null) {
                                  final secs = int.tryParse(val) ?? 120;
                                  try {
                                    await qp.updateQueueSettings(
                                        q.id, {'noShowTimeoutSeconds': secs});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Timeout updated.')));
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(e.toString())));
                                  }
                                }
                              },
                            ),
                            IconButton(
                              icon: _adminBusyQueues.contains(q.id)
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.history_toggle_off),
                              color: accentYellow,
                              tooltip: 'Process no-shows',
                              onPressed: _adminBusyQueues.contains(q.id)
                                  ? null
                                  : () async {
                                      setState(
                                          () => _adminBusyQueues.add(q.id));
                                      try {
                                        await qp.processNoShows(q.id);
                                        if (mounted)
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content: Text(
                                                      'Processing no-shows requested.')));
                                      } catch (e) {
                                        if (mounted)
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(e.toString())));
                                      }
                                      if (mounted)
                                        setState(() =>
                                            _adminBusyQueues.remove(q.id));
                                    },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever),
                              color: accentRed,
                              onPressed: () async {
                                final ok = await showDialog<bool?>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                          title: const Text('Delete queue?'),
                                          content: Text(
                                              'Are you sure you want to delete "${q.name}"? This cannot be undone.'),
                                          actions: [
                                            TextButton(
                                                onPressed: () => Navigator.pop(
                                                    context, false),
                                                child: const Text('Cancel')),
                                            TextButton(
                                                onPressed: () => Navigator.pop(
                                                    context, true),
                                                child: const Text('Delete',
                                                    style: TextStyle(
                                                        color: Colors.red))),
                                          ],
                                        ));
                                if (ok == true) {
                                  try {
                                    await qp.deleteQueue(q.id);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Queue deleted.')));
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(e.toString())));
                                  }
                                }
                              },
                            ),
                          ],
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
