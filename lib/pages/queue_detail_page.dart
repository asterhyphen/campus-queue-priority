import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../queue_provider.dart';

class QueueDetailPage extends StatefulWidget {
  final String queueId;
  final String queueName;

  const QueueDetailPage(
      {super.key, required this.queueId, required this.queueName});

  @override
  State<QueueDetailPage> createState() => _QueueDetailPageState();
}

class _QueueDetailPageState extends State<QueueDetailPage> {
  final Set<String> _markingNoShow = {};
  bool _processingNoShows = false;

  @override
  Widget build(BuildContext context) {
    final qp = Provider.of<QueueProvider>(context, listen: false);

    final tokensRef = FirebaseFirestore.instance
        .collection('queues')
        .doc(widget.queueId)
        .collection('tokens')
        .orderBy('createdAt', descending: false);

    final queueRef =
        FirebaseFirestore.instance.collection('queues').doc(widget.queueId);

    const titleText = Color(0xFFFFF3C0);
    const subtleText = Color(0xFFBDBDBD);
    const card = Color(0xFF1C1C1C);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.queueName),
        actions: [
          IconButton(
            icon: _processingNoShows
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.history_toggle_off),
            tooltip: 'Process no-shows',
            onPressed: _processingNoShows
                ? null
                : () async {
                    setState(() => _processingNoShows = true);
                    try {
                      await qp.processNoShows(widget.queueId);
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Processing no-shows requested.')));
                    } catch (e) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString())));
                    }
                    if (mounted) setState(() => _processingNoShows = false);
                  },
          ),
        ],
      ),
      backgroundColor: const Color(0xFF121212),
      body: StreamBuilder<DocumentSnapshot>(
        stream: queueRef.snapshots(),
        builder: (context, queueSnap) {
          final queueData = queueSnap.data?.data() as Map<String, dynamic>?;
          final timeoutSecs =
              (queueData?['noShowTimeoutSeconds'] ?? 120) as int;

          return StreamBuilder<QuerySnapshot>(
            stream: tokensRef.snapshots(),
            builder: (context, snap) {
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;

              if (docs.isEmpty) {
                return const Center(child: Text('No users in queue.'));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  if (idx == 0) {
                    // Header showing settings
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                              child: Text('No-show timeout: $timeoutSecs s',
                                  style: const TextStyle(color: titleText))),
                          FilledButton(
                            onPressed: _processingNoShows
                                ? null
                                : () async {
                                    setState(() => _processingNoShows = true);
                                    try {
                                      await qp.processNoShows(widget.queueId);
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
                                      setState(
                                          () => _processingNoShows = false);
                                  },
                            child: _processingNoShows
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Process no-shows'),
                          )
                        ],
                      ),
                    );
                  }

                  final i = idx - 1;
                  final d = docs[i];
                  final data = d.data() as Map<String, dynamic>;
                  final email = data['email'] as String? ?? 'unknown';
                  final priority = data['priority'] ?? 1;
                  final createdAt = data['createdAt'] != null
                      ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
                      : null;

                  final isStale = createdAt != null &&
                      DateTime.now().difference(createdAt).inSeconds >=
                          timeoutSecs;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                      child: Text(email,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: titleText))),
                                  if (isStale)
                                    const Icon(Icons.warning_amber_rounded,
                                        color: Colors.orangeAccent, size: 18),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                  'Priority: $priority • ${createdAt?.toLocal().toIso8601String().split('T').first ?? ''}',
                                  style: const TextStyle(
                                      color: subtleText, fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.swap_vert,
                              color: Colors.white70),
                          tooltip: 'Swap with next',
                          onPressed: i == docs.length - 1
                              ? null
                              : () async {
                                  final next = docs[i + 1];
                                  final aRef = d.reference;
                                  final bRef = next.reference;

                                  await FirebaseFirestore.instance
                                      .runTransaction((tx) async {
                                    final aSnap = await tx.get(aRef);
                                    final bSnap = await tx.get(bRef);
                                    final aData =
                                        aSnap.data() as Map<String, dynamic>? ??
                                            {};
                                    final bData =
                                        bSnap.data() as Map<String, dynamic>? ??
                                            {};

                                    final aTime = aData['createdAt'] ??
                                        DateTime.now().millisecondsSinceEpoch;
                                    final bTime = bData['createdAt'] ??
                                        DateTime.now().millisecondsSinceEpoch;

                                    tx.update(aRef, {'createdAt': bTime});
                                    tx.update(bRef, {'createdAt': aTime});
                                  });
                                },
                        ),
                        IconButton(
                          icon: _markingNoShow.contains(d.id)
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.block,
                                  color: Colors.redAccent),
                          tooltip: 'Mark no-show',
                          onPressed: _markingNoShow.contains(d.id)
                              ? null
                              : () async {
                                  final ok = await showDialog<bool?>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Mark no-show?'),
                                      content: Text('Mark $email as no-show?'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancel')),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Mark',
                                                style: TextStyle(
                                                    color: Colors.red))),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    setState(() => _markingNoShow.add(d.id));
                                    try {
                                      await qp.markNoShow(widget.queueId, d.id);
                                      if (mounted)
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text(
                                                    'Marked as no-show.')));
                                    } catch (e) {
                                      if (mounted)
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(e.toString())));
                                    }
                                    if (mounted)
                                      setState(
                                          () => _markingNoShow.remove(d.id));
                                  }
                                },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          tooltip: 'Remove',
                          onPressed: () async {
                            final ok = await showDialog<bool?>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Remove user?'),
                                content: Text('Remove $email from queue?'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel')),
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Remove',
                                          style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await d.reference.delete();
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
