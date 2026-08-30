/// What a refused write looks like to the person who made it.
///
/// `AccessDenied` is thrown on the write path by `GuardedStateMan` and
/// `GuardedPreferences`, at roughly thirty asset call sites, none of which
/// handles it. Without this widget the visible result of the first denial on a
/// plant is a debug-mode red screen or, in release, nothing at all — and
/// "nothing at all" is worse, because the operator presses the button again.
///
/// **This prompt does not depend on anybody catching the exception.** Both
/// guards fire `onDenied` — which `lib/providers/*.dart` routes into
/// [reportAccessDenial] — *before* they throw, so the event reaches this
/// listener whether the call site swallows the throw, logs it, or lets it
/// escape to the framework. That ordering is the whole safety net; it is
/// asserted in `guarded_state_man_test.dart` ("the rows are written before the
/// exception is raised") and end-to-end in `access_denied_prompt_test.dart`.
///
/// **This is the safety net, not the good version.** Phase 4 is where the
/// elevation prompt fires at *tap* time and the control itself renders locked,
/// so a write that would be refused is never issued. What ships here is that
/// every denial reaches the operator meanwhile.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc_access/tfc_access.dart';

import '../providers/access_policy.dart';
import 'access_sign_in_dialog.dart';
import 'panes/pane_chrome.dart';
import 'panes/standard_dialog.dart';

/// How many `StateMan` write call sites in `lib/` do **not** handle
/// `AccessDenied`.
///
/// Derived on 2026-08-30 by walking every `.dart` file under `lib/`, dropping
/// comment lines, and counting the calls whose receiver is a `StateMan`:
///
/// ```sh
/// grep -rnE '\b(client|stateMan|sm|widget\.stateMan)\.write\(' \
///   --include='*.dart' lib/ | grep -v ':[0-9]*: *//'
/// grep -rn 'AccessDenied' lib/page_creator lib/widgets lib/pages   # empty
/// ```
///
/// `access_denied_prompt_test.dart` runs the same walk in Dart and asserts the
/// number, so the count cannot quietly grow, and it also asserts the second
/// grep is empty — the claim that none of these sites *handles* the refusal is
/// checked rather than assumed.
///
/// **What this number means, in the terms the phase agreed and no softer.**
/// At these call sites `AccessDenied` is not handled. At some of them —
/// `number.dart:473`, `conveyor.dart:2394`, the `advantys_stb.dart` and
/// `beckhoff.dart` force grids — it escapes as an unhandled asynchronous
/// error. At the rest — `start_stop_button.dart:184`, `button.dart`,
/// `section_button.dart`, `conveyor_gate.dart` — a bare `catch (e)` swallows
/// it into a log line, or, in `sensor.dart:773` and `schneider.dart:303`,
/// renders its developer string into a snackbar. **None of those is a
/// handling**: not one of them tells the operator what permission was missing
/// or offers a way through, which is why they are all counted here.
///
/// The operator still sees this prompt in every one of those cases, because
/// the guard publishes to `accessDenialsProvider` before it throws. Phase 4's
/// tap-time elevation is what removes the throw from the operator's path, by
/// never issuing a write that will be refused. This number is expected to fall
/// to zero there, and the test above is what makes that visible.
const int kUncaughtAccessDeniedWriteSites = 31;

/// The headline, kept at the top of the file so tests assert against the
/// string the widget renders rather than one they supply — the
/// `access_gate.dart` idiom.
///
/// Reads like `kAccessLockedHeadline` in `access_gate.dart`, not like an error: this write is shut,
/// not broken.
const String kAccessDeniedHeadline = 'Sign in to make this change';

/// Which permission was missing, named by [AccessGroup.name] — the same word
/// the roles screen shows, so "needs force" and the tick box that grants it
/// read alike.
String kAccessDeniedGroupNote(AccessGroup group) =>
    'This change needs the "${group.name}" permission.';

/// What was refused. An operator who pressed one of four buttons on a mimic
/// needs to know which one this is about.
String kAccessDeniedItemNote(String itemKey) => 'What was refused: $itemKey';

/// The never-replay rule, made visible rather than merely obeyed.
///
/// The requirement is that signing in "never replays the original action", and
/// nothing here holds the attempted write. This sentence is what stops an
/// operator signing in, walking away, and believing the jog happened.
const String kAccessDeniedNoReplayNote =
    'Nothing was changed. Signing in will not repeat this action for you — '
    'once you are signed in you will need to make the change again yourself.';

/// The prompt body, so a test can assert the prompt rendered at all.
const Key kAccessDeniedBodyKey = Key('access-denied-body');

/// The lock glyph. Keyed so a test can pin the colour it is painted in.
const Key kAccessDeniedLockKey = Key('access-denied-lock');

/// The permission line.
const Key kAccessDeniedGroupKey = Key('access-denied-group');

/// The refused-item line.
const Key kAccessDeniedItemKey = Key('access-denied-item');

/// The never-replay line's key, so a test can assert the widget carrying it is
/// not the single-line ellipsising kind. Phase 1 shipped exactly that defect
/// past a green `find.text`.
const Key kAccessDeniedNoReplayKey = Key('access-denied-no-replay');

/// The Sign in action.
const Key kAccessDeniedSignInKey = Key('access-denied-sign-in');

/// The dismissal.
const Key kAccessDeniedDismissKey = Key('access-denied-dismiss');

/// Marks that a prompt is already listening somewhere above.
///
/// `BaseScaffold` nests — a gated route builds one of its own around a page
/// that brings another — and two listeners on one broadcast stream would open
/// two dialogs for one refused write. The inner prompt sees this and stands
/// down.
class _AccessDeniedPromptScope extends InheritedWidget {
  const _AccessDeniedPromptScope({required super.child});

  @override
  bool updateShouldNotify(_AccessDeniedPromptScope oldWidget) => false;
}

/// Turns every refusal on [accessDenialsProvider] into a locked prompt.
///
/// **Costs nothing until it fires.** With no [child] it renders
/// `SizedBox.shrink()`; with one it renders the child itself and contributes
/// **no render object at all**, which is how it can be mounted in
/// `BaseScaffold` — a widget every page and four Phase 2 goldens pass through
/// — without moving a single pixel.
class AccessDeniedPrompt extends ConsumerStatefulWidget {
  const AccessDeniedPrompt({
    super.key,
    this.openSignIn = showAccessSignInDialog,
    this.child,
  });

  /// How the sign-in prompt is opened. Injectable so a widget test can count
  /// the taps without standing up a dialog route — the `AccessStatusAction`
  /// idiom.
  final AccessSignInOpener openSignIn;

  /// The subtree this prompt watches over, passed through untouched.
  ///
  /// Passing the page through rather than sitting beside it in a `Stack` is
  /// deliberate: a `Stack` would re-constrain the body — `Scaffold` hands it
  /// `_BodyBoxConstraints`, and a stack sizes and positions its children
  /// itself — and the pixel budget for this plan is zero.
  final Widget? child;

  @override
  ConsumerState<AccessDeniedPrompt> createState() => _AccessDeniedPromptState();
}

class _AccessDeniedPromptState extends ConsumerState<AccessDeniedPrompt> {
  StreamSubscription<AccessDenied>? _subscription;

  /// True from the moment a refusal is taken until its prompt closes.
  ///
  /// Set synchronously, before the first `await`, so the three further
  /// denials a struct write produces are **dropped** rather than queued: one
  /// action, one prompt. Not latched — it clears when the prompt closes, so
  /// the operator's next refused action gets its own.
  bool _showing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // A prompt above us is already listening; a second subscription would open
    // a second dialog for the same refusal.
    if (context
            .dependOnInheritedWidgetOfExactType<_AccessDeniedPromptScope>() !=
        null) {
      _subscription?.cancel();
      _subscription = null;
      return;
    }

    // `ref.read`, not `watch`: the provider holds a broadcast stream that
    // never changes value, and a watch here would rebuild the page's whole
    // subtree on any container churn.
    _subscription ??= ref.read(accessDenialsProvider).listen(_onDenied);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _onDenied(AccessDenied denial) async {
    if (_showing || !mounted) return;
    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => _AccessDeniedDialog(
          denial: denial,
          onSignIn: _signIn,
        ),
      );
    } finally {
      _showing = false;
    }
  }

  /// Dismisses the prompt and opens the sign-in form.
  ///
  /// **Nothing is retried here, and nothing is remembered to retry.** The
  /// refused write is not held anywhere, so signing in cannot replay it —
  /// which is the requirement, and [kAccessDeniedNoReplayNote] is how the
  /// operator is told.
  Future<void> _signIn(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    if (!mounted) return;
    try {
      await widget.openSignIn(context, ref);
    } on Object catch (error) {
      // A sign-in form that fails to open must not take the page with it.
      debugPrint('AccessDeniedPrompt: could not open the sign-in form: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (child == null) return const SizedBox.shrink();
    return _AccessDeniedPromptScope(child: child);
  }
}

/// The prompt itself: what was refused, what it needed, and that it did not
/// happen.
///
/// Built on [StandardDialogFrame] rather than a surface of its own, so a
/// refusal looks like the rest of the app instead of like a new feature — the
/// same frame `AccessSignInDialog` uses, with `showClose: false` for the same
/// reason: the two actions below already cover dismissal, and a third
/// affordance in the corner would make "exactly a sign-in and a dismissal"
/// untrue.
class _AccessDeniedDialog extends StatelessWidget {
  const _AccessDeniedDialog({required this.denial, required this.onSignIn});

  final AccessDenied denial;
  final Future<void> Function(BuildContext dialogContext) onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary =
        theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    return StandardDialogFrame(
      title: kAccessDeniedHeadline,
      icon: Icons.lock_outline,
      showClose: false,
      actions: [
        PaneAction(
          buttonKey: kAccessDeniedDismissKey,
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PaneAction.primary(
          buttonKey: kAccessDeniedSignInKey,
          label: 'Sign in',
          onPressed: () => unawaited(onSignIn(context)),
        ),
      ],
      child: Column(
        key: kAccessDeniedBodyKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A lock, not a warning triangle: this write is shut, not
              // broken. `onSurfaceVariant` rather than HmiStateColors.orange,
              // which means forced/override and — since plan 01-08 — an
              // elevated session; a lock is neither, and red is the plant's
              // fault colour.
              Icon(
                Icons.lock_outline,
                key: kAccessDeniedLockKey,
                size: 28,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  kAccessDeniedGroupNote(denial.required),
                  key: kAccessDeniedGroupKey,
                  maxLines: null,
                  overflow: TextOverflow.visible,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The item key, never `denial.toString()`: that is a developer
          // string and this is the operator's prompt.
          Text(
            kAccessDeniedItemNote(denial.itemKey),
            key: kAccessDeniedItemKey,
            maxLines: null,
            overflow: TextOverflow.visible,
            style: secondary,
          ),
          const SizedBox(height: 12),
          Text(
            kAccessDeniedNoReplayNote,
            key: kAccessDeniedNoReplayKey,
            maxLines: null,
            overflow: TextOverflow.visible,
            style: secondary,
          ),
        ],
      ),
    );
  }
}
