/// The modal sign-in form.
///
/// Called **Sign in**, never "Login". `lib/pages/dbus_login.dart` already owns
/// "Login" for the *station's* D-Bus credential, and the access-control spec
/// requires the two to read differently in the UI so an operator standing at
/// the panel meets one prompt and knows which one it is.
///
/// Nothing here is a security boundary and the dialog says so out loud — see
/// [kAccessSignInHonestyNote]. Signing in records what you change; it does not
/// stop anybody who is standing at the panel.
library;

import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/access.dart';
import '../routes.dart';
import 'panes/pane_chrome.dart';
import 'panes/standard_dialog.dart';

/// Opens the sign-in dialog. The signature the app-bar affordance injects.
typedef AccessSignInOpener = Future<void> Function(
  BuildContext context,
  WidgetRef ref,
);

/// Keys the tests and any automation address the form by.
const Key kAccessSignInUsernameKey = Key('access-sign-in-username');
const Key kAccessSignInPasswordKey = Key('access-sign-in-password');
const Key kAccessSignInSubmitKey = Key('access-sign-in-submit');
const Key kAccessSignInCancelKey = Key('access-sign-in-cancel');
const Key kAccessSignInFirstUserKey = Key('access-sign-in-first-user');

/// The honesty line's own key, so a test can assert the widget carrying it is
/// not the single-line ellipsising kind. See [kAccessSignInHonestyNote].
const Key kAccessSignInHonestyKey = Key('access-sign-in-honesty');

/// What a rejected credential says.
///
/// One message for a wrong username and for a wrong password, deliberately:
/// two messages would let anybody standing at the panel enumerate which
/// usernames exist by watching which of the two comes back.
const String kAccessSignInBadCredentialsMessage =
    'Username or password not recognised';

/// What an outage says.
///
/// Different from [kAccessSignInBadCredentialsMessage] on purpose. Telling
/// somebody their password is wrong when the database is unreachable sends
/// them off to reset a password that was never the problem.
const String kAccessSignInUnavailableMessage =
    'Cannot reach the user database — sign-in is unavailable right now.';

/// The honesty line, in the operator's own terms.
///
/// Spec §8 requires the UI itself to say what signing in does and does not do.
/// The long version is the admin help text; this is the half that ships with
/// the first sign-in surface.
const String kAccessSignInHonestyNote =
    'Signing in records what you change. It is not a security boundary.';

/// Shows the sign-in dialog, and beams to the first-user screen if the
/// operator took that link instead.
///
/// The dialog pops with a route rather than navigating itself, so the widget
/// needs no router in a test and the destination is a value an assertion can
/// read.
Future<void> showAccessSignInDialog(BuildContext context, WidgetRef ref) async {
  final target = await showDialog<String>(
    context: context,
    builder: (_) => const AccessSignInDialog(),
  );
  if (target == null) return;
  if (!context.mounted) return;
  context.beamToNamed(target);
}

/// The form itself. Public so a widget test can push it directly and read the
/// value it pops with.
class AccessSignInDialog extends ConsumerStatefulWidget {
  const AccessSignInDialog({super.key});

  @override
  ConsumerState<AccessSignInDialog> createState() => _AccessSignInDialogState();
}

class _AccessSignInDialogState extends ConsumerState<AccessSignInDialog> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  /// The inline error, or null when there is nothing to say. Cleared the
  /// moment either field is edited — a stale complaint about credentials the
  /// operator has already changed is noise.
  String? _error;

  /// True while an attempt is in flight. Disables the action, so a double tap
  /// cannot fire two attempts and write two audit rows.
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error == null) return;
    setState(() => _error = null);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(accessSessionProvider.notifier)
        .signIn(_username.text, _password.text);

    if (!mounted) return;
    switch (result) {
      case AccessSignInResult.ok:
        Navigator.of(context).maybePop();
      case AccessSignInResult.badCredentials:
        setState(() {
          _busy = false;
          _error = kAccessSignInBadCredentialsMessage;
        });
      case AccessSignInResult.unavailable:
        setState(() {
          _busy = false;
          _error = kAccessSignInUnavailableMessage;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A closed window and an unreachable database read the same here: no link.
    // `firstUserWindowOpenProvider` already answers false for an outage.
    final windowOpen =
        ref.watch(firstUserWindowOpenProvider).valueOrNull ?? false;

    return StandardDialogFrame(
      title: 'Sign in',
      // The honesty line is NOT the header subtitle. `PaneHeader` renders its
      // subtitle on one line with `TextOverflow.ellipsis` — it is built for
      // short fixed wording like "Conveyor" — and at the dialog's 520px width
      // this sentence came out as "…It is not a security bo…" on screen. A
      // `find.text` assertion still passed, because the `Text` widget carries
      // the whole string whether or not any of it is legible; the golden in
      // `test/widgets/access_golden_test.dart` is what showed it. Spec §8
      // requires the operator to be able to *read* it, so it lives in the
      // body below, where it wraps.
      icon: Icons.lock_open_outlined,
      showClose: false,
      actions: [
        PaneAction(
          buttonKey: kAccessSignInCancelKey,
          label: 'Cancel',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        PaneAction.primary(
          buttonKey: kAccessSignInSubmitKey,
          label: 'Sign in',
          onPressed: _busy ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Above the fields, not below the buttons: what signing in does and
          // does not do has to be read before the credential is typed, not
          // after.
          Text(
            kAccessSignInHonestyNote,
            key: kAccessSignInHonestyKey,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            key: kAccessSignInUsernameKey,
            controller: _username,
            autofocus: true,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Username'),
            onChanged: (_) => _clearError(),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kAccessSignInPasswordKey,
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Password'),
            onChanged: (_) => _clearError(),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
          // No "forgot password": password reset is out of scope for this
          // phase, and an affordance that goes nowhere is worse than none.
          if (windowOpen) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: kAccessSignInFirstUserKey,
                onPressed: () =>
                    Navigator.of(context).maybePop(AppRoutes.firstUser),
                child: const Text('Create the first account'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
