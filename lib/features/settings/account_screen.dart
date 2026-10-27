import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../widgets/common.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool create}) async {
    if (_email.text.trim().isEmpty || _password.text.length < 6) {
      setState(() => _message = 'Enter your email and a password of at least 6 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final sync = ref.read(syncServiceProvider);
    final result = create
        ? await sync.signUp(_email.text, _password.text)
        : await sync.signIn(_email.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result;
    });
    if (result == null) {
      snack(context, 'Signed in. Your data will now back up.');
      sync.requestSync(pull: true, immediate: true);
    }
  }

  Future<void> _signOut() async {
    final ok = await confirmDialog(
      context,
      title: 'Sign out?',
      message: 'Your data stays on this phone. It just stops syncing until you sign in again.',
      confirmLabel: 'Sign out',
    );
    if (!ok) return;
    await ref.read(syncServiceProvider).signOut();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the sync state (and therefore the sign-in state) changes.
    ref.watch(syncStateProvider);
    final sync = ref.watch(syncServiceProvider);

    Widget body;
    if (!sync.isConfigured) {
      body = const SectionCard(
        title: 'Cloud sync is not set up yet',
        children: [
          Text('The app works fully without it. To back up and sync across devices:'),
          SizedBox(height: 8),
          Text('1. Create a free project at supabase.com.'),
          Text('2. In its SQL Editor, run the file supabase_schema.sql.'),
          Text('3. In Authentication > Providers > Email, switch off "Confirm email" (simplest for a personal app).'),
          Text('4. Copy the project URL and the anon / publishable key (Project Settings > API) into lib/config/supabase_config.dart.'),
          Text('5. Rebuild the app. Never use a service_role or secret key in the app.'),
        ],
      );
    } else if (sync.isSignedIn) {
      body = SectionCard(
        title: 'Signed in',
        children: [
          Text(sync.userEmail ?? ''),
          const SizedBox(height: 8),
          const Text('Your notes, cases, trades and screenshots back up automatically when you are online.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _signOut, child: const Text('Sign out')),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Sign in to back up your data and use it on another phone. '
              'Everything you have already saved on this phone will be uploaded.'),
          const SizedBox(height: 16),
          LabeledField(controller: _email, label: 'Email', keyboardType: TextInputType.emailAddress),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : () => _submit(create: false),
            child: Text(_busy ? 'Please wait...' : 'Sign in'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _submit(create: true),
            child: const Text('Create account'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(padding: const EdgeInsets.all(16), children: [body]),
    );
  }
}
