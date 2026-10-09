class AppInfo {
  final String pkg;
  final String name;
  const AppInfo(this.pkg, this.name);
}

String fmtClock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return fmtMinOfDay(d.hour * 60 + d.minute);
}

String fmtMinOfDay(int m) {
  final hour24 = (m ~/ 60) % 24;
  final min = m % 60;
  final h = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$h:${min.toString().padLeft(2, '0')} ${hour24 >= 12 ? 'PM' : 'AM'}';
}

String fmtMinutes(int mins) {
  if (mins >= 60) {
    final r = mins % 60;
    return r == 0 ? '${mins ~/ 60} h' : '${mins ~/ 60} h $r m';
  }
  return '$mins min';
}

class Rules {
  Set<String> locked;
  Map<String, int> timed;
  Map<String, int> limits;
  Map<String, int> allowances;
  List<String> domains;
  int phoneLockedUntil;
  bool bedEnabled;
  int bedStart;
  int bedEnd;

  Rules({
    Set<String>? locked,
    Map<String, int>? timed,
    Map<String, int>? limits,
    Map<String, int>? allowances,
    List<String>? domains,
    this.phoneLockedUntil = 0,
    this.bedEnabled = false,
    this.bedStart = 22 * 60,
    this.bedEnd = 6 * 60,
  })  : locked = locked ?? <String>{},
        timed = timed ?? <String, int>{},
        limits = limits ?? <String, int>{},
        allowances = allowances ?? <String, int>{},
        domains = domains ?? <String>[];

  static Map<String, int> _readPairs(dynamic raw, String key) {
    final out = <String, int>{};
    if (raw is List) {
      for (final m in raw) {
        if (m is Map && m['pkg'] is String && m[key] is num) {
          out[m['pkg'] as String] = (m[key] as num).toInt();
        }
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> _writePairs(Map<String, int> m, String key) {
    return [
      for (final e in m.entries) {'pkg': e.key, key: e.value}
    ];
  }

  factory Rules.fromMap(Map<String, dynamic>? m) {
    final data = m ?? <String, dynamic>{};
    final bed = data['bedtime'] is Map
        ? Map<String, dynamic>.from(data['bedtime'] as Map)
        : <String, dynamic>{};
    return Rules(
      locked: {
        for (final x in (data['lockedApps'] as List? ?? [])) x.toString()
      },
      timed: _readPairs(data['timedLocks'], 'until'),
      limits: _readPairs(data['dailyLimits'], 'minutes'),
      allowances: _readPairs(data['allowances'], 'until'),
      domains: [
        for (final x in (data['customDomains'] as List? ?? [])) x.toString()
      ],
      phoneLockedUntil: (data['phoneLockedUntil'] as num?)?.toInt() ?? 0,
      bedEnabled: bed['enabled'] == true,
      bedStart: (bed['start'] as num?)?.toInt() ?? 22 * 60,
      bedEnd: (bed['end'] as num?)?.toInt() ?? 6 * 60,
    );
  }

  Map<String, dynamic> toMap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final liveTimed = <String, int>{
      for (final e in timed.entries)
        if (e.value > now) e.key: e.value
    };
    final liveAllow = <String, int>{
      for (final e in allowances.entries)
        if (e.value > now) e.key: e.value
    };
    return {
      'lockedApps': locked.toList(),
      'timedLocks': _writePairs(liveTimed, 'until'),
      'dailyLimits': _writePairs(limits, 'minutes'),
      'allowances': _writePairs(liveAllow, 'until'),
      'customDomains': domains,
      'phoneLockedUntil': phoneLockedUntil > now ? phoneLockedUntil : 0,
      'bedtime': {'enabled': bedEnabled, 'start': bedStart, 'end': bedEnd},
    };
  }

  Rules copy() => Rules.fromMap(toMap());
}
