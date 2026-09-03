/// One session's view of the shared source, with the policy already applied.
///
/// **Source: 06-RESEARCH §E.2**, and orchestrator ruling OQ1 approving the
/// shape. Four placements were considered and three rejected: per-call-site
/// checks inside the handlers (six sites today, six *files* by Phase 10, and
/// the one somebody forgets is the unauthorized surface), `ServedStateMan` (a
/// test-kit peer, not production) and `LocalStateMan` (does not exist yet, and
/// is one instance shared by every panel while policy is per identity).
///
/// What is left is a decorator, and the argument for it is the one
/// `relay_session.dart:484-489` already makes about the handshake gate: the
/// check belongs at the seam every request comes through, because "a
/// per-handler check would be a rule every future plan has to remember, and
/// the one it forgot would be the method that serves plant data to a client
/// that never authenticated". `RelaySession` hands this object — never the
/// source it wraps — to both `SessionHandlers` and `ValueHandlers`, so a
/// handler added in Phase 10 cannot reach around the policy, because there is
/// no unwrapped source in scope to reach for (T-06-38).
///
/// ## What breaks in the plant without this file
///
/// Nothing today, and that is the honest answer: the shipped policy is
/// all-visible and `operate`-writes, so this object is transparent and the
/// whole suite is unchanged by it. What breaks is *later*. The first
/// deployment that needs one station not to see one tag would otherwise get
/// six hand-written checks across five files, and the hiding rule — hidden is
/// indistinguishable from nonexistent — cannot survive being spelled six
/// times. It survives being spelled once, in [keys].
///
/// ## `keys` is the hiding primitive
///
/// This is the whole design and it is worth stating plainly. Every surface
/// that can reveal a tag's existence already gates on `keys`:
///
///  * `value_handlers.dart:212` — `read`'s `api.keys.contains`.
///  * `value_handlers.dart:244` — `readFresh`'s, added by 06-04.
///  * `value_handlers.dart:276` — `readMany`'s `servable` set.
///  * `value_handlers.dart:387` — `write`'s, and with it `holdToRun`, which
///    is reachable only through the write path.
///  * `session_handlers.dart:184` + `:303-315` — `subscribe`'s `_classify`,
///    whose own doc says "Phase 6's per-key authorization attaches here: one
///    more arm, no change of shape". It turned out to need no arm at all.
///
/// So filtering one getter gives hiding on five surfaces **byte-identically to
/// a nonexistent tag**, with no edit to either handler file. That is not a
/// coincidence to be grateful for — it is why the answer for an unserved tag
/// was consolidated into one helper in 06-04 first, and it is what
/// `policy_test.dart`'s indistinguishability case exists to keep true.
///
/// ## The four sub-APIs, and all four now decide something
///
/// `browse`, `timeseries`, `historyViews` and `preferences` return wrappers.
/// They are wrapped rather than returned bare so the "no unwrapped source to
/// reach" property holds for them too: a handler that takes `api.browse` gets
/// something this session owns, not the shared object itself.
///
/// Through Phase 9 all four merely delegated, and the reason was that none of
/// their methods was on the wire — the handler table was nine names and the
/// contract legs enumerated thirteen unreachable checks, every one a sub-API
/// method. A policy call nothing can reach would read like coverage while
/// testing nothing, which `suite_integrity_test.dart:104-108` calls worse than
/// an absent one.
///
/// **10-02 registered the four `browse.*` handlers, so browse filters**;
/// **10-03 the four `timeseries.*` ones, so timeseries does too** — each with
/// cases that can see it, and each as an entry in the indistinguishability
/// loop (browse seventh, timeseries eighth). **10-04 filled in history views**,
/// which drops a hidden key from a view rather than the view from the picker,
/// and **10-05 preferences**, which is the one of the four that does not hide
/// anything: it *gates*, because a preference key is not a plant key and the
/// question it settles is who may write `key_mappings`. The rule stands
/// unchanged — a filter lands in the commit that makes the surface reachable,
/// never before it and never after.
library;

import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../auth/identity.dart';
import '../error_codes.dart';
import 'key_policy.dart';
import 'series_mapping_tally.dart';

/// The shared source, seen through one session's policy.
///
/// Implements [StateManApi] and **adds no interface members**, which is how
/// 06-CONTEXT amendment 3 is satisfied by construction:
/// `api_surface_test.dart` walks the five interface *types* by mirrors and
/// never an implementation, so the 49 cannot move because of anything in this
/// file.
///
/// Written as explicit member-by-member delegation rather than with
/// `noSuchMethod` forwarding. A forwarder would silently absorb a member added
/// to `StateManApi` in a later phase — the new member would work, unpoliced,
/// and nothing would say so — which is the exact opposite of what the
/// hand-written 49 exists to make visible. Here a new member is a compile
/// error in this file, and the fix is a deliberate decision about whether it
/// needs the policy.
final class PolicyStateMan implements StateManApi {
  PolicyStateMan({
    required this.source,
    required this.policy,
    required this.resolver,
    required this.tally,
    required this.identityOf,
  });

  /// The shared source every session on this gateway is served from.
  ///
  /// **Named `source`, and it must not be renamed to `api`.**
  /// `tfc_relay_client/test/no_retry_test.dart:220-245` pins `api.write(` and
  /// `api.holdToRun(` at exactly one non-comment occurrence each under this
  /// package's `lib/`, because those are the gateway's only two crossings into
  /// the plant and a second one is a second actuation. A delegate field called
  /// `api` would add one of each and trip both pins — with a failure message
  /// about *retries*, on a file that has nothing to do with retrying, which is
  /// an afternoon nobody needs to spend.
  final StateManApi source;

  final KeyPolicy policy;

  /// How a node id and a table name become the plant key [canSee] is asked
  /// about.
  ///
  /// The browse and timeseries filters need it and nothing else in this class
  /// does: `keys` is already a list of plant keys, so the five surfaces that
  /// inherit hiding from it never had a translation problem. Browse walks the
  /// upstream address space, where every identifier belongs to the server that
  /// published it; timeseries is keyed by a series name, which has to become a
  /// table and a plant key before `canSee` can be asked anything. History
  /// views need no translation at all — a view is already a list of plant
  /// keys.
  ///
  /// Required, no default. See `relay_server.dart`'s `resolver` parameter.
  final SeriesResolver resolver;

  /// Where a series this gateway cannot map is recorded.
  ///
  /// **Gateway-wide, not per session**, and required for the same reason
  /// [resolver] is: a tally created here by default would reset every time a
  /// panel reconnected, which is exactly the number that has to accumulate.
  /// See [SeriesMappingTally] for why a count exists at all when the wire
  /// answer is deliberately silent.
  final SeriesMappingTally tally;

  /// Who is asking, read **late**.
  ///
  /// The `epochOf` / `ownerOf` idiom (`relay_session.dart:559`, `:576`) and
  /// for the identical reason: this object is built during the session's
  /// `_start`, and the identity is minted later, by `_hello`. A captured value
  /// would be null forever.
  ///
  /// **Nullable, and null means "nothing", not "everything".** A pre-hello
  /// session has no identity (`relay_session.dart:383-394`), so there is no
  /// station for the policy to answer about. That state is unreachable from
  /// the wire — the handshake gate refuses every key-touching method before
  /// `hello`, and `handler_table_test.dart`'s pre-hello sweep is what keeps it
  /// that way — but "unreachable" is a property of today's gate rather than of
  /// this class, and the two ways to spell an unreachable state are a `!` that
  /// crashes the session or an answer that is safe if it ever happens. This
  /// takes the second: no identity, no visibility, no writes. A gateway that
  /// showed the plant to a peer it could not name would be the failure worth
  /// preventing; a session that saw nothing before saying hello is one it
  /// could not have used anyway.
  final Identity? Function() identityOf;

  /// Whether the asking station may know [key] exists.
  ///
  /// Public because it is the same question `RelaySession` needs for the
  /// write gate, and one object answering both is what "every surface
  /// consults one policy object" means. Not on [StateManApi] — see this
  /// class's doc.
  bool canSee(String key) {
    final identity = identityOf();
    return identity != null && policy.canSee(key, identity);
  }

  /// Whether the asking station may actuate [key].
  ///
  /// Consulted by `ValueHandlers` through the `canWriteKey` predicate
  /// `RelaySession` builds from it, after the existence check and before the
  /// fingerprint, the idempotency window and the outcome log.
  bool canWrite(String key) {
    final identity = identityOf();
    return identity != null && policy.canWrite(key, identity);
  }

  // -------------------------------------------------------------------------
  // StateManApi — the thirteen members plus dispose.
  // -------------------------------------------------------------------------

  /// **The hiding primitive.** See this library's doc.
  ///
  /// One `where`, and five surfaces inherit hiding from it.
  @override
  List<String> get keys => source.keys.where(canSee).toList();

  @override
  ValueListenable<DynamicValue> listen(String key) => source.listen(key);

  @override
  Stream<DynamicValue> subscribe(String key) => source.subscribe(key);

  @override
  DynamicValue? read(String key) => source.read(key);

  /// **An override, not a delegation** (§E.2 item 2).
  ///
  /// Every other read surface is answered by a handler that consults [keys]
  /// first, so a hidden tag never gets this far over the wire. This one is
  /// written out anyway because the alternative is letting the source choose
  /// the answer, and the sources disagree: `FakeStateMan` happens to answer
  /// `q:258` ("no reading yet, wait") for a tag it does not serve, while
  /// `LocalStateMan` over a real `DeviceClient` may throw. Neither is the
  /// nonexistent shape this gateway promises, and the round trip itself is a
  /// side channel — a caller who may not know the tag exists should not be
  /// able to make the plant be asked about it.
  ///
  /// `errorConfig` is the gateway's own answer for an unserved tag: 770 means
  /// "the source affirmatively said this tag is gone", which 06-04 settled as
  /// the quality `read` and `readFresh` both give it. The wire-level shape —
  /// the `rejected` map and the message — is `value_handlers.dart`'s
  /// `_unserved`, and it is reached before this method by the `keys` check
  /// there.
  @override
  Future<DynamicValue> readFresh(String key) async {
    if (!canSee(key)) {
      return DynamicValue.of(null, quality: Quality.errorConfig);
    }
    return source.readFresh(key);
  }

  @override
  Future<Map<String, DynamicValue>> readMany(List<String> keys) =>
      source.readMany(keys);

  @override
  Future<WriteResult> write(String key, Object? value,
          {Object? expect, String? cmd}) =>
      source.write(key, value, expect: expect, cmd: cmd);

  @override
  Future<List<WriteResult>> writeStatus(List<String> cmds) =>
      source.writeStatus(cmds);

  @override
  Future<HoldHandle> holdToRun(String key) => source.holdToRun(key);

  @override
  BrowseApi get browse => _PolicyBrowse(source.browse, resolver, canSee);

  @override
  TimeseriesApi get timeseries =>
      _PolicyTimeseries(source.timeseries, resolver, canSee, tally);

  @override
  HistoryViewApi get historyViews =>
      _PolicyHistoryViews(source.historyViews, canSee);

  @override
  PreferencesApi get preferences =>
      _PolicyPreferences(source.preferences, identityOf);

  /// Delegates, and owns nothing of its own to release.
  ///
  /// The source is **one instance shared by every session** on this gateway
  /// (`relay_server.dart:213-214`: "One instance, shared" — two panels
  /// watching one motor must be served by one upstream subscription). Nothing
  /// in `RelaySession`'s teardown calls this, and nothing should: a
  /// per-session dispose of a shared source would take the whole plant off
  /// the air when one panel goes home. The delegation exists so an embedder
  /// that built one of these by hand can still release what it wrapped.
  @override
  Future<void> dispose() => source.dispose();
}

// ---------------------------------------------------------------------------
// The four sub-APIs. Browse filters as of 10-02, timeseries as of 10-03,
// history views as of 10-04, and preferences gates as of 10-05 — three that
// hide and one that refuses, and the difference is at each declaration. See
// the library doc for why each of those words is deliberate.
// ---------------------------------------------------------------------------

/// Navigating the address space, **with the hiding rule applied** (10-02).
///
/// Browse is the seventh way to ask whether a tag exists and the first that
/// does not inherit hiding from [PolicyStateMan.keys]: the other six all gate
/// on that one list of plant keys, and this one walks the *upstream* address
/// space, where a node id belongs to the server that published it rather than
/// to the plant's key namespace. So it needs a translation, and that is what
/// [SeriesResolver.keyForNode] is.
///
/// Three rules, and the second and third are the ones a reader will not guess:
///
///  1. **A hidden node is dropped from a list, never refused.** A refusal
///     names what it refused; ask about a thousand names, keep the ones
///     refused rather than absent, and the plant's address space has been
///     enumerated by a station that may not read a byte of it (T-06-36).
///  2. **Only a *variable* is asked about.** `canSee` takes a plant key and a
///     folder is not one. A node the resolver maps to no key at all — a
///     folder, an intermediate struct, a method — is not asked about and is
///     not dropped. Pruning a folder would take every tag under it off the
///     tree, including the ones the station may see, on the strength of a
///     policy entry that was never about the folder.
///  3. **A path through a hidden node is null, not truncated.** A chain that
///     stopped at the last visible node would claim an edge that is not there
///     and would announce "something you may not see is under here" as
///     clearly as a refusal would.
///
/// Written as explicit member-by-member delegation like everything else in
/// this file — **never `noSuchMethod`** (see the class doc above): a forwarder
/// would absorb an interface member added later and serve it unfiltered.
///
/// Under the shipped [AllVisibleOperatorWrites] this whole class is a no-op —
/// `canSee` is `true` for every key — which is why the six browse contract
/// checks are unchanged by it. That is the acceptance shape 06-08 established:
/// a filter must be provably invisible against the default policy.
final class _PolicyBrowse implements BrowseApi {
  const _PolicyBrowse(this._source, this._resolver, this._canSee);

  final BrowseApi _source;
  final SeriesResolver _resolver;

  /// [PolicyStateMan.canSee], passed as a function rather than as the whole
  /// decorator so this class cannot reach anything else on it.
  final bool Function(String key) _canSee;

  /// Whether this station may know [node] is in the address space.
  ///
  /// Rule 2 above, in the order the checks have to happen: kind first, then
  /// the mapping, then the policy. Reordering them would ask `canSee` about a
  /// folder id, which is a string the policy was never written about.
  bool _visible(BrowseNode node) {
    if (!node.isVariable) return true;
    final key = _resolver.keyForNode(node.id);
    if (key == null) return true;
    return _canSee(key);
  }

  @override
  Future<List<BrowseNode>> fetchRoots() async =>
      (await _source.fetchRoots()).where(_visible).toList();

  @override
  Future<List<BrowseNode>> fetchChildren(BrowseNode parent) async =>
      (await _source.fetchChildren(parent)).where(_visible).toList();

  /// The detail of [node], or — for one this station may not see — **the
  /// answer a node that does not exist gets**.
  ///
  /// The source is not asked, for `readFresh`'s reason (§E.2 item 2): the
  /// round trip is itself a side channel, and a caller who may not know a tag
  /// exists must not be able to make the plant be asked about it. What comes
  /// back instead is built from the node the caller already holds — the
  /// description and data type travelled with it in whatever list it came out
  /// of, so echoing them discloses nothing — and carries **no reading and no
  /// struct members**, which is the shape a source gives a node it has never
  /// heard of. `policy_test.dart` pins that by *comparing the two answers*
  /// rather than by restating this sentence as a literal, so a source that
  /// changes its nonexistent shape has to change both.
  @override
  Future<BrowseNodeDetail> fetchDetail(BrowseNode node) async {
    if (!_visible(node)) {
      return BrowseNodeDetail(
          description: node.description, dataType: node.dataType);
    }
    return _source.fetchDetail(node);
  }

  @override
  Future<List<BrowseNode>?> resolvePath(String targetId) async {
    final chain = await _source.resolvePath(targetId);
    if (chain == null) return null;
    // Rule 3: any hidden step, anywhere in the chain, and there is no path.
    return chain.every(_visible) ? chain : null;
  }
}

/// Historical samples, **with the hiding rule applied** (10-03).
///
/// Browse's translation problem, one step further on. These methods are keyed
/// by a **series name**, not by a plant key and not by a node id, so the
/// question `canSee` needs — which tag do these samples belong to — has to be
/// asked of [SeriesResolver] first. `resolve` is what is consulted rather than
/// `keyForTable`, and that is deliberate: it understands the
/// `<series>:<member>` grammar, so the policy is asked about the tag rather
/// than about a chart's way of selecting a column out of one.
///
/// **What comes back is used for the answer and never for the argument.**
/// [_visible] reads `plantKey` and discards the rest; every method below hands
/// the source **the caller's own name**, unrewritten. That is 10-REVIEW CR-01's
/// rule and the reason it is stated twice in this file — see [_visible] for
/// what happened when the table travelled down instead.
///
/// Three rules.
///
///  1. **A hidden series is an empty series** — never a refusal. Same
///     argument as everywhere else in this file: a refusal names what it
///     refused, and a station that can tell "hidden" from "nothing recorded"
///     can enumerate the historian by asking.
///  2. **A series the resolver cannot map at all is answered the same way,
///     and is counted.** This is the pairing 10-CONTEXT amendment 6 forces
///     and it is the one a later reader is most likely to try to "fix", so
///     both halves are stated here:
///
///      * The **wire** answer must be indistinguishable from a series that
///        does not exist, because a refusal naming an unmapped table would
///        enumerate the historian exactly as a `forbidden` would (T-10-12).
///      * The **gateway** must not be silent about it, because fail-closed
///        with nothing to read is a chart that renders flat for months while
///        nobody knows a table was never mapped.
///
///     The reconciliation is [SeriesMappingTally]: silence outward, a count
///     and a name inward. Making the refusal informative breaks the first
///     half; dropping the count breaks the second. Neither is an improvement.
///
///     The honest limit, from research §C.2: the mapping covers what the
///     *gateway* collects, so a chart pointed at a pre-cutover table the
///     application's own collector wrote gets nothing until the migration runs
///     or the configuration declares a read-side alias. That is the correct
///     default, and the first time it happens it will look like a database
///     problem (Trap 7). The count is what makes it one query instead of one
///     afternoon.
///  3. **An entry is still returned for every requested series on the
///     multiple path.** A hidden or unmappable series is an *empty* entry,
///     never an omission — an omission would be a perfect existence oracle,
///     and it would also break the rule the contract check names ("an absent
///     entry and an empty entry are different answers and only one of them is
///     true"). The gateway's handler builds the map from the request as well,
///     so this holds twice over; both belts are cheap.
///
/// Note the asymmetry with browse, and do not make the two uniform: an
/// unmappable *node* is left alone there, because a folder legitimately maps
/// to no key, while an unmappable *series* is fail-closed here, because a
/// series always names something recorded.
///
/// Written as explicit member-by-member delegation — **never `noSuchMethod`**
/// — for the reason the class doc above gives.
///
/// Under the shipped [AllVisibleOperatorWrites] with a resolver that maps
/// everything, this class is a no-op: which is why the three timeseries
/// contract checks are unchanged by it, and is the acceptance shape 06-08
/// established.
final class _PolicyTimeseries implements TimeseriesApi {
  const _PolicyTimeseries(this._source, this._resolver, this._canSee,
      this._tally);

  final TimeseriesApi _source;
  final SeriesResolver _resolver;

  /// [PolicyStateMan.canSee], passed as a function rather than as the whole
  /// decorator so this class cannot reach anything else on it.
  final bool Function(String key) _canSee;

  final SeriesMappingTally _tally;

  /// Whether this station may read [wireName]. **The name is not rewritten.**
  ///
  /// ## The decorator authorizes; it does not translate (10-REVIEW CR-01)
  ///
  /// This used to answer `resolved.table` and every method below handed that
  /// table down as the source's `tableName` argument. That was a **second**
  /// resolution across one seam: [TimescaleReader] treats its argument as a
  /// wire series name and resolves it itself
  /// (`timescale_reader.dart:585-589`), against a map keyed by plant key. With
  /// the deployed `gw_` prefix — `CollectionEntry.table` is `tablePrefix +
  /// name` and the default prefix is `'gw_'` (`collection_config.dart:148`) —
  /// the second lookup missed and *every* timeseries request over the pipe
  /// answered `UnknownSeries`, refused as INVALID_PARAMS naming a table the
  /// caller never sent. And the member was dropped in the same hand-off, so
  /// `<series>:<member>` — 10-CONTEXT ruling 2's whole feature, ninety of the
  /// live plant's 140 collected keys — could not work even with an empty
  /// prefix: the reader saw a bare name for a struct table and answered "Ask
  /// for one member" to a caller that had.
  ///
  /// The rule that replaces it, and the one to keep: **each layer hands the
  /// next the vocabulary it was given.** The wire speaks series names, the
  /// resolver is the only translator, and it is consulted once per layer for
  /// the question that layer owns — here, "may this station see the tag these
  /// samples belong to", which is a question about `plantKey` and never about
  /// the table.
  ///
  /// The two false paths are different facts and only one of them is recorded:
  /// an unmappable series is counted, a hidden one is not. Hiding is a
  /// deliberate configuration and needs no diagnostic; a missing mapping is a
  /// gap somebody has to close.
  ///
  /// A [FormatException] cannot arrive here from the wire — `DataHandlers`
  /// refuses a malformed series name before this is reached, which is the
  /// grammar belt — but it is caught rather than thrown, because an embedder
  /// holding this decorator directly is a caller too and a policy layer that
  /// threw on a bad name would turn a typo into a handler failure.
  bool _visible(String wireName) {
    final ResolvedSeries? resolved;
    try {
      resolved = _resolver.resolve(wireName);
    } on FormatException {
      _tally.record(wireName);
      return false;
    }
    if (resolved == null) {
      _tally.record(wireName);
      return false;
    }
    // The key, not the member: a policy is written about tags, and
    // `CN02.MOT01.speed:speed` is a chart selecting a column out of one.
    return _canSee(resolved.plantKey);
  }

  @override
  Future<List<TimeseriesData>> queryTimeseriesData(
      String tableName, DateTime to,
      {String? orderBy = 'time ASC', DateTime? from}) async {
    if (!_visible(tableName)) return const [];
    return _source.queryTimeseriesData(tableName, to,
        orderBy: orderBy, from: from);
  }

  /// Rule 3: one entry per requested name, keyed by **the name the caller
  /// used**.
  ///
  /// The source is asked only about the series that survive the filter, and
  /// only once each — a hidden series must not cost a round trip either, for
  /// `readFresh`'s reason (§E.2 item 2): the round trip is itself a side
  /// channel.
  ///
  /// **De-duplicated by the address, never by the table** (10-REVIEW CR-01).
  /// The previous spelling passed `visible.values.toSet()` — the resolved
  /// tables — which silently collapsed two different member addresses of one
  /// struct into a single query and then answered both with the same rows. Two
  /// members of one table are two different series on this wire; a `Set` of
  /// the *names* keeps them apart while still refusing to ask twice for a name
  /// a caller repeated.
  @override
  Future<Map<String, List<TimeseriesData>>> queryTimeseriesDataMultiple(
      List<String> tableNames, DateTime to,
      {String? orderBy = 'time ASC', DateTime? from}) async {
    final visible = <String>{
      for (final name in tableNames)
        if (_visible(name)) name,
    };
    final answers = visible.isEmpty
        ? const <String, List<TimeseriesData>>{}
        : await _source.queryTimeseriesDataMultiple(visible.toList(), to,
            orderBy: orderBy, from: from);
    return {
      for (final name in tableNames)
        name: visible.contains(name) ? answers[name] ?? const [] : const [],
    };
  }

  @override
  Future<List<TimeseriesData>> queryTimeseriesDataDownsampled(
      String tableName, DateTime from, DateTime to,
      {int maxPoints = 1000}) async {
    if (!_visible(tableName)) return const [];
    return _source.queryTimeseriesDataDownsampled(tableName, from, to,
        maxPoints: maxPoints);
  }

  @override
  Future<Map<DateTime, int>> countTimeseriesDataMultiple(
      String tableName, Duration interval, int howMany,
      {DateTime? since}) async {
    if (!_visible(tableName)) return const {};
    return _source.countTimeseriesDataMultiple(tableName, interval, howMany,
        since: since);
  }
}

/// Saved history views, **with the hiding rule applied** (10-04).
///
/// A view is a list of *plant keys*, so unlike browse and unlike timeseries
/// this one needs no resolver at all — [PolicyStateMan.canSee] takes the keys
/// as they come.
///
/// Three rules, and the third is a decision rather than a mechanism:
///
///  1. **A hidden key is dropped from a view; the view itself still comes
///     back.** A view that vanished would itself say a view exists — the
///     operator saved it and the picker offered it a moment ago, so its
///     disappearance is a louder statement about the key it held than the
///     key's own absence is (T-10-13). The arm that proves the difference is
///     the boundary one: a view **all** of whose keys are hidden comes back as
///     a view with an *empty* key list. Every other case passes under either
///     rule.
///  2. **Graphs are not filtered.** A graph index is not a key and there is
///     nothing to hide in a title or an axis unit. Filtering them alongside
///     the keys is the plausible over-reach, and it would leave a view whose
///     axes lost their labels for a reason nobody could find.
///  3. **A hidden key is dropped from a *save*, silently** — see
///     [_visibleKeys] for the cost, which is real and is written down there
///     rather than here because that is where somebody will stand.
///
/// [selectHistoryViews] delegates untouched, and that is not an omission:
/// `HistoryViewRecord` carries an id, a name and two timestamps and **no key
/// list**, so there is nothing on it to filter. The keys live behind
/// [getHistoryViewKeys] and [getHistoryViewKeyNames], which are the two
/// methods that do filter.
///
/// Written as explicit member-by-member delegation like everything else in
/// this file — **never `noSuchMethod`**: a forwarder would absorb an interface
/// member added later and serve it unfiltered.
///
/// Under the shipped [AllVisibleOperatorWrites] this whole class is a no-op,
/// which is why the two history-view contract checks are unchanged by it.
final class _PolicyHistoryViews implements HistoryViewApi {
  const _PolicyHistoryViews(this._source, this._canSee);

  final HistoryViewApi _source;

  /// [PolicyStateMan.canSee], passed as a function rather than as the whole
  /// decorator so this class cannot reach anything else on it.
  final bool Function(String key) _canSee;

  /// The keys of [keys] this station may see.
  ///
  /// ## On the way *out* this is rule 1. On the way *in* it is a decision.
  ///
  /// Dropping a hidden key from a **save** means an operator's save can
  /// quietly lose a key they cannot see: they edit a view somebody else built,
  /// press save, and a line disappears from the chart with nothing said. That
  /// is a real cost and it is the reason this paragraph exists.
  ///
  /// The alternative is to refuse the save, and it is worse in two ways.
  /// Refusing *and saying why* names the hidden key, which is the whole of
  /// what the hiding rule closes — the same disclosure a `forbidden` refusal
  /// is. Refusing *without* saying why turns an invisible key into an
  /// unexplainable failure: the operator sees a save that will not go through,
  /// on a view that looks complete to them, with no field to correct and
  /// nothing in the message to act on. A key silently absent is at least a
  /// difference they can see on the chart.
  ///
  /// Under [AllVisibleOperatorWrites] neither happens, so this is recorded for
  /// whoever ships per-key hiding rather than chosen against evidence. When
  /// that day comes, the honest third option is an *audit* one — save what was
  /// asked, log what was dropped, and tell the operator "some keys were not
  /// saved" without naming them — which needs a logging surface this gateway
  /// does not have yet.
  ///
  /// The read side has no such tension: a key already stored is dropped from
  /// the answer, and there was never anything to tell the caller.
  List<String> _visibleKeys(List<String> keys) =>
      keys.where(_canSee).toList();

  @override
  Future<int> createHistoryView(String name, List<String> keys,
      [Map<String, HistoryViewKeyRecord>? keyConfigs,
      Map<int, HistoryViewGraphRecord>? graphConfigs]) {
    final visible = _visibleKeys(keys);
    return _source.createHistoryView(
        name, visible, _visibleConfigs(keyConfigs), graphConfigs);
  }

  @override
  Future<void> updateHistoryView(int id, String name, List<String> keys,
      [Map<String, HistoryViewKeyRecord>? keyConfigs,
      Map<int, HistoryViewGraphRecord>? graphConfigs]) {
    final visible = _visibleKeys(keys);
    return _source.updateHistoryView(
        id, name, visible, _visibleConfigs(keyConfigs), graphConfigs);
  }

  /// The per-key configuration of the keys that survived [_visibleKeys].
  ///
  /// Filtered with them rather than passed through: a configuration entry
  /// carries its own key, so leaving one behind would write a hidden key's
  /// name into a row the key itself never reached.
  Map<String, HistoryViewKeyRecord>? _visibleConfigs(
      Map<String, HistoryViewKeyRecord>? configs) {
    if (configs == null) return null;
    return {
      for (final entry in configs.entries)
        if (_canSee(entry.key)) entry.key: entry.value,
    };
  }

  @override
  Future<void> deleteHistoryView(int id) => _source.deleteHistoryView(id);

  /// Delegates. See the class doc: there are no keys on a
  /// [HistoryViewRecord] to filter, and the view itself is never hidden.
  @override
  Future<List<HistoryViewRecord>> selectHistoryViews() =>
      _source.selectHistoryViews();

  @override
  Future<Map<String, HistoryViewKeyRecord>> getHistoryViewKeys(
      int viewId) async {
    final keys = await _source.getHistoryViewKeys(viewId);
    return {
      for (final entry in keys.entries)
        if (_canSee(entry.key)) entry.key: entry.value,
    };
  }

  /// Delegates. Rule 2: a graph index is not a key.
  @override
  Future<Map<int, HistoryViewGraphRecord>> getHistoryViewGraphs(int viewId) =>
      _source.getHistoryViewGraphs(viewId);

  /// The same filter as [getHistoryViewKeys], because the two are two reads of
  /// one row set and a caller picks whichever it needs. One fitted and the
  /// other forgotten would hide a key from the legend and hand it to the
  /// chart.
  @override
  Future<List<String>> getHistoryViewKeyNames(int viewId) async =>
      _visibleKeys(await _source.getHistoryViewKeyNames(viewId));

  @override
  Future<int> addHistoryViewPeriod(
          int viewId, String name, DateTime start, DateTime end) =>
      _source.addHistoryViewPeriod(viewId, name, start, end);

  @override
  Future<void> deleteHistoryViewPeriod(int id) =>
      _source.deleteHistoryViewPeriod(id);

  @override
  Future<List<HistoryViewPeriodRecord>> listHistoryViewPeriods(int viewId) =>
      _source.listHistoryViewPeriods(viewId);

  @override
  Future<DateTime?> getGlobalRetentionHorizon() =>
      _source.getGlobalRetentionHorizon();
}

/// Stored preferences: **anyone authenticated may read them, and writing one
/// takes the same role writing a motor setpoint takes** (10-05, 10-CONTEXT
/// ruling 1).
///
/// The least obvious of the four seams, because a preference key is not a
/// plant key: `svn.chart.maxPoints` names a row in the gateway's own settings
/// store, and [KeyPolicy] — which answers about tags — has nothing to say about
/// it. So the question this class had to settle was not *which* preferences a
/// station may touch but whether preferences are policed by identity at all.
///
/// ## Why `operate`, and why that is not a new rule
///
/// **`key_mappings`.** That one preference row is the gateway's own routing
/// configuration — 518 KiB of it — and a station that can `setString` it
/// re-points the plant's tag map for every panel on the site. A `view` station
/// doing that is at least as consequential as a `view` station writing a motor
/// setpoint, which is precisely what `operate` already guards. So the rule
/// reused here is [AllVisibleOperatorWrites]'s own, verbatim: everything is
/// readable, and the `operate` role is what a write takes. The comparison
/// below is the only one in this file — one rule, not seven copies of it.
///
/// **No new rule shape**, and that is a deliberate scope fence rather than
/// laziness. A `canWritePreference(String key, Identity)` on [KeyPolicy] would
/// be a second policy surface to keep in step with the first, for behaviour
/// nobody has asked for and no policy data exists to fill; tightening this
/// later — a per-key preference rule, a read rule — stays a change to policy
/// *data* rather than to plumbing, which is the whole point of the Phase 6
/// hiding architecture. The `operate` gate is the safe floor either way.
///
/// ## The refusal is `forbidden`, and here that is the *correct* answer
///
/// Everywhere else in this file a refusal that names what it refused is the
/// leak being closed: answer `forbidden` for a hidden tag and a station can
/// enumerate the plant by asking. Preferences invert that, because **reads are
/// all-visible**. A station that is refused a write has already read the key,
/// or could have; there is no existence left to conceal, and the two facts a
/// client acts on differently are "fix the key name" (`unknownKey`) and
/// "obtain the permission" (`forbidden`). This is the second, and it is the one
/// place in Phase 10 where saying so out loud is right.
///
/// The refusal is also **pre-effect**: raised before the source is touched, in
/// the same shape `value_handlers.dart:445-455` raises it for a plant write —
/// `ServerErrorCodes.forbidden` with a pre-substituted `data`, never
/// `RpcException.invalidParams`, because a refusal with no `data` is the one
/// `serialize` fills in with the offending request (the 02-05 hang). A gate
/// that fired after the write had landed would not be a gate; for
/// `key_mappings` it would be a report that the tag map has already moved.
///
/// ## Secret material is impossible by construction, and not because of this
///
/// Worth stating at the gate, because the two are easy to conflate and the
/// mistake is one-directional. This class is about `key_mappings`. It is **not**
/// what keeps credentials off the pipe: `PreferencesApi` simply omits the
/// `{bool secret = false}` parameter the concrete `Preferences` carries at
/// twelve sites, so there is no route from this wire to the secure store at
/// all, and `api_surface_test.dart` fails if any wire interface ever declares a
/// parameter with that name (SEC-01, T-10-18). A reader who reads this gate as
/// "secrets are handled" will eventually restore the parameter behind it.
///
/// Ruling 1 is **resolved**, not open: the user's 2026-09-02 morning review
/// kept `key_mappings` wire-writable behind this gate, on the argument that the
/// audit trail is what makes a gated configuration write defensible, and closed
/// the off-wire option.
///
/// Written as explicit member-by-member delegation like everything else in this
/// file — **never `noSuchMethod`**: a forwarder would absorb a mutator added to
/// the interface later and serve it ungated, which is this class's whole job.
///
/// Under the shipped `PermissiveTokenValidator`, which mints `operate` for
/// every station it accepts, this class is a no-op — which is why both
/// preference contract checks pass through it unchanged, and is the acceptance
/// shape 06-08 established.
final class _PolicyPreferences implements PreferencesApi {
  const _PolicyPreferences(this._source, this._identityOf);

  final PreferencesApi _source;

  /// [PolicyStateMan.identityOf], passed as a function rather than as the whole
  /// decorator so this class cannot reach anything else on it.
  ///
  /// The identity itself rather than a `canWrite`-shaped predicate, because
  /// there is no key to ask about: the comparison below **is** the rule, and it
  /// is made once so there are not seven copies of it to keep in step.
  final Identity? Function() _identityOf;

  /// Refuses [method] unless the asking station may actuate.
  ///
  /// Null identity is refused too, by the same `identity != null` rule
  /// [PolicyStateMan.canSee] and [PolicyStateMan.canWrite] answer by: a session
  /// between `serve` and `hello` has no station for the policy to answer about,
  /// and null means "nothing", not "everything". The state is unreachable from
  /// the wire — the handshake gate refuses every method before `hello` — but
  /// that is a property of today's gate rather than of this class.
  void _requireOperate(String method, String what) {
    final identity = _identityOf();
    if (identity != null && identity.role == Role.operate) return;
    throw rpc.RpcException(
        ServerErrorCodes.forbidden,
        'this station may read preferences but may not write them, so '
        '"$method" was refused. $what: the preference store was not touched, '
        'so this call definitively had no effect. Do not retry — the session '
        'is fine and reading continues; what is missing is a permission, and '
        'permissions change in the gateway\'s token file rather than on the '
        'next attempt',
        data: _substitute(method));
  }

  /// A refusal's `data`, pre-substituted.
  ///
  /// Copied from `value_handlers.dart` and `data_handlers.dart` rather than
  /// shared, for the reason those two carry: `RpcException.serialize` fills an
  /// empty `data` with the offending **request**, and one request carrying
  /// `1e999` then makes the error itself unencodable — at which point the peer
  /// drops it and a caller with no deadline waits forever.
  static Map<String, Object?> _substitute(String method) => {
        'method': method,
        'request': 'omitted: echoing a request that may carry a non-finite '
            'number is what makes the error itself unencodable, and an '
            'unencodable error on a path with no deadline is a hang',
      };

  @override
  Future<Set<String>> getKeys({Set<String>? allowList}) =>
      _source.getKeys(allowList: allowList);

  @override
  Future<Map<String, Object?>> getAll({Set<String>? allowList}) =>
      _source.getAll(allowList: allowList);

  @override
  Future<bool?> getBool(String key) => _source.getBool(key);

  @override
  Future<int?> getInt(String key) => _source.getInt(key);

  @override
  Future<double?> getDouble(String key) => _source.getDouble(key);

  @override
  Future<String?> getString(String key) => _source.getString(key);

  @override
  Future<List<String>?> getStringList(String key) =>
      _source.getStringList(key);

  @override
  Future<bool> containsKey(String key) => _source.containsKey(key);

  // The seven mutators. Each states the gate on its own line, above the
  // delegation, so a reader adding an eighth sees what the other seven do.

  @override
  Future<void> setBool(String key, bool value) {
    _requireOperate('preferences.setBool', 'nothing was stored under "$key"');
    return _source.setBool(key, value);
  }

  @override
  Future<void> setInt(String key, int value) {
    _requireOperate('preferences.setInt', 'nothing was stored under "$key"');
    return _source.setInt(key, value);
  }

  @override
  Future<void> setDouble(String key, double value) {
    _requireOperate('preferences.setDouble', 'nothing was stored under "$key"');
    return _source.setDouble(key, value);
  }

  @override
  Future<void> setString(String key, String value) {
    // The one this ruling is about: `key_mappings` is a string, and it is the
    // gateway's own routing configuration.
    _requireOperate('preferences.setString', 'nothing was stored under "$key"');
    return _source.setString(key, value);
  }

  @override
  Future<void> setStringList(String key, List<String> value) {
    _requireOperate(
        'preferences.setStringList', 'nothing was stored under "$key"');
    return _source.setStringList(key, value);
  }

  @override
  Future<void> remove(String key) {
    _requireOperate('preferences.remove', '"$key" is still stored');
    return _source.remove(key);
  }

  @override
  Future<void> clear({Set<String>? allowList}) {
    // Gated like the setters and not more loudly, though it is the widest of
    // the seven: `clear()` with no allow-list removes every preference this
    // gateway holds, `key_mappings` among them.
    _requireOperate('preferences.clear', 'nothing was removed');
    return _source.clear(allowList: allowList);
  }

  @override
  Stream<String> get onPreferencesChanged => _source.onPreferencesChanged;
}
