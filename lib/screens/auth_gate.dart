import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/db.dart';
import '../widgets.dart';
import 'child_gate.dart';
import 'parent_home.dart';
import 'role_screen.dart';
import 'terms_screen.dart';
import 'welcome_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.changes,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Splash();
        }
        final user = snap.data;
        if (user == null) return const WelcomeScreen();
        return UserGate(user: user);
      },
    );
  }
}

class UserGate extends StatelessWidget {
  final User user;
  const UserGate({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Db.user(user.uid).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Something went wrong:\n${snap.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: AuthService.signOut,
                        child: const Text('Sign out')),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) return const Splash();
        final data = snap.data!.data();
        final role = data?['role'] as String?;
        if (role == null) return RoleScreen(user: user);
        if (data?['termsAccepted'] != true) {
          return TermsScreen(user: user, role: role);
        }
        if (role == 'parent') return ParentHome(user: user);
        return ChildGate(user: user);
      },
    );
  }
}
