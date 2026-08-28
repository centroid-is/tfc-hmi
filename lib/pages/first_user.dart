/// Commissioning: the one screen that creates the first Engineering account.
///
/// Roles are seeded, users are not, so without this the sign-in dialog ships
/// with nobody able to pass it. Creation is permitted only while `app_user` is
/// empty, and the window closes permanently behind the first account — no
/// default password to forget to change, no bootstrap flag to leave switched
/// on.
///
/// The window check on this page is a **courtesy**. The guard is the
/// in-transaction emptiness re-check inside
/// [AccessRepository.createFirstUser]: checking here and inserting there is a
/// check-then-act race, and this is the one window in the design that must not
/// have a hole in it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:tfc_dart/core/access/access_repository.dart';

import '../providers/access.dart';
import '../widgets/base_scaffold.dart';

/// The intro. Says what is being created, not merely that something is.
const String _kIntro =
    'Roles are seeded; users are not. This creates the first Engineering '
    'account.';

/// Why there is no second chance.
const String _kOneShot =
    'This window is open only while no users exist. Once this account is '
    'created it closes permanently — there is no default password and no '
    'bootstrap flag.';

/// The consequence of the window standing open, stated plainly rather than
/// left in the deployment doc where the person at the panel will not read it.
const String _kClaimable =
    'A freshly deployed station is claimable by whoever reaches it first. Do '
    'this at commissioning.';

/// The honesty line. This milestone records who changed what; it does not stop
/// anybody, and a screen that implied otherwise would be the more dangerous
/// outcome.
const String _kHonesty =
    'Signing in records who changed what. It is a guardrail, not a security '
    'boundary.';

/// The closed state. Names the deployment doc rather than linking it, because
/// the station that needs it may be the one that cannot be signed into.
const String _kClosed =
    'An account already exists, so this window is closed. Recovery is a '
    'deployment task — see docs/access-control-deployment.md.';

/// No database configured, or the connection has not opened yet.
///
/// Deliberately distinct from [_kClosed]: `firstUserWindowOpenProvider`
/// answers false in both cases, and telling a commissioning engineer that
/// somebody already claimed a station they just unboxed would send them
/// looking for the wrong problem.
const String _kNoDatabase =
    'This station has no reachable database, so the first account cannot be '
    'created yet. Configure the connection in Server Config and come back.';

/// Route target for [AppRoutes.firstUser].
///
/// Field-less on purpose so `createLocationBuilder` can register it as
/// `const FirstUserPage()`. All of the logic lives in [FirstUserBody].
class FirstUserPage extends StatelessWidget {
  const FirstUserPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const BaseScaffold(
      title: 'First account',
      body: FirstUserBody(),
    );
  }
}

/// The page content, split from [FirstUserPage] so tests can pump it without
/// [BaseScaffold]'s routing context.
///
/// [BaseScaffold] calls `context.currentBeamLocation`, so it cannot be pumped
/// without a Beamer ancestor. `IpSettingsBody` and `ServerConfigBody` are the
/// same split for the same reason.
class FirstUserBody extends ConsumerStatefulWidget {
  const FirstUserBody({super.key});

  @override
  ConsumerState<FirstUserBody> createState() => _FirstUserBodyState();
}

class _FirstUserBodyState extends ConsumerState<FirstUserBody> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  /// The inline error under the form. Never contains the credential.
  String? _error;

  /// True while a `createFirstUser` call is outstanding — the action is
  /// disabled for its duration so a second tap cannot race the first.
  bool _submitting = false;

  /// Set when the repository reports the window shut under us. The provider
  /// may still be answering true from before the race; the repository is the
  /// authority, so this pins the closed state locally.
  bool _lostTheRace = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit(AccessRepository repo) async {
    final username = _username.text.trim();
    final password = _password.text;

    if (username.isEmpty) {
      setState(() => _error = 'Enter a username.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter a password.');
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      await repo.createFirstUser(username: username, password: password);
      if (!mounted) return;
      // Re-ask rather than assume: the provider counts the rows, and a page
      // that decided the window was shut on its own say-so would be a second
      // source of truth for the one rule this screen exists to enforce.
      ref.invalidate(firstUserWindowOpenProvider);
      setState(() => _submitting = false);
    } on FirstUserWindowClosedError {
      // Somebody claimed the station between the check and the submit. The
      // transaction made the outcome correct; this only has to say so.
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _lostTheRace = true;
      });
    } on Object catch (e, st) {
      // The exception goes to the log, never to the screen. An `ArgumentError`
      // raised on a bad credential can carry the credential in its message,
      // and this is the one screen where the password is in hand — rendering
      // `$e` would put it in a screenshot of a commissioning session.
      Logger().e('createFirstUser failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'The account could not be created. '
            'The log has the details.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(accessRepositoryProvider);
    final windowAsync = ref.watch(firstUserWindowOpenProvider);

    // A database that cannot even be constructed is a missing database, not a
    // claimed station.
    if (repoAsync.hasError) return _message(context, _kNoDatabase);
    if (!repoAsync.hasValue) return _loading();
    final repo = repoAsync.requireValue;
    if (repo == null) return _message(context, _kNoDatabase);

    // The window closes on the repository's word before the provider's.
    if (_lostTheRace) return _message(context, _kClosed);
    // The provider swallows its own errors, but if one ever reaches here the
    // safe direction is closed: this screen hands out Engineering.
    if (windowAsync.hasError) return _message(context, _kClosed);
    if (!windowAsync.hasValue) return _loading();
    if (!windowAsync.requireValue) return _message(context, _kClosed);

    return _form(context, repo);
  }

  /// A progress indicator rather than an empty box: this route is reached
  /// deliberately, and a blank page reads as broken.
  Widget _loading() => const Center(child: CircularProgressIndicator());

  Widget _shell(BuildContext context, List<Widget> children) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _message(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return _shell(context, [
      Icon(Icons.lock_outline, size: 40, color: scheme.onSurfaceVariant),
      const SizedBox(height: 16),
      Text(text, textAlign: TextAlign.center),
    ]);
  }

  Widget _form(BuildContext context, AccessRepository repo) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = theme.textTheme.bodyMedium
        ?.copyWith(color: scheme.onSurfaceVariant);

    return _shell(context, [
      Text('First account', style: theme.textTheme.headlineSmall),
      const SizedBox(height: 16),
      Text(_kIntro, style: theme.textTheme.bodyLarge),
      const SizedBox(height: 12),
      Text(_kOneShot, style: secondary),
      const SizedBox(height: 12),
      Text(_kClaimable, style: secondary),
      const SizedBox(height: 24),
      TextField(
        controller: _username,
        autofocus: true,
        enabled: !_submitting,
        decoration: const InputDecoration(
          labelText: 'Username',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: true,
        enabled: !_submitting,
        decoration: const InputDecoration(
          labelText: 'Password',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _confirm,
        obscureText: true,
        enabled: !_submitting,
        onSubmitted: _submitting ? null : (_) => _submit(repo),
        decoration: const InputDecoration(
          labelText: 'Confirm password',
          border: OutlineInputBorder(),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
        ),
      ],
      const SizedBox(height: 20),
      ElevatedButton(
        onPressed: _submitting ? null : () => _submit(repo),
        child: const Text('Create account'),
      ),
      const SizedBox(height: 24),
      Text(_kHonesty, style: secondary),
    ]);
  }
}
