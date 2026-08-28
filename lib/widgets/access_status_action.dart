/// The app-bar access affordance: a sign-in when nobody is signed in, and who
/// is signed in — in orange — when somebody is.
///
/// Called **Sign in**, never "Login". `lib/pages/dbus_login.dart` already owns
/// "Login" for the *station's* D-Bus credential, and the access-control spec
/// requires the two to read differently in the UI, so an operator standing at
/// the panel meets one prompt rather than two that look alike.
///
/// The elevated state is painted with [HmiStateColors.orange] — the repo's
/// forced/override colour, reused here because it is the same idea: the panel
/// is not in its normal state and somebody should be able to see that from
/// across the room. Nothing in this file reaches for a raw Material colour
/// constant; a grep for one should come back empty.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_access/tfc_access.dart';

import '../providers/access.dart';
import '../theme.dart';
import 'access_sign_in_dialog.dart';

/// The width budget for the elevated row.
///
/// `base_scaffold.dart` positions the app bar's centre region with a
/// `right:` margin that reserves room for this cluster; a row wider than the
/// budget pushes the clock and the alarm banner off-centre. A long display
/// name ellipsises inside this instead of growing.
const double kAccessStatusActionMaxWidth = 220;

/// Sign in from the app bar; when elevated, who and their role, and sign out.
class AccessStatusAction extends ConsumerWidget {
  const AccessStatusAction({
    super.key,
    this.openSignIn = showAccessSignInDialog,
  });

  /// How the sign-in prompt is opened. Injectable so a widget test can count
  /// the taps without standing up a dialog route.
  final AccessSignInOpener openSignIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(accessSessionProvider);
    final value = session.valueOrNull;

    // Still resolving, and nothing to show yet: render nothing rather than a
    // spinner. The app bar rebuilds on every navigation and a spinner there
    // would flicker on each one.
    if (value == null && session.isLoading) return const SizedBox.shrink();

    // A null value that is not loading is an error — no database configured,
    // or one that would not answer. The app bar degrades to the sign-in
    // affordance: a broken access layer must not make the bar unusable, and
    // the attempt itself will report the outage inline.
    if (value == null || !value.isElevated) {
      return IconButton(
        icon: const Icon(Icons.lock_open_outlined),
        tooltip: 'Sign in',
        onPressed: () => openSignIn(context, ref),
      );
    }

    return _ElevatedBadge(session: value);
  }
}

class _ElevatedBadge extends ConsumerWidget {
  const _ElevatedBadge({required this.session});

  final AccessSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final orange = HmiStateColors.of(context).orange;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kAccessStatusActionMaxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 20, color: orange),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.user!.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  session.roleName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: orange),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: orange),
            tooltip: 'Sign out',
            // Always available while elevated: spec §5 requires logging out to
            // be explicit and one tap from the app bar.
            onPressed: () => ref.read(accessSessionProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}
