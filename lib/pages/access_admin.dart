/// The administration screen: roles, accounts, and the paragraph that says
/// what all of it is not.
///
/// **One page, two sections** (06-CONTEXT, "Roles Screen"). A single
/// `/advanced/access` route with the roles section above the users section.
/// `key_repository.dart` already stacks gated sections on one page and is the
/// analog; two Advanced entries would crowd a menu that is already long.
/// The order is the commissioning order — create roles, then accounts, then
/// close the first-user window — which is the sequence
/// `docs/access-control-deployment.md` §4 now spells out.
///
/// **This file composes and nothing else.** No store, no repository, no Drift,
/// no query, no write. Both sections own their own reads, their own writes and
/// their own four terminal states; the one thing this page owns that neither
/// section does is the *page-level* loading affordance, because a section is
/// one card on a screen and a page is the whole screen.
///
/// **No gate here.** The `users` gate is applied at the route, exactly as it is
/// for the other eight raised routes (`lib/access_routes.dart`,
/// `lib/widgets/access_gate.dart`). A second gate inside the page would be a
/// second place to get it wrong, and it would also hide the honesty note from a
/// `configure`-only engineer — who is precisely the person who might otherwise
/// conclude that the HMI has logins.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/access_admin.dart';
import '../widgets/base_scaffold.dart';
import 'access_roles_section.dart';
import 'access_session_section.dart';
import 'access_users_section.dart';

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

/// The route's title, in the app bar and in the Advanced menu.
///
/// One string, declared once, because 06-10 has to repeat it in three places —
/// the route table, the menu entry and the gate's locked scaffold — and three
/// spellings of one screen's name is how a locked page stops looking like the
/// page it locks. Short and unambiguous: "Access" is what the milestone is
/// called everywhere else in this tree.
const String kAccessAdminTitle = 'Access';

// ---------------------------------------------------------------------------
// The honesty note
//
// PROJECT.md's `## What This Is Not` and `docs/access-control-spec.md` §8 both
// require this text in *"the admin screen's own help text"*, and this is that
// screen. It is not a disclaimer and it is not legal cover: a softened version
// of it is the failure mode it exists to prevent, which is a site reading "the
// HMI has access control" and moving network segmentation down the list.
//
// So: no reassuring hedge, no "for more information" pointer to a document
// nobody at a panel can open, no dismiss control, and no gate. Every sentence
// below is PROJECT.md's or `docs/access-control-deployment.md` §1's, kept at
// its own bluntness.
//
// It also must not contradict `first_user.dart`'s `_kHonesty` — *"Signing in
// records who changed what. It is a guardrail, not a security boundary."* —
// which is the same claim in one line. [kAccessAdminHonestySummary] is the
// longer screen's version of that sentence, and a test pins both halves of it.
// ---------------------------------------------------------------------------

/// The collapsed title, and therefore the whole note as far as a reader who
/// never opens it is concerned.
///
/// It is written to be **true on its own**. A title that teased the body — "A
/// note about what this screen is" — would make the collapsed state a lie
/// about the expanded one, and the collapsed state is the one almost everybody
/// sees.
const String kAccessAdminHonestySummary =
    'This screen records who changed what. It is a guardrail, not a security '
    'boundary.';

/// What the milestone does. Every level, and refusals as well as changes.
const String kAccessAdminHonestyRecords =
    'What it records: every hand-made change on this station, at every level — '
    'setpoints, device parameters, forces, page and key configuration, and the '
    'roles and accounts on this screen — written against whoever was signed in '
    'at the time. A refusal leaves a row as surely as a change does. The trail '
    'is append-only, and nothing on this screen can prune it or export it.';

/// What it does not do, and the three credentials that are the reason.
///
/// The three are named rather than gestured at, because "some credentials are
/// held by the station" is exactly the vague version this paragraph replaces.
/// The wording follows `docs/access-control-deployment.md` §1's table.
const String kAccessAdminHonestyCredentials =
    'What it does not do: stop anybody. Three credentials are held by this '
    'station rather than by a person — the OPC UA session, the Postgres '
    'password, and the D-Bus credential behind system settings — and every one '
    'of them authenticates the station, never a person. Anyone with UaExpert '
    'or psql reaches the plant and the database without passing anything on '
    'this screen. A username and a password here tell you who was standing at '
    'the panel; they do not stop anybody who is not.';

/// The actual failure mode, in PROJECT.md's own words.
const String kAccessAdminHonestyDanger =
    'The danger is not the guardrail. The danger is somebody concluding that '
    'the HMI has logins and deprioritising network segmentation on the '
    'strength of it. The network segmentation is the control. This is the '
    'guardrail inside it.';

/// When this stops being true — in the good direction, so the note ends on a
/// condition somebody can work towards rather than on a warning.
const String kAccessAdminHonestyWhen =
    'That changes, in the good direction, when the relay pipe takes over '
    'preferences and credentials come off the client. Until then this is what '
    'it is: an accurate account of accident and shift confusion, which is the '
    'realistic failure in a plant, and no defence at all against somebody who '
    'would rather not be recorded.';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

/// The page-level progress indicator.
///
/// Its own key rather than a bare [CircularProgressIndicator] finder: the two
/// sections may each show a spinner of their own inside a dialog, and a test
/// meaning "the page has not decided yet" must not pass on one of those.
const Key kAccessAdminLoadingKey = Key('access-admin-loading');

/// The honesty note's card.
const Key kAccessAdminHonestyKey = Key('access-admin-honesty');

/// The collapsed title. Also the tap target that opens the note.
const Key kAccessAdminHonestySummaryKey = Key('access-admin-honesty-summary');

/// The four body paragraphs, one key each.
///
/// Separate keys rather than one for the body: each paragraph makes a different
/// claim, and a test meaning "the credentials are named" must not pass on a
/// screen that only said the trail is append-only.
const Key kAccessAdminHonestyRecordsKey = Key('access-admin-honesty-records');
const Key kAccessAdminHonestyCredentialsKey =
    Key('access-admin-honesty-credentials');
const Key kAccessAdminHonestyDangerKey = Key('access-admin-honesty-danger');
const Key kAccessAdminHonestyWhenKey = Key('access-admin-honesty-when');

// ---------------------------------------------------------------------------
// Heights
//
// Two variable-height lists on one page make this number matter more than it
// does on `key_repository.dart`, which has one. Both figures below were
// measured, not chosen: a nudged constant here is a page that reads correctly
// on a 1080p panel and clips on a cabinet-door screen.
// ---------------------------------------------------------------------------

/// Everything on this page that is not a role row or an account row: the page
/// padding, both section cards' frames, the two 16 px gaps and the honesty note
/// in its collapsed state.
///
/// **Measured at 800 px wide**, which is the width the widget tests and the
/// goldens run at and the narrower — therefore taller — of the two cases:
///
/// | Piece | Height |
/// |---|---|
/// | page padding, top and bottom | 24 |
/// | roles card frame — margins, header row, subtitle | 136 |
/// | gap | 16 |
/// | users card frame — margins, header row, subtitle | 136 |
/// | gap | 16 |
/// | the honesty note, collapsed | 66 |
///
/// 394 px, rounded up to 400. The two card frames were derived rather than
/// eyeballed: the seeded roles card measures 421 px with four role rows summing
/// to 285 px, and the seeded users card 268 px with a 28 px header and two
/// 52 px rows — 136 px of frame each way, from two independent measurements
/// that agree.
///
/// The note's 66 px is its collapsed [ExpansionTile] inside a [Card], measured
/// rather than assumed — a bare Material tile is 56 px and this one is taller
/// because its title is a wrapping sentence rather than a label.
/// **Adding a paragraph to the note does not move this number**, because an
/// [ExpansionTile]'s collapsed height does not depend on its children and the
/// note ships collapsed.
const double kAccessAdminChromeHeight = 400;

/// The room the two lists are worth showing in at all: the four seeded roles,
/// and a commissioned station's two accounts under their column header.
///
/// **Measured at 800 px wide against the seeded database.** The four seeded
/// roles are not equal: `Operator` 64 px, `Maintenance` 70 px, `Shift Leader`
/// 64 px and `Engineering` 87 px — they differ because the summary line lists
/// the groups the role grants and `Engineering` grants all seven, so it wraps.
/// That is 285 px. The roster is a 28 px column header plus two 52 px rows,
/// 132 px. 417 px, rounded up to 424.
///
/// Below this the page has no room for a list worth reading and is scrolled as
/// a whole instead. It is deliberately **not** the height of a full roster: a
/// site with thirty accounts scrolls, and sizing the floor to the largest
/// plausible roster would put every panel below the threshold and make the
/// fallback the normal case rather than the short-window one.
const double kAccessAdminMinListsHeight = 424;

/// The height below which this page is given its measured height and scrolled,
/// rather than being laid out in the window it was handed.
///
/// The sum of the two measurements above, and derived rather than declared, so
/// that changing either one moves the threshold with it. A 1080p station is far
/// above it and lays out directly.
const double kAccessAdminMinContentHeight =
    kAccessAdminChromeHeight + kAccessAdminMinListsHeight;

/// The gap between the two sections and between the users section and the note.
const double _kSectionGap = 16;

/// The page's own padding.
const EdgeInsets _kPagePadding = EdgeInsets.fromLTRB(12, 12, 12, 12);

// ---------------------------------------------------------------------------
// The page
// ---------------------------------------------------------------------------

/// Route target for the administration screen.
///
/// Field-less on purpose so `createLocationBuilder` can register it as
/// `const AccessAdminPage()`, the same way `FirstUserPage` is. All of the
/// content lives in [AccessAdminBody].
class AccessAdminPage extends StatelessWidget {
  const AccessAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const BaseScaffold(
      title: kAccessAdminTitle,
      body: AccessAdminBody(),
    );
  }
}

/// The page content, split from [AccessAdminPage] so tests and goldens can pump
/// it without [BaseScaffold]'s routing context.
///
/// [BaseScaffold] calls `context.currentBeamLocation`, so it cannot be pumped
/// without a Beamer ancestor. `FirstUserBody`, `IpSettingsBody`,
/// `ServerConfigBody` and `KeyRepositoryContent` are the same split for the
/// same reason.
class AccessAdminBody extends ConsumerWidget {
  const AccessAdminBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(accessAdminStoreProvider);

    // The one state this page owns that neither section does.
    //
    // A section renders `SizedBox.shrink()` here, on purpose: it is one card
    // on a screen somebody came to for something else, and a spinner that
    // flashes for a frame on every station is what `AccessLockBadge` and
    // `AccessStatusAction` both refuse to draw. A whole *page* must not do
    // that. `access_gate.dart` says why for the waiting gate — "this route was
    // reached deliberately and an empty one reads as broken" — and
    // `first_user.dart`'s `_loading` says the same thing for a page that is
    // still resolving its database handle. Both are this page's case.
    if (!storeAsync.hasValue && !storeAsync.hasError) {
      return const Center(
        child: CircularProgressIndicator(key: kAccessAdminLoadingKey),
      );
    }

    // Deliberately **not** branched past this point. The store's error state
    // and its null state are each rendered by both sections, in their own
    // words, with their own keys. A third message at page level would be a
    // fourth thing that can contradict the other two, and the first time one
    // wording changed it would be the one nobody updated.
    //
    // Both sections are `const`: a page rebuild — and the store provider
    // resolving is one — then does not rebuild either subtree.
    const content = Padding(
      padding: _kPagePadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AccessRolesSection(),
          SizedBox(height: _kSectionGap),
          AccessUsersSection(),
          SizedBox(height: _kSectionGap),
          AccessSessionSection(),
          SizedBox(height: _kSectionGap),
          _HonestyNote(),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // **The scroll view is unconditional, and that is where this page
        // departs from `key_repository.dart`'s otherwise identical fallback.**
        // That page has an `Expanded` key list which absorbs a roster of any
        // size, so it can lay out directly on a tall window. Neither section
        // here is bounded or scrolled — both say so in their own class docs:
        // *"the page composing this section owns the scroll view"* — so a site
        // with thirty accounts overflows a 1080p panel without one.
        //
        // What the measured minimum then buys is the short window: below it,
        // the content is given the height it was measured at instead of the
        // window's, so the page a cabinet-door panel scrolls is the same page
        // a station shows rather than a differently wrapped one.
        final double floor = constraints.maxHeight >= kAccessAdminMinContentHeight
            ? 0
            : kAccessAdminMinContentHeight;
        return SingleChildScrollView(
          // Not the primary scroll view: a dialog opened from either section
          // brings its own, and leaving this one primary would hand it the
          // PrimaryScrollController and make the two indistinguishable to a
          // test helper.
          primary: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: floor),
            child: content,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// The note
// ---------------------------------------------------------------------------

/// One short expandable note at the foot of the page — the milestone's honesty
/// requirement, discharged on the screen `docs/access-control-spec.md` §8
/// names.
///
/// **Collapsed is the settled default, on purpose.** `initiallyExpanded` is
/// false and nothing toggles it, so the page reaches a resting state in one
/// frame. 06-11 captures this page in four goldens and every one of them
/// depends on that: an [ExpansionTile] that opened itself would make each
/// capture a function of how many frames the harness pumped.
///
/// **Not gated, not conditional, not dismissible.** It renders for every
/// session that can see the page, in every state of the store, and there is no
/// "do not show again" — that would be a preference key, which is a
/// `configure`-classified write, hiding the one paragraph the spec requires.
/// There is also no link out: the station that most needs this paragraph is
/// the one standing in a plant room with no way to open a document.
class _HonestyNote extends StatelessWidget {
  const _HonestyNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: kAccessAdminHonestyKey,
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: Icon(Icons.info_outline,
            size: 20, color: theme.colorScheme.onSurfaceVariant),
        title: Text(
          kAccessAdminHonestySummary,
          key: kAccessAdminHonestySummaryKey,
          // The title is the note for most readers, so it wraps rather than
          // truncating for the same reason every paragraph below does.
          maxLines: null,
          style: theme.textTheme.titleSmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _note(context, kAccessAdminHonestyRecords,
              key: kAccessAdminHonestyRecordsKey),
          const SizedBox(height: 8),
          _note(context, kAccessAdminHonestyCredentials,
              key: kAccessAdminHonestyCredentialsKey),
          const SizedBox(height: 8),
          _note(context, kAccessAdminHonestyDanger,
              key: kAccessAdminHonestyDangerKey),
          const SizedBox(height: 8),
          _note(context, kAccessAdminHonestyWhen,
              key: kAccessAdminHonestyWhenKey),
        ],
      ),
    );
  }
}

/// A secondary line, never ellipsised. Every sentence of the note goes through
/// here so none of them can quietly become one clipped line — `find.text`
/// passing is not the same as the operator being able to read it, and a
/// warning the eye skips because it was cut short has not been given.
///
/// The same helper both sections carry, by the same argument.
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
