import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/db.dart';
import '../widgets.dart';

class UsageInfo {
  final Map<String, int> byPkg;
  final DateTime? updated;
  const UsageInfo(this.byPkg, this.updated);
  int get total => byPkg.values.fold(0, (a, b) => a + b);
}

List<AppInfo> _parseApps(Map<String, dynamic>? d) {
  final raw = d?['apps'];
  final out = <AppInfo>[];
  if (raw is List) {
    for (final a in raw) {
      if (a is Map && a['pkg'] is String) {
        out.add(AppInfo(a['pkg'] as String, (a['name'] ?? a['pkg']) as String));
      }
    }
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

UsageInfo _parseUsage(Map<String, dynamic>? d) {
  final m = <String, int>{};
  final raw = d?['entries'];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map && e['pkg'] is String && e['min'] is num) {
        m[e['pkg'] as String] = (e['min'] as num).toInt();
      }
    }
  }
  final ts = d?['updatedAt'];
  return UsageInfo(m, ts is Timestamp ? ts.toDate() : null);
}

class ChildDetail extends StatelessWidget {
  final String childUid;
  final String childName;
  const ChildDetail(
      {super.key, required this.childUid, required this.childName});

  Future<void> _remove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove $childName?'),
        content: const Text(
            'All limits stop working and this child\'s data is deleted. To link again you need to send a new invite.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Db.unlinkChild(childUid);
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) showSnack(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(childName),
          bottom: const TabBar(tabs: [
            Tab(text: 'Apps'),
            Tab(text: 'Phone'),
            Tab(text: 'Websites'),
          ]),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'remove') _remove(context);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'remove', child: Text('Remove child')),
              ],
            ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: Db.rules(childUid).snapshots(),
          builder: (context, rs) {
            final rules = Rules.fromMap(rs.data?.data());
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: Db.device(childUid).snapshots(),
              builder: (context, ds) {
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: Db.usage(childUid).snapshots(),
                  builder: (context, us) {
                    final apps = _parseApps(ds.data?.data());
                    final usage = _parseUsage(us.data?.data());
                    Future<void> save(Rules r) async {
                      try {
                        await Db.saveRules(childUid, r);
                      } catch (e) {
                        if (context.mounted) {
                          showSnack(context, 'Could not save: $e');
                        }
                      }
                    }

                    return TabBarView(
                      children: [
                        AppsTab(
                            rules: rules,
                            apps: apps,
                            usage: usage,
                            onSave: save),
                        PhoneTab(rules: rules, onSave: save),
                        WebsitesTab(rules: rules, onSave: save),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Apps tab

class AppsTab extends StatefulWidget {
  final Rules rules;
  final List<AppInfo> apps;
  final UsageInfo usage;
  final Future<void> Function(Rules) onSave;
  const AppsTab(
      {super.key,
      required this.rules,
      required this.apps,
      required this.usage,
      required this.onSave});

  @override
  State<AppsTab> createState() => _AppsTabState();
}

class _AppsTabState extends State<AppsTab> {
  String _query = '';

  String _status(String pkg) {
    final r = widget.rules;
    final now = DateTime.now().millisecondsSinceEpoch;
    final parts = <String>[];
    if (r.locked.contains(pkg)) parts.add('Locked');
    final t = r.timed[pkg];
    if (t != null && t > now) parts.add('Locked until ${fmtClock(t)}');
    final a = r.allowances[pkg];
    if (a != null && a > now) parts.add('Allowed until ${fmtClock(a)}');
    final l = r.limits[pkg];
    if (l != null) parts.add('Limit ${fmtMinutes(l)}');
    parts.add('${fmtMinutes(widget.usage.byPkg[pkg] ?? 0)} today');
    return parts.join(' · ');
  }

  bool _isLocked(String pkg) {
    final r = widget.rules;
    final now = DateTime.now().millisecondsSinceEpoch;
    return r.locked.contains(pkg) || (r.timed[pkg] ?? 0) > now;
  }

  void _openSheet(AppInfo app) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        void apply(void Function(Rules r) change) {
          final r = widget.rules.copy();
          change(r);
          Navigator.pop(ctx);
          widget.onSave(r);
        }

        int nowMs() => DateTime.now().millisecondsSinceEpoch;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.name, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => apply((r) {
                        r.locked.add(app.pkg);
                        r.timed.remove(app.pkg);
                        r.allowances.remove(app.pkg);
                      }),
                      icon: const Icon(Icons.lock),
                      label: const Text('Lock now'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => apply((r) {
                        r.locked.remove(app.pkg);
                        r.timed.remove(app.pkg);
                        r.allowances.remove(app.pkg);
                      }),
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Unlock'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Lock for a while',
                    style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in [30, 60, 120, 180, 480])
                      ActionChip(
                        label: Text(fmtMinutes(m)),
                        onPressed: () => apply((r) {
                          r.timed[app.pkg] = nowMs() + m * 60 * 1000;
                          r.locked.remove(app.pkg);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Daily time limit',
                    style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in [15, 30, 60, 90, 120, 180])
                      ChoiceChip(
                        label: Text(fmtMinutes(m)),
                        selected: widget.rules.limits[app.pkg] == m,
                        onSelected: (_) => apply((r) => r.limits[app.pkg] = m),
                      ),
                    ChoiceChip(
                      label: const Text('No limit'),
                      selected: widget.rules.limits[app.pkg] == null,
                      onSelected: (_) => apply((r) => r.limits.remove(app.pkg)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final shown = widget.apps
        .where((a) => q.isEmpty || a.name.toLowerCase().contains(q))
        .toList();
    final upd = widget.usage.updated;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.timer),
            title: Text(
                'Screen time today: ${fmtMinutes(widget.usage.total)}'),
            subtitle: Text(upd == null
                ? 'Waiting for the child\'s phone to report'
                : 'Updated ${fmtClock(upd.millisecondsSinceEpoch)}'),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search apps',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        if (widget.apps.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
                'The app list appears here after the child has finished setup on their phone (this can take a minute).',
                textAlign: TextAlign.center),
          ),
        for (final a in shown)
          ListTile(
            leading: CircleAvatar(
              child: Text(a.name.isNotEmpty ? a.name[0].toUpperCase() : '?'),
            ),
            title: Text(a.name),
            subtitle: Text(_status(a.pkg)),
            trailing: Icon(
              _isLocked(a.pkg)
                  ? Icons.lock
                  : (widget.rules.limits.containsKey(a.pkg)
                      ? Icons.hourglass_bottom
                      : Icons.chevron_right),
              color: _isLocked(a.pkg) ? Colors.red : null,
            ),
            onTap: () => _openSheet(a),
          ),
      ],
    );
  }
}

// --------------------------------------------------------------- Phone tab

class PhoneTab extends StatelessWidget {
  final Rules rules;
  final Future<void> Function(Rules) onSave;
  const PhoneTab({super.key, required this.rules, required this.onSave});

  Future<void> _pickTime(BuildContext context, bool start) async {
    final cur = start ? rules.bedStart : rules.bedEnd;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
    );
    if (t == null) return;
    final r = rules.copy();
    if (start) {
      r.bedStart = t.hour * 60 + t.minute;
    } else {
      r.bedEnd = t.hour * 60 + t.minute;
    }
    await onSave(r);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final locked = rules.phoneLockedUntil > now;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lock the whole phone',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(locked
                    ? 'Locked until ${fmtClock(rules.phoneLockedUntil)}'
                    : 'Not locked. Calls, the home screen and the keyboard always work.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in [30, 60, 120, 240])
                      ActionChip(
                        label: Text(fmtMinutes(m)),
                        onPressed: () {
                          final r = rules.copy();
                          r.phoneLockedUntil =
                              DateTime.now().millisecondsSinceEpoch +
                                  m * 60 * 1000;
                          onSave(r);
                        },
                      ),
                    if (locked)
                      FilledButton.tonal(
                        onPressed: () {
                          final r = rules.copy();
                          r.phoneLockedUntil = 0;
                          onSave(r);
                        },
                        child: const Text('Unlock phone'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Bedtime / quiet hours'),
                subtitle: const Text(
                    'Every day. All apps are blocked except calls, the home screen and the keyboard.'),
                value: rules.bedEnabled,
                onChanged: (v) {
                  final r = rules.copy();
                  r.bedEnabled = v;
                  onSave(r);
                },
              ),
              ListTile(
                title: const Text('Starts at'),
                trailing: Text(fmtMinOfDay(rules.bedStart)),
                onTap: () => _pickTime(context, true),
              ),
              ListTile(
                title: const Text('Ends at'),
                trailing: Text(fmtMinOfDay(rules.bedEnd)),
                onTap: () => _pickTime(context, false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ Websites tab

class WebsitesTab extends StatefulWidget {
  final Rules rules;
  final Future<void> Function(Rules) onSave;
  const WebsitesTab({super.key, required this.rules, required this.onSave});

  @override
  State<WebsitesTab> createState() => _WebsitesTabState();
}

class _WebsitesTabState extends State<WebsitesTab> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _clean(String s) {
    var t = s.trim().toLowerCase();
    t = t.replaceFirst(RegExp(r'^https?://'), '');
    t = t.split('/').first.split('?').first;
    if (t.startsWith('www.')) t = t.substring(4);
    return t;
  }

  void _add() {
    final d = _clean(_ctrl.text);
    if (!d.contains('.') || d.contains(' ')) {
      showSnack(context, 'Enter a website like example.com');
      return;
    }
    if (widget.rules.domains.contains(d)) return;
    final r = widget.rules.copy();
    r.domains.add(d);
    _ctrl.clear();
    widget.onSave(r);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'When you lock an app such as YouTube or Instagram, its website is blocked too, in every browser. You can also block any other website below.'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                    hintText: 'example.com', border: OutlineInputBorder()),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _add, child: const Text('Block')),
          ],
        ),
        const SizedBox(height: 8),
        for (final d in widget.rules.domains)
          ListTile(
            leading: const Icon(Icons.public_off),
            title: Text(d),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                final r = widget.rules.copy();
                r.domains.remove(d);
                widget.onSave(r);
              },
            ),
          ),
      ],
    );
  }
}
