import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../services/native_bridge.dart';
import '../widgets.dart';
import 'child_home.dart';

class ChildGate extends StatelessWidget {
  final User user;
  const ChildGate({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Db.child(user.uid).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(body: Center(child: Text('Error: ${snap.error}')));
        }
        if (!snap.hasData) return const Splash();
        final d = snap.data!.data();
        if (d == null) return LinkingScreen(user: user);
        return ChildHome(user: user, parentUid: d['parentUid'] as String);
      },
    );
  }
}

/// Waits for a parent invite that matches this Google email, then links.
class LinkingScreen extends StatefulWidget {
  final User user;
  const LinkingScreen({super.key, required this.user});

  @override
  State<LinkingScreen> createState() => _LinkingScreenState();
}

class _LinkingScreenState extends State<LinkingScreen> {
  Timer? _timer;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    NativeBridge.stopGuard(); // make sure no old rules stay active
    _try();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _try());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _try() async {
    if (_checking) return;
    _checking = true;
    try {
      await Db.tryAutoLink(widget.user);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connecting to your parent')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('Logged in as ${widget.user.email}',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'Waiting for your parent to add this email in their FocusFamily app. This page connects automatically.',
              textAlign: TextAlign.center,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            OutlinedButton(onPressed: _try, child: const Text('Check now')),
          ],
        ),
      ),
    );
  }
}
