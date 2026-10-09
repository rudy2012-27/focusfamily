import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/native_bridge.dart';

class ChildHome extends StatefulWidget {
  final User user;
  final String parentUid;
  const ChildHome({super.key, required this.user, required this.parentUid});

  @override
  State<ChildHome> createState() => _ChildHomeState();
}

class _ChildHomeState extends State<ChildHome> with WidgetsBindingObserver {
  Map<String, bool> _perms = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _boot() async {
    if (Platform.isAndroid) {
      await NativeBridge.startGuard(
        childUid: widget.user.uid,
        parentUid: widget.parentUid,
        childName: widget.user.displayName ?? widget.user.email ?? 'Child',
      );
      await NativeBridge.requestNotifications();
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    final p = await NativeBridge.permissions();
    if (mounted) setState(() => _perms = p);
  }

  bool _ok(String k) => _perms[k] == true;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Child protection on iPhone is coming next (it uses Apple Screen Time). For now, please use an Android phone as the child device.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final allDone = _ok('usageAccess') &&
        _ok('accessibility') &&
        _ok('vpn') &&
        _ok('battery');
    return Scaffold(
      appBar: AppBar(title: const Text('FocusFamily')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: allDone
                ? Colors.green.shade50
                : Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(allDone ? Icons.verified_user : Icons.info_outline,
                      size: 36, color: allDone ? Colors.green : null),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      allDone
                          ? "You're connected to your parent. Everything is set. You don't need to do anything else."
                          : 'Almost done! Turn on the permissions below so your parent\'s limits can work.',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _PermRow(
            done: _ok('usageAccess'),
            title: 'Usage access',
            desc: 'Lets the app measure how long each app is used.',
            onTap: NativeBridge.openUsageAccess,
          ),
          _PermRow(
            done: _ok('accessibility'),
            title: 'Accessibility service',
            desc:
                'Lets the app notice which app or website is open so a lock can be applied. Find "FocusFamily Guard" and turn it on. If the switch is greyed out: Settings > Apps > FocusFamily > (three dots) > Allow restricted settings.',
            onTap: NativeBridge.openAccessibility,
          ),
          _PermRow(
            done: _ok('vpn'),
            title: 'Website blocking (local VPN)',
            desc:
                'Blocks locked websites in every browser. Only website names are checked on this phone; your traffic is not sent anywhere.',
            onTap: () async {
              await NativeBridge.requestVpn();
              _refresh();
            },
          ),
          _PermRow(
            done: _ok('battery'),
            title: 'Keep running in background',
            desc: 'Stops the phone from putting FocusFamily to sleep.',
            onTap: NativeBridge.openBattery,
          ),
          const SizedBox(height: 16),
          Text('What your parent can see',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
              'Which apps are installed, how long you use each app, and whether FocusFamily is working.'),
          const SizedBox(height: 12),
          Text('What your parent cannot see',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
              'Your messages, photos, passwords, calls, location or browsing history.'),
        ],
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final bool done;
  final String title;
  final String desc;
  final VoidCallback onTap;
  const _PermRow(
      {required this.done,
      required this.title,
      required this.desc,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? Colors.green : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(desc, style: Theme.of(context).textTheme.bodySmall),
                  if (!done) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                        onPressed: onTap, child: const Text('Allow')),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
