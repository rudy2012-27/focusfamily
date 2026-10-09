import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models.dart';

class Db {
  static final FirebaseFirestore fs = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> user(String uid) =>
      fs.collection('users').doc(uid);
  static DocumentReference<Map<String, dynamic>> child(String uid) =>
      fs.collection('children').doc(uid);
  static DocumentReference<Map<String, dynamic>> rules(String uid) =>
      fs.collection('rules').doc(uid);
  static DocumentReference<Map<String, dynamic>> device(String uid) =>
      fs.collection('devices').doc(uid);
  static DocumentReference<Map<String, dynamic>> usage(String uid) =>
      fs.collection('usage').doc(uid);

  static Future<void> saveRole(User u, String role) {
    return user(u.uid).set({
      'role': role,
      'name': u.displayName ?? '',
      'email': (u.email ?? '').toLowerCase(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> acceptTerms(String uid, String version) {
    return user(uid).set({
      'termsAccepted': true,
      'termsVersion': version,
      'termsAcceptedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> createInvite(String parentUid, String childEmail) {
    return fs.collection('invites').add({
      'parentUid': parentUid,
      'childEmail': childEmail.toLowerCase().trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> cancelInvite(String id) =>
      fs.collection('invites').doc(id).delete();

  /// Child side: look for a pending invite for this Google email and link.
  static Future<bool> tryAutoLink(User u) async {
    final email = (u.email ?? '').toLowerCase();
    if (email.isEmpty) return false;
    final q = await fs
        .collection('invites')
        .where('childEmail', isEqualTo: email)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (q.docs.isEmpty) return false;
    final inv = q.docs.first;
    final parentUid = inv.data()['parentUid'] as String;
    final batch = fs.batch();
    batch.set(child(u.uid), {
      'parentUid': parentUid,
      'email': email,
      'name': (u.displayName == null || u.displayName!.isEmpty)
          ? email
          : u.displayName,
      'inviteId': inv.id,
      'linkedAt': FieldValue.serverTimestamp(),
    });
    batch.update(inv.reference, {'status': 'linked', 'childUid': u.uid});
    await batch.commit();
    return true;
  }

  static Future<void> saveRules(String childUid, Rules r) {
    return rules(childUid).set({
      ...r.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> grantAllowance(
      String childUid, String pkg, int minutes) async {
    final snap = await rules(childUid).get();
    final r = Rules.fromMap(snap.data());
    r.allowances[pkg] =
        DateTime.now().millisecondsSinceEpoch + minutes * 60 * 1000;
    await saveRules(childUid, r);
  }

  static Future<void> answerRequest(String id, String status) =>
      fs.collection('requests').doc(id).update({'status': status});

  static Future<void> unlinkChild(String childUid) async {
    for (final d in [rules(childUid), usage(childUid), device(childUid)]) {
      try {
        await d.delete();
      } catch (_) {}
    }
    await child(childUid).delete();
  }
}
