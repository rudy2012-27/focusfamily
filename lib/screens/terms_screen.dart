import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../legal.dart';
import '../services/auth_service.dart';
import '../services/db.dart';
import '../widgets.dart';

class TermsScreen extends StatefulWidget {
  final User user;
  final String role;
  const TermsScreen({super.key, required this.user, required this.role});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _agree = false;
  bool _extra = false;
  bool _busy = false;

  Future<void> _continue() async {
    setState(() => _busy = true);
    try {
      await Db.acceptTerms(widget.user.uid, termsVersion);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isParent = widget.role == 'parent';
    final canGo = _agree && _extra && !_busy;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms and Privacy'),
        actions: [
          TextButton(onPressed: AuthService.signOut, child: const Text('Sign out'))
        ],
      ),
      body: Column(
        children: [
          const Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Text(termsText),
            ),
          ),
          const Divider(height: 1),
          CheckboxListTile(
            value: _agree,
            onChanged: (v) => setState(() => _agree = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I have read and agree to the Terms and Privacy policy'),
          ),
          CheckboxListTile(
            value: _extra,
            onChanged: (v) => setState(() => _extra = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(isParent
                ? 'I am the parent or legal guardian of the children I will add'
                : 'I understand my parent will be able to see my app usage and set limits'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canGo ? _continue : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Continue'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
