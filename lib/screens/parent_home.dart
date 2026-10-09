import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/db.dart';
import '../widgets.dart';
import 'child_detail.dart';

class ParentHome extends StatelessWidget {
  final User user;
  const ParentHome({super.key, required this.user});

  Future<void> _addChild(BuildContext context) async {
    final ctrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add your child'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                "Enter the Google email your child will log in with on their own phone. The link is made automatically when they log in."),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: "Child's email", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(c, ctrl.text.trim().toLowerCase()),
              child: const Text('Send invite')),
        ],
      ),
    );
    if (email == null || !email.contains('@')) return;
    try {
      await Db.createInvite(user.uid, email);
      if (context.mounted) {
        showSnack(context, 'Invite created. Now log in on your child\'s phone.');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not add: $e');
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await AuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final fs = Db.fs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent dashboard'),
        actions: [
          IconButton(
              onPressed: () => _signOut(context),
              icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addChild(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add child'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // Requests for more time
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: fs
                .collection('requests')
                .where('parentUid', isEqualTo: user.uid)
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Requests for more time',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final d in docs) _RequestCard(doc: d),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
          Text('Your children', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: fs
                .collection('children')
                .where('parentUid', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'No child linked yet. Tap "Add child", then log in on your child\'s phone with that email.'),
                  ),
                );
              }
              return Column(
                children: [
                  for (final d in docs)
                    _ChildTile(
                      uid: d.id,
                      name: (d.data()['name'] ?? '') as String,
                      email: (d.data()['email'] ?? '') as String,
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: fs
                .collection('invites')
                .where('parentUid', isEqualTo: user.uid)
                .where('status', isEqualTo: 'pending')
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Waiting for child to log in',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final d in docs)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.hourglass_top),
                        title: Text((d.data()['childEmail'] ?? '') as String),
                        subtitle: const Text(
                            'Ask your child to open FocusFamily and log in with this email'),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Db.cancelInvite(d.id),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _RequestCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final d = doc.data();
    final child = (d['childName'] ?? 'Your child') as String;
    final app = (d['appName'] ?? d['pkg'] ?? 'an app') as String;
    final pkg = (d['pkg'] ?? '') as String;
    final childUid = (d['childUid'] ?? '') as String;

    Future<void> approve(int mins) async {
      try {
        await Db.grantAllowance(childUid, pkg, mins);
        await Db.answerRequest(doc.id, 'approved');
      } catch (e) {
        if (context.mounted) showSnack(context, 'Failed: $e');
      }
    }

    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$child wants more time on $app'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                    onPressed: () => approve(15), child: const Text('Allow 15 min')),
                FilledButton.tonal(
                    onPressed: () => approve(30), child: const Text('Allow 30 min')),
                OutlinedButton(
                    onPressed: () => Db.answerRequest(doc.id, 'denied'),
                    child: const Text('Deny')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildTile extends StatelessWidget {
  final String uid;
  final String name;
  final String email;
  const _ChildTile(
      {required this.uid, required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Db.device(uid).snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data();
        final hb = (d?['heartbeat'] as Timestamp?)?.toDate();
        final status =
            Map<String, dynamic>.from((d?['status'] as Map?) ?? {});
        final online =
            hb != null && DateTime.now().difference(hb).inMinutes < 10;
        final problems = <String>[];
        if (d == null) {
          problems.add('Child has not finished setup');
        } else if (!online) {
          problems.add('Offline or app stopped');
        } else {
          if (status['usageAccess'] == false) problems.add('Usage access is off');
          if (status['accessibility'] == false) {
            problems.add('Accessibility is off');
          }
          if (status['vpnRunning'] == false) problems.add('Website blocking is off');
        }
        final ok = problems.isEmpty;
        return Card(
          child: ListTile(
            leading: CircleAvatar(
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
            title: Text(name.isEmpty ? email : name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(email),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(ok ? Icons.check_circle : Icons.warning_amber,
                        size: 16, color: ok ? Colors.green : Colors.orange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ok ? 'Protected and online' : problems.join(' · '),
                        style: TextStyle(
                            color: ok ? Colors.green[800] : Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChildDetail(
                  childUid: uid, childName: name.isEmpty ? email : name),
            )),
          ),
        );
      },
    );
  }
}
