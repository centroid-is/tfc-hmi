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
/// ## The four sub-APIs: one filters, three are still transparent
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
/// **10-02 registered the four `browse.*` handlers, so browse now filters**
/// and has cases that can see it (`policy_test.dart`'s browse group, and
/// browse as the seventh entry in the indistinguishability loop). The other
/// three still delegate, each saying so at its own declaration, and the plans
/// that make their methods reachable are the plans that fill them in: 10-03
/// for timeseries, 10-04 for history views, 10-05 for preferences. The rule
/// stands unchanged — a filter lands in the commit that makes the surface
/// reachable, never before it and never after.
library;

import 'package:tfc_relay_protocol/tfc_relay_protocol.dart';

import '../auth/identity.dart';
import 'key_policy.dart';

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
  /// The browse filter needs it and nothing else in this class does yet:
  /// `keys` is already a list of plant keys, so the five surfaces that inherit
  /// hiding from it never had a translation problem. Browse walks the upstream
  /// address space instead, where every identifier belongs to the server that
  /// published it, and 10-03 and 10-04 will need the same object for tables.
  ///
  /// Required, no default. See `relay_server.dart`'s `resolver` parameter.
  final SeriesResolver resolver;

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
  TimeseriesApi get timeseries => _PolicyTimeseries(source.timeseries);

  @override
  HistoryViewApi get historyViews => _PolicyHistoryViews(source.historyViews);

  @override
  PreferencesApi get preferences => _PolicyPreferences(source.preferences);

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
// The four sub-APIs. Browse filters as of 10-02; the other three are still
// wrapped and delegating, and say so at their own declarations. See the
// library doc for why each of those words is deliberate.
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

/// Historical samples. **Still transparent — 10-03 owns the filter**, and this
/// class hides nothing today: it delegates every member and says so here so
/// the file never claims coverage it does not have.
///
/// The decision browse needed is already made — [SeriesResolver] is on
/// [PolicyStateMan] and 10-02 threaded it — but the translation is a different
/// one: these methods are keyed by `tableName`, not by node id, so what 10-03
/// consults is `keyForTable`, and 10-CONTEXT amendment 6 makes an unmappable
/// table **fail-closed**: not served until mapped. That is the opposite of
/// browse's rule for an unmappable *node*, where a folder legitimately maps to
/// nothing, and the two must not be made uniform by whoever writes the second
/// one.
final class _PolicyTimeseries implements TimeseriesApi {
  const _PolicyTimeseries(this._source);

  final TimeseriesApi _source;

  @override
  Future<List<TimeseriesData>> queryTimeseriesData(
          String tableName, DateTime to,
          {String? orderBy = 'time ASC', DateTime? from}) =>
      _source.queryTimeseriesData(tableName, to, orderBy: orderBy, from: from);

  @override
  Future<Map<String, List<TimeseriesData>>> queryTimeseriesDataMultiple(
          List<String> tableNames, DateTime to,
          {String? orderBy = 'time ASC', DateTime? from}) =>
      _source.queryTimeseriesDataMultiple(tableNames, to,
          orderBy: orderBy, from: from);

  @override
  Future<List<TimeseriesData>> queryTimeseriesDataDownsampled(
          String tableName, DateTime from, DateTime to,
          {int maxPoints = 1000}) =>
      _source.queryTimeseriesDataDownsampled(tableName, from, to,
          maxPoints: maxPoints);

  @override
  Future<Map<DateTime, int>> countTimeseriesDataMultiple(
          String tableName, Duration interval, int howMany,
          {DateTime? since}) =>
      _source.countTimeseriesDataMultiple(tableName, interval, howMany,
          since: since);
}

/// Saved history views. **Still transparent — 10-04 owns the filter**, and
/// this class hides nothing today.
///
/// A view is a list of *plant keys*, so unlike browse and unlike timeseries
/// this one needs no resolver at all — [PolicyStateMan.canSee] takes the keys
/// as they come. The rule when it lands: a view holding a hidden key comes
/// back **without that key** rather than not at all, because a view that
/// vanished would itself say a view exists.
final class _PolicyHistoryViews implements HistoryViewApi {
  const _PolicyHistoryViews(this._source);

  final HistoryViewApi _source;

  @override
  Future<int> createHistoryView(String name, List<String> keys,
          [Map<String, HistoryViewKeyRecord>? keyConfigs,
          Map<int, HistoryViewGraphRecord>? graphConfigs]) =>
      _source.createHistoryView(name, keys, keyConfigs, graphConfigs);

  @override
  Future<void> updateHistoryView(int id, String name, List<String> keys,
          [Map<String, HistoryViewKeyRecord>? keyConfigs,
          Map<int, HistoryViewGraphRecord>? graphConfigs]) =>
      _source.updateHistoryView(id, name, keys, keyConfigs, graphConfigs);

  @override
  Future<void> deleteHistoryView(int id) => _source.deleteHistoryView(id);

  @override
  Future<List<HistoryViewRecord>> selectHistoryViews() =>
      _source.selectHistoryViews();

  @override
  Future<Map<String, HistoryViewKeyRecord>> getHistoryViewKeys(int viewId) =>
      _source.getHistoryViewKeys(viewId);

  @override
  Future<Map<int, HistoryViewGraphRecord>> getHistoryViewGraphs(int viewId) =>
      _source.getHistoryViewGraphs(viewId);

  @override
  Future<List<String>> getHistoryViewKeyNames(int viewId) =>
      _source.getHistoryViewKeyNames(viewId);

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

/// Stored preferences. **The filter point for Phase 10** is here, and it is
/// the least obvious of the four: preference keys are not plant keys, so
/// [KeyPolicy] as it stands has nothing to say about them. Whoever wires this
/// decides whether preferences are policed by identity at all — and
/// `preferences_api.dart` is where the SEC-01 argument about secret material
/// already lives.
final class _PolicyPreferences implements PreferencesApi {
  const _PolicyPreferences(this._source);

  final PreferencesApi _source;

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

  @override
  Future<void> setBool(String key, bool value) => _source.setBool(key, value);

  @override
  Future<void> setInt(String key, int value) => _source.setInt(key, value);

  @override
  Future<void> setDouble(String key, double value) =>
      _source.setDouble(key, value);

  @override
  Future<void> setString(String key, String value) =>
      _source.setString(key, value);

  @override
  Future<void> setStringList(String key, List<String> value) =>
      _source.setStringList(key, value);

  @override
  Future<void> remove(String key) => _source.remove(key);

  @override
  Future<void> clear({Set<String>? allowList}) =>
      _source.clear(allowList: allowList);

  @override
  Stream<String> get onPreferencesChanged => _source.onPreferencesChanged;
}
