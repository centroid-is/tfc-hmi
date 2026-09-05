/// The two notice blocks the administration screen's two sections share: a
/// warning, and a refusal.
///
/// **Why this file exists before either section does.** 06-07 writes the roles
/// section and 06-08 writes the users section, in parallel, in two files. Both
/// need to warn — the `Operator` row governs every logged-out panel — and both
/// need to refuse: the last-`users`-holder invariant and a role still held by
/// accounts are refusals either section can hit. Two sections each inventing a
/// warning block is how two warning registers start diverging, and two refusal
/// wordings for the same rule is how an operator ends up reading two different
/// accounts of one refusal. So the frame is written once, here, and both
/// sections render through it.
///
/// **The register, and why it is not a fault colour.** `surfaceContainerHighest`
/// on `outlineVariant` with `onSurfaceVariant` text and icon — the theme's own
/// warning surface, copied from `access_templates_section.dart`'s
/// `_WarningBlock` and matching `access_gate.dart`'s locked page. Never a raw
/// Material palette constant, and never the `HmiStateColors` fault or elevation
/// members: red is the plant's fault colour, orange means forced or elevated,
/// and a lock is neither. The ruling was settled twice already in this
/// milestone and this file is the third place it holds.
/// (`lib/pages/key_repository.dart`'s `_DatabaseStatusBanner` reaches straight
/// into the Material palette for its red; it predates the convention and is a
/// counter-example, not a precedent.)
///
/// **It renders what it is handed.** No provider, no store, no `ref`. That is
/// what lets it be tested without a container and reused by two sections that
/// hold different stores.
///
/// **What it deliberately does not provide.** The `Operator` warning's own
/// sentence. That wording exists in three places already —
/// `access_repository.dart`'s class doc, `access_role.dart`, and
/// `docs/access-control-deployment.md` §5 — and 06-07 renders a short on-screen
/// version rather than adding a fourth phrasing here. This file is the frame;
/// 06-07 supplies the Operator text.
library;

import 'package:flutter/material.dart';
import 'package:tfc_dart/core/access/access_repository.dart';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

/// The warning block's own container.
const Key kAccessAdminWarningKey = Key('access-admin-warning');

/// The refusal block's own container. A separate key from the warning's
/// because a test that means "the change was refused" must not pass on a
/// screen that merely warned.
const Key kAccessAdminRefusalKey = Key('access-admin-refusal');

/// The leading sentence of either block.
const Key kAccessAdminNoticeTextKey = Key('access-admin-notice-text');

/// The trailing sentence, present only where there is one. The lockout refusal
/// has it and the in-use refusal does not, and that difference is assertable
/// precisely because the key is only rendered when the sentence is.
const Key kAccessAdminNoticeFootnoteKey = Key('access-admin-notice-footnote');

/// One name in the list beneath the sentence.
///
/// A function of the name, following `access_templates_section.dart`'s
/// discipline: a test asserts that *this* account reached the screen, not that
/// some row at some index did.
Key kAccessAdminNoticeNameKey(String name) =>
    Key('access-admin-notice-name-$name');

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

/// `n account` / `n accounts`, with the number in the sentence.
///
/// The count is a parameter of the copy rather than something the reader
/// derives from the length of the list beneath it. That is 06-CONTEXT's ruling —
/// *"showing the count and names of the holders"* — and the shape of the
/// precedent it names, `kAccessTemplateDeleteBlockedNote(String name, int keys)`
/// in `access_templates_section.dart`, which takes the count and renders the
/// names below. A sentence naming five people without saying "5" makes the
/// reader count them.
String _accounts(int n) => '$n account${n == 1 ? '' : 's'}';

/// The lockout refusal: trip routes (a) to (d), whichever one was taken.
///
/// Says the change was **not** made, names the role that is the only source of
/// the `users` group, and gives the count. The names follow beneath. It is
/// distinct from [kAccessAdminRoleInUseNote] because the two are different
/// problems with different fixes: this one is resolved by *widening* — grant
/// `users` to another role, or move another account onto this one — while a
/// role still in use is resolved by *moving accounts off it*. Telling an
/// operator to do one when they needed the other is worse than saying nothing.
String kAccessAdminLastUsersHolderNote(String roleName, int holders) =>
    'Not saved: this would leave nobody able to manage roles and accounts. '
    '"$roleName" is the only role granting the users group, and '
    '${_accounts(holders)} ${holders == 1 ? 'holds' : 'hold'} it. Grant users '
    'to another role, or move another account onto this one, first:';

/// The lockout refusal's second sentence, and the only place this milestone
/// points at break-glass from a screen.
///
/// Two things at once, deliberately: there is no override here, and there is a
/// documented way back if a station is ever locked out anyway. Saying only the
/// first reads as a dead end; saying only the second reads as an invitation.
/// It is attached to the lockout refusal alone — a role still held by accounts
/// is not a lockout and sending somebody to `DELETE FROM app_user` for it would
/// be advice that breaks things.
const String kAccessAdminBreakGlassNote =
    'There is no override. If a station is ever locked out anyway, recovery is '
    'the break-glass procedure in docs/access-control-deployment.md §4.';

/// The blocked role delete: accounts still hold it.
///
/// Says the role was **not** deleted, gives the count, and says what to do
/// instead. Distinct from [kAccessAdminLastUsersHolderNote] — see that
/// constant's note — and distinct in stakes too: this one is not an
/// authorization failure at all. It is blocked in application code rather than
/// by the foreign key, which this build never enables, and no sign-in resolves
/// it.
String kAccessAdminRoleInUseNote(String roleName, int holders) =>
    'Not deleted: ${_accounts(holders)} still '
    '${holders == 1 ? 'holds' : 'hold'} "$roleName". Deleting it would leave '
    'every one of them pointing at a role that is no longer there. Move them '
    'to another role first:';

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// A sentence, an optional list of names, and an optional second sentence, in
/// the milestone's warning register.
///
/// Copied from `access_templates_section.dart`'s `_WarningBlock` rather than
/// reinvented, colour comment and all, so the two blocks cannot drift apart.
/// The names are the same shape that file lists bound keys in: a short scrolled
/// column beneath the sentence, so ten holders do not push the sentence off the
/// screen.
class AccessAdminWarning extends StatelessWidget {
  const AccessAdminWarning({
    super.key,
    required this.text,
    this.names = const <String>[],
    this.footnote,
    this.icon = Icons.lock_outline,
    this.blockKey = kAccessAdminWarningKey,
  });

  /// The leading sentence. Never ellipsised — see [_note].
  final String text;

  /// The accounts, keys or roles the sentence is about, listed beneath it.
  final List<String> names;

  /// A second sentence, or null. Rendered in the secondary style.
  final String? footnote;

  /// `lock_outline` by default — this is shut, not broken. 06-07 passes
  /// `lock_open_outlined` for the `Operator` warning, which is about something
  /// becoming *less* restricted, matching `_WarningBlock`'s own choice.
  final IconData icon;

  /// The container's key, so a refusal and a warning are separately assertable.
  final Key blockKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = footnote;
    return Container(
      key: blockKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // The theme's own warning surface rather than a raw colour: only a
        // fault may be saturated, and this is not a fault.
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  key: kAccessAdminNoticeTextKey,
                  // Never ellipsised: a warning the eye skips because it was
                  // cut to one line has not been given.
                  maxLines: null,
                  overflow: TextOverflow.visible,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (names.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: ListView(
                shrinkWrap: true,
                primary: false,
                padding: EdgeInsets.zero,
                children: [
                  for (final name in names)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        name,
                        key: kAccessAdminNoticeNameKey(name),
                        maxLines: null,
                        overflow: TextOverflow.visible,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: 8),
            _note(context, note, key: kAccessAdminNoticeFootnoteKey),
          ],
        ],
      ),
    );
  }
}

/// A refusal, built from the exception the layer below threw.
///
/// **It offers no action.** No override button, no typed-confirmation field, no
/// "proceed anyway". That is `_DeleteTemplateDialog`'s doctrine — the
/// instruction takes the action's place, because a control that is present and
/// always refuses teaches the operator to press it twice — and, for the lockout
/// case, 06-CONTEXT's explicit rejection of a typed-confirmation escape.
/// `access_admin_notice_test.dart` counts buttons and text fields and asserts
/// zero, so that a later edit adding one fails rather than ships.
///
/// Neither refusal is an [AccessDenied] and neither is resolved by signing in:
/// the account that hits the lockout refusal is by definition one that already
/// holds `users`, and an Engineering user holding every group gets the in-use
/// refusal too. Rendering either through the shared locked prompt would send
/// somebody to find a colleague who cannot help either.
class AccessAdminRefusal extends StatelessWidget {
  /// The last-`users`-holder invariant refused the change.
  ///
  /// Carries the break-glass sentence; the other constructor does not.
  AccessAdminRefusal.lastUsersHolder(
    LastUsersHolderException refusal, {
    super.key,
  })  : text = kAccessAdminLastUsersHolderNote(
          refusal.roleName,
          refusal.holders.length,
        ),
        names = refusal.holders,
        footnote = kAccessAdminBreakGlassNote;

  /// The role is still held by accounts, so it was not deleted.
  AccessAdminRefusal.roleInUse(
    RoleInUseException refusal, {
    super.key,
  })  : text = kAccessAdminRoleInUseNote(
          refusal.roleName,
          refusal.holders.length,
        ),
        names = refusal.holders,
        footnote = null;

  /// The refusal sentence, count included.
  final String text;

  /// The holders the exception carried, already sorted by the repository.
  final List<String> names;

  /// The break-glass pointer, on the lockout refusal only.
  final String? footnote;

  @override
  Widget build(BuildContext context) => AccessAdminWarning(
        blockKey: kAccessAdminRefusalKey,
        text: text,
        names: names,
        footnote: footnote,
      );
}

/// A secondary line, never ellipsised.
///
/// Copied from `access_templates_section.dart` for the same reason it exists
/// there: every explanatory sentence in this file goes through one helper so
/// none of them can quietly become a clipped line, and `find.text` passing is
/// not the same as the operator being able to read it.
Widget _note(BuildContext context, String text, {Key? key}) {
  final theme = Theme.of(context);
  return Text(
    text,
    key: key,
    maxLines: null,
    overflow: TextOverflow.visible,
    style: theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
  );
}
