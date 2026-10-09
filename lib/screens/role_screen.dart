import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/db.dart';
import '../widgets.dart';

class RoleScreen extends StatelessWidget {
  final User user;
  const RoleScreen({super.key, required this.user});

  Future<void> _choose(BuildContext context, String role) async {
    try {
      await Db.saveRole(user, role);
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Who is using this phone?'),
        actions: [
          TextButton(onPressed: AuthService.signOut, child: const Text('Sign out'))
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Logged in as ${user.email ?? ''}'),
            const SizedBox(height: 20),
            _RoleCard(
              icon: Icons.shield,
              title: "I'm a Parent",
              subtitle: "I'll add my children and set limits on their phones.",
              onTap: () => _choose(context, 'parent'),
            ),
            const SizedBox(height: 16),
            _RoleCard(
              icon: Icons.child_care,
              title: "I'm a Child",
              subtitle: 'This is my phone. My parent will manage app limits.',
              onTap: () => _choose(context, 'child'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _RoleCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
