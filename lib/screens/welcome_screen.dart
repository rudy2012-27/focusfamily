import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await AuthService.signInWithGoogle();
    } catch (e) {
      if (mounted) showSnack(context, 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Icon(Icons.family_restroom, size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text('FocusFamily',
                  style: Theme.of(context)
                      .textTheme
                      .displaySmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Healthy phone habits, set by parents, from their own phone.',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 32),
              const _Feature(Icons.lock_clock,
                  'Lock apps or set daily time limits for each app'),
              const _Feature(Icons.public_off,
                  'Block websites too, so the web version of an app is locked as well'),
              const _Feature(Icons.bedtime, 'Set bedtime and study hours'),
              const _Feature(Icons.phonelink_lock,
                  'Control your child\'s phone from your phone'),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Login with Google to get started'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Feature(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
