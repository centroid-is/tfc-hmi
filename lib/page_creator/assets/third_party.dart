import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;
import 'package:tfc/converter/color_converter.dart';

import '../../providers/state_man.dart';
import '../../widgets/panes/color_picker_dialog.dart';
import '../../widgets/panes/pane_chrome.dart';
import '../../widgets/panes/side_pane.dart';
import 'package:tfc/widgets/number_slider.dart';
import 'common.dart';
import 'conveyor.dart' show ConveyorConfig;
import 'led.dart' show LEDPainter, LEDType;
import 'graph.dart' show GraphAssetConfig;
import 'number.dart' show NumberConfig, NumberWidget, showNumberGraphDialog;
import 'ratio_number.dart'
    show
        RatioNumberConfig,
        RatioNumberWidget,
        ratioIntervalChips,
        showRatioAnalysisDialog;
import 'registry.dart';
import 'sensor.dart' show SensorConfig;
import 'third_party_painter.dart';

part 'third_party.g.dart';

/// The piece of third-party equipment this asset stands for.
///
/// Drives painter dispatch — one simplified top view per kind. Adding a value
/// here is a compile error in `_createPainter` until a painter is wired up,
/// which is deliberate.
@JsonEnum()
enum ThirdPartyEquipmentKind {
  multivac,
  speedBatcher,

  /// TODO(product-name): the make/model of the box erector on the line has not
  /// been identified yet. Rename this value (and its label + painter) once it
  /// is — every other kind is named after its manufacturer.
  boxErector,

  strappingLine,

  /// The vodlari — Icelandic for the fish aligning buffer. Stored under an
  /// English-ish identifier because the persisted JSON should not depend on
  /// non-ASCII. It is still called the vodlari on the plant floor, but the
  /// operator-facing label reads "Batch aligner"; the floor name survives as a
  /// search keyword on [ThirdPartyEquipmentConfig.searchKeywords].
  fishAligner,
}

/// Operator-facing metadata for each kind. Kept out of the enum so the
/// persisted JSON stays a stable identifier while the display text can change
/// freely.
extension ThirdPartyEquipmentKindInfo on ThirdPartyEquipmentKind {
  /// Name shown in the kind dropdown and as the details-dialog title.
  String get label {
    switch (this) {
      case ThirdPartyEquipmentKind.multivac:
        return 'Multivac thermoformer';
      case ThirdPartyEquipmentKind.speedBatcher:
        return 'Marel SpeedBatcher';
      case ThirdPartyEquipmentKind.boxErector:
        return 'Box erector';
      case ThirdPartyEquipmentKind.strappingLine:
        return 'Afak / Strapex strapping line';
      case ThirdPartyEquipmentKind.fishAligner:
        return 'Batch aligner';
    }
  }

  /// Label including the model variant, where the head count picks a real
  /// model number. Used for the side-pane title.
  String labelFor({int strapMachines = 3}) =>
      this == ThirdPartyEquipmentKind.strappingLine
          ? 'Strapping line — ${strapMachines.clamp(1, 3)} x Strapex'
          : label;

  /// Real machine footprint, shown in the side pane. See the source notes at
  /// the top of `third_party_painter.dart` for where each figure comes from.
  ///
  /// [strapMachines] only affects the strapping line.
  String footprint({int strapMachines = 3}) {
    switch (this) {
      case ThirdPartyEquipmentKind.multivac:
        return '~5437 x 1002 mm (R 245)';
      case ThirdPartyEquipmentKind.speedBatcher:
        return 'station layout — per site sketch';
      case ThirdPartyEquipmentKind.boxErector:
        return 'tall and narrow — per site CAD';
      case ThirdPartyEquipmentKind.fishAligner:
        return 'near square — per site CAD';
      case ThirdPartyEquipmentKind.strappingLine:
        // Only the 3-strapper line length is published. A shorter line is the
        // same line with strappers removed, so its length is estimated at one
        // strapper pitch each and labelled as such rather than quoted as
        // fact.
        if (strapMachines >= 3) return '~2665 x 1815 mm (3 strappers)';
        final estimated = 2665 - (3 - strapMachines) * 640;
        return '~$estimated x 1815 mm '
            '($strapMachines strappers, length estimated)';
    }
  }

  /// Aspect ratio of the drawing as authored — **width divided by height**,
  /// matching the real machine's plan proportions.
  ///
  /// Note the SpeedBatcher is the odd one out at under 1.0: it is drawn
  /// PORTRAIT, because product runs up the page through it rather than left
  /// to right.
  ///
  /// Sizing an asset well away from its kind's ratio squashes the layout — the
  /// Multivac especially, at 5.4:1. Used for the editor preview.
  double aspectRatio({int strapMachines = 3}) {
    switch (this) {
      case ThirdPartyEquipmentKind.multivac:
        return 5437 / 1002;
      case ThirdPartyEquipmentKind.speedBatcher:
        // From the site sketch: roughly twice as long as it is wide, running
        // up the page.
        return 0.53;
      case ThirdPartyEquipmentKind.boxErector:
        // Portrait, and markedly so — the site CAD shows a long narrow
        // machine with the blank magazine running most of its length.
        return 0.35;
      case ThirdPartyEquipmentKind.strappingLine:
        return (2665 - (3 - strapMachines.clamp(1, 3)) * 640) / 1815;
      case ThirdPartyEquipmentKind.fishAligner:
        // Close to square in the site CAD.
        return 0.93;
    }
  }

  /// Whether the head-count control applies to this kind.
  bool get hasStrapMachines => this == ThirdPartyEquipmentKind.strappingLine;
}

// ---------------------------------------------------------------------------
// Child assets inside the box
// ---------------------------------------------------------------------------

/// Deserialise a polymorphic child asset for a [ThirdPartyChildEntry].
///
/// Same envelope trick as `elevator.dart:_childFromJson` — wrapping the child
/// JSON in a single-key Map makes [AssetRegistry.parse]'s tree crawl find
/// exactly one asset without bare-Map ambiguity, and any registered asset type
/// works without a switch here.
///
/// FAIL-LOUD: an unregistered `asset_name` throws rather than silently
/// dropping the child, so a saved page cannot quietly lose the conveyor an
/// operator relies on.
BaseAsset _childFromJson(Map<String, dynamic> json) {
  final assets = AssetRegistry.parse(<String, dynamic>{'wrapped_child': json});
  if (assets.isEmpty) {
    throw FormatException(
      'ThirdPartyChildEntry.child JSON did not match any registered '
      'asset_name in AssetRegistry: ${json[constAssetName]}',
    );
  }
  return assets.first as BaseAsset;
}

Map<String, dynamic> _childToJson(BaseAsset child) => child.toJson();

List<ThirdPartyChildEntry> _childrenFromJson(List<dynamic>? json) {
  if (json == null) return <ThirdPartyChildEntry>[];
  return json
      .map(
          (item) => ThirdPartyChildEntry.fromJson(item as Map<String, dynamic>))
      .toList();
}

List<Map<String, dynamic>> _childrenToJson(List<ThirdPartyChildEntry> list) =>
    list.map((e) => e.toJson()).toList();

/// Monotonic suffix for entry ids. Windows clock resolution (~15 ms) can make
/// back-to-back `DateTime.now()` calls return the same microseconds; the
/// suffix guarantees uniqueness regardless. Mirrors `elevator.dart`.
int _nextThirdPartyChildIdSuffix = 0;

/// A live asset placed inside the dotted box.
///
/// The point is that the parts of a third-party machine we CAN see — a
/// conveyor whose drive frequency we read, a sensor on the infeed — get their
/// real assets rather than a painted approximation. Drop a `ConveyorConfig`
/// onto the SpeedBatcher's infeed lane and it animates from the actual
/// frequency while the surrounding station stays a drawing.
///
/// Positions are fractions of the machine area (the rect the plan view is
/// drawn into), NOT of the whole asset rect — so a child stays on its lane
/// when the LED header changes height.
@JsonSerializable(explicitToJson: true)
class ThirdPartyChildEntry {
  /// Stable identity, used as a `ValueKey` so the child keeps its State (and
  /// its subscription) when the list is reordered.
  String id;

  /// Centre X within the machine area: 0.0 = left edge, 1.0 = right edge.
  double offsetX;

  /// Centre Y within the machine area: 0.0 = top edge, 1.0 = bottom edge.
  double offsetY;

  /// Keep this child level on screen no matter how the parent is rotated.
  ///
  /// Readouts want this — a weight you have to tilt your head to read is
  /// useless, and the machine gets rotated to match the plant layout, not to
  /// suit the numbers. Machinery (conveyors, sensors) wants the opposite: it
  /// must turn with the machine it belongs to.
  @JsonKey(defaultValue: false)
  bool keepUpright;

  /// Polymorphic child asset. Its own `size` is resolved against the machine
  /// area rather than the screen, so it scales with the parent.
  @JsonKey(fromJson: _childFromJson, toJson: _childToJson)
  BaseAsset child;

  ThirdPartyChildEntry({
    String? id,
    this.offsetX = 0.5,
    this.offsetY = 0.5,
    this.keepUpright = false,
    required this.child,
  }) : id = id ??
            '${DateTime.now().microsecondsSinceEpoch}-'
                '${_nextThirdPartyChildIdSuffix++}';

  factory ThirdPartyChildEntry.fromJson(Map<String, dynamic> json) =>
      _$ThirdPartyChildEntryFromJson(json);

  Map<String, dynamic> toJson() => _$ThirdPartyChildEntryToJson(this);
}

/// A piece of equipment we do NOT control, shown on the line overview so the
/// operator can see the handshake between our PLC and the neighbouring
/// machine.
///
/// Renders a simplified top view of the selected machine inside a dotted
/// boundary box — the dotted line is the visual convention for "outside our
/// scope of supply". One LED in the top-left corner reports run status; tap
/// anywhere in the box for the details dialog.
///
/// Scope note: run status is the only live signal on the MIMIC. The
/// SpeedBatcher additionally reads its `p_stat_*` handshake struct via
/// [statusKey], surfaced as diodes in the side pane — richer state stays off
/// the drawing so the box reads the same across kinds.
@JsonSerializable(explicitToJson: true)
class ThirdPartyEquipmentConfig extends BaseAsset {
  @override
  String get displayName => '3rd Party Equipment';

  @override
  String get category => 'Third Party';

  /// Every kind's label, so searching for the machine on the floor —
  /// "multivac", "speedbatcher", "afak" — surfaces this tile even though the
  /// palette shows the umbrella name. "vodlari" is listed on top of the labels
  /// because the batch aligner's label no longer carries its floor name, and
  /// the floor name is what an operator will type.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  List<String> get searchKeywords => [
        for (final kind in ThirdPartyEquipmentKind.values) kind.label,
        'vodlari',
      ];

  /// Which machine this asset represents.
  @JsonKey(unknownEnumValue: ThirdPartyEquipmentKind.multivac)
  ThirdPartyEquipmentKind kind;

  /// State key carrying the machine's run status as a bool.
  ///
  /// Empty key, no value yet, or a stream error all render the LED grey with
  /// the `!` glyph (`LEDPainter`'s unknown state) rather than claiming the
  /// machine is stopped.
  String runKey;

  /// When true the visual run state is the inverse of the raw bool — for
  /// equipment that hands us a "stopped" contact rather than a "running" one.
  bool invertRunPolarity;

  /// Struct node carrying the SpeedBatcher's `p_stat_*` handshake bits
  /// (e.g. `SB1` mapping to `SPB01.speedBatcher.hmi`). Drives the diodes in
  /// the side pane's Status section.
  ///
  /// For every other kind this is a key PREFIX rather than a struct node:
  /// `BER02`, `STM02`, `SPB02.multivac`, `SPB02.Aligner`. The pane appends the
  /// suffixes in [kEquipmentStatusBits] to it.
  /// A bit the PLC does not expose renders as the unknown LED rather than
  /// claiming "off".
  String statusKey;

  /// LED colour while the machine is running.
  @ColorConverter()
  Color runningColor;

  /// LED colour while the machine is stopped.
  @ColorConverter()
  Color stoppedColor;

  /// Outline colour of the machine drawing. The dotted boundary uses the same
  /// colour at reduced opacity.
  @ColorConverter()
  Color outlineColor;

  /// Outline stroke width in logical pixels.
  double strokeWidth;

  /// Optional human-readable label (e.g. `"MV-01"`).
  String? tag;

  /// Paint [tag] on the page next to the drawing.
  ///
  /// Off by default: `AssetStack` scales the label font with the asset's
  /// bounding box, and these machines are big, so the tag comes out huge on
  /// the mimic. The side pane titles itself with the tag either way, so
  /// nothing is lost by leaving this off.
  @JsonKey(defaultValue: false)
  bool showTag;

  /// Free-text notes surfaced in the side pane — supplier contact, line
  /// position, interlock quirks, whatever the operator needs at 03:00.
  String? notes;

  /// Strapex arches on the strapping line — the `-N` in SL-15-N. Ignored by
  /// the other kinds.
  int strapMachines;

  /// Live assets placed inside the dotted box (conveyors driven by real drive
  /// frequencies, sensors, readouts, and so on).
  @JsonKey(fromJson: _childrenFromJson, toJson: _childrenToJson)
  List<ThirdPartyChildEntry> children;

  /// Extra rotation, in degrees, for every child marked
  /// [ThirdPartyChildEntry.keepUpright].
  ///
  /// One angle for the lot, because the readouts inside a machine are always
  /// read from the same place. Zero — the default — means level on screen
  /// whatever `coordinates.angle` the machine is placed at: the parent's
  /// rotation is cancelled out first, then this is applied on top. Use it to
  /// tilt the whole set when the operator reads the panel from an angle.
  double childTextAngle;

  /// Averaging window, in minutes, behind the accept-rate readout.
  ///
  /// The accept rate is a rolling figure, not an instant one, and a bare
  /// percentage invites being read as "right now". The scaffold folds this
  /// number into the readout's units — `% / 30 min` — so the window travels
  /// with the value instead of living in someone's head.
  int acceptWindowMinutes;

  /// Whether the accept/reject chart's bars sit on clock boundaries.
  ///
  /// True — the default — buckets a 10-minute interval at :00, :10, :20 and so
  /// on, which is how the figure gets compared against a shift clock or a
  /// production log. False buckets backwards from "now", so every refresh
  /// slides the bars and two operators looking at the same chart a minute
  /// apart are reading different windows.
  ///
  /// Lives on the station rather than on each readout because it is applied to
  /// both of them on load: the two checkweighers must bucket alike or their
  /// accept rates cannot be read side by side.
  @JsonKey(defaultValue: true)
  bool acceptBarsClockAligned;

  /// `Asset.text` is what `AssetStack` (in `lib/pages/page_view.dart`) reads to
  /// paint the label OUTSIDE the asset's rotated subtree. Aliasing `text` onto
  /// `tag` — the same trick `SensorConfig` uses — keeps the label upright
  /// regardless of `Coordinates.angle`.
  ///
  /// Gated on [showTag]: with it off, `AssetStack` sees no label and paints
  /// nothing. [tag] itself is untouched — it still names the pane and is
  /// persisted under its own JSON key.
  @override
  String? get text => showTag ? tag : null;

  /// Non-null writes only. The generated `fromJson` assigns `..text =` AFTER
  /// the constructor has set `tag`; adopting a null `text` from a legacy page
  /// would wipe a perfectly good tag. Mirrors `SensorConfig.text`.
  @override
  set text(String? value) {
    if (value != null) tag = value;
  }

  ThirdPartyEquipmentConfig({
    this.kind = ThirdPartyEquipmentKind.multivac,
    this.runKey = '',
    this.invertRunPolarity = false,
    this.statusKey = '',
    Color? runningColor,
    Color? stoppedColor,
    Color? outlineColor,
    this.strokeWidth = 2.0,
    this.tag,
    this.showTag = false,
    this.notes,
    this.strapMachines = 3,
    this.childTextAngle = 0.0,
    this.acceptWindowMinutes = 30,
    this.acceptBarsClockAligned = true,
    List<ThirdPartyChildEntry>? children,
  })  : children =
            children != null ? List<ThirdPartyChildEntry>.of(children) : [],
        runningColor = runningColor ?? Colors.green,
        // Grey, not red: stopped is a normal state on this line, and red is
        // reserved for something actually being wrong. The unknown state stays
        // tellable from stopped by the `!` glyph LEDPainter adds.
        stoppedColor = stoppedColor ?? Colors.grey,
        outlineColor = outlineColor ?? Colors.blueGrey {
    textPos = TextPos.below;
    // These machines are wide; the BaseAsset 3%×3% default would squash the
    // top view into an unreadable stamp. `fromJson` assigns `..size` after the
    // constructor, so persisted sizes still win.
    size = const RelativeSize(width: 0.16, height: 0.10);
  }

  /// Palette preview. Multivac by default, so no children are built — a
  /// SpeedBatcher picked from the dropdown gets its station scaffolded there.
  ThirdPartyEquipmentConfig.preview() : this();

  /// A SpeedBatcher complete with its two conveyors and their readouts.
  ///
  /// The station is only meaningful with them: each checkweigher IS a
  /// conveyor, and the weight and accept rate are why it is on the mimic at
  /// all. Keys start empty for the operator to fill in.
  factory ThirdPartyEquipmentConfig.speedBatcherStation({
    int acceptWindowMinutes = 30,
    bool acceptBarsClockAligned = true,
  }) {
    final config = ThirdPartyEquipmentConfig(
      kind: ThirdPartyEquipmentKind.speedBatcher,
      acceptWindowMinutes: acceptWindowMinutes,
      acceptBarsClockAligned: acceptBarsClockAligned,
    );
    config.children.addAll(buildSpeedBatcherStationChildren(
      acceptWindowMinutes: acceptWindowMinutes,
      acceptBarsClockAligned: acceptBarsClockAligned,
    ));
    return config;
  }

  factory ThirdPartyEquipmentConfig.fromJson(Map<String, dynamic> json) =>
      _$ThirdPartyEquipmentConfigFromJson(json)..applyAcceptReadoutSettings();

  /// Pushes the station's accept-rate settings down onto its readouts.
  ///
  /// Stations placed before the presets fix persisted the RatioNumber default
  /// ([1, 5, 10, 60, 240]), which does not contain 30 — so the chart opened on
  /// a window none of its toggles could show. Repaired on load rather than by
  /// a migration script: the parent owns these children, and "the window the
  /// figure is quoted over is offerable" is an invariant of the station, not a
  /// one-off data fix. Only ADDS the window; a preset list someone widened by
  /// hand is left alone otherwise.
  ///
  /// [acceptBarsClockAligned] is pushed down the same way, which is why it is
  /// a station setting: editing it on one checkweigher's readout would be
  /// overwritten here on the next load, and the two must match anyway.
  void applyAcceptReadoutSettings() {
    for (final entry in children) {
      final child = entry.child;
      if (child is! RatioNumberConfig) continue;
      child.barsClockAligned = acceptBarsClockAligned;
      // Not a station setting: a count is a whole number on every machine.
      child.integersOnly = true;
      if (acceptWindowMinutes <= 0) continue;
      if (child.intervalPresets.contains(acceptWindowMinutes)) continue;
      child.intervalPresets = [...child.intervalPresets, acceptWindowMinutes]
        ..sort();
    }
  }

  @override
  Map<String, dynamic> toJson() => _$ThirdPartyEquipmentConfigToJson(this);

  /// Own run key plus every key reachable through the children.
  ///
  /// `BaseAsset.allKeys` introspects `toJson()` and would only see the nested
  /// children as opaque maps, so a conveyor placed inside the box would be
  /// invisible to key discovery. Insertion order is preserved: parent first,
  /// then children in declaration order.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  List<String> get allKeys => <String>{
        ...super.allKeys,
        if (statusKey.isNotEmpty)
          for (final bit in kEquipmentStatusBits[kind] ?? const [])
            '$statusKey.${bit.suffix}',
        for (final key in children.expand((e) => e.child.allKeys)) key,
      }.toList();

  @override
  Widget build(BuildContext context) => ThirdPartyEquipment(config: this);

  @override
  Widget configure(BuildContext context) =>
      _ThirdPartyEquipmentConfigEditor(config: this);
}

/// Apply polarity inversion to a raw run bool.
///
/// `isRunning = invertRunPolarity ? !rawBool : rawBool`. Mirrors
/// `sensorIsActive` in `sensor.dart`.
bool thirdPartyIsRunning({
  required bool rawBool,
  required bool invertRunPolarity,
}) {
  return invertRunPolarity ? !rawBool : rawBool;
}

// ---------------------------------------------------------------------------
// SpeedBatcher status diodes
// ---------------------------------------------------------------------------

/// One diode of the SpeedBatcher handshake: which struct member feeds it and
/// how it is presented.
class SpeedBatcherStatusBit {
  /// Member name inside the [ThirdPartyEquipmentConfig.statusKey] struct.
  final String member;

  /// Operator-facing label beside the diode.
  final String label;

  /// Diode colour when the bit is true. Off is white, unknown is the grey `!`.
  final Color onColor;

  const SpeedBatcherStatusBit(this.member, this.label, this.onColor);
}

/// The five handshake bits, in display order. Same members and colours as the
/// retired flat SpeedBatcher asset (`speedbatcher.dart`); two labels reworded
/// to match the other machines' panes -- "Drop Ok from PLC" was the
/// engineer's phrase for the same bit the Multivac pane calls "ready for
/// fish", and "Dropped Batch" sat beside "Batch ready" as a dangling fragment.
/// Blue for Cleaning, green for the rest.
const List<SpeedBatcherStatusBit> speedBatcherStatusBits = [
  SpeedBatcherStatusBit('p_stat_Running', 'Running', Colors.green),
  SpeedBatcherStatusBit('p_stat_Cleaning', 'Cleaning', Colors.blue),
  SpeedBatcherStatusBit('p_stat_BatchReady', 'Batch ready', Colors.green),
  SpeedBatcherStatusBit('p_stat_DropOk', 'Conveyor may drop', Colors.green),
  SpeedBatcherStatusBit('p_stat_Dropped', 'Batch dropped', Colors.green),
];

/// The machine's name as it reads inside a diode label.
///
/// Shorter than [ThirdPartyEquipmentKindInfo.label], which carries the make
/// ("Afak / Strapex strapping line") -- a row saying "Fish waiting to drop to
/// Afak / Strapex strapping line" is worse than useless.
String equipmentShortName(ThirdPartyEquipmentKind kind) => switch (kind) {
      ThirdPartyEquipmentKind.multivac => 'Multivac',
      ThirdPartyEquipmentKind.speedBatcher => 'SpeedBatcher',
      ThirdPartyEquipmentKind.boxErector => 'box erector',
      ThirdPartyEquipmentKind.strappingLine => 'strapping machine',
      ThirdPartyEquipmentKind.fishAligner => 'batch aligner',
    };

/// One diode in a non-SpeedBatcher machine's Status section.
///
/// [suffix] is appended to the asset's [ThirdPartyEquipmentConfig.statusKey],
/// which for these kinds holds a key PREFIX rather than a struct node. The
/// SpeedBatcher can read members out of one struct because its handshake is a
/// published `SP_HMI`; the other machines expose their permits as separate
/// global bools (`BER02.PermitOutfeed`, `STM02.PermitInfeed`), so the prefix
/// plus a fixed suffix list is the closest equivalent.
class EquipmentStatusBit {
  final String suffix;

  /// Label template. `{m}` is replaced with the machine's name, so a row reads
  /// "Fish waiting to drop to Multivac" rather than "Fish waiting to drop" --
  /// the pane is one of several open at once and a bare label leaves the
  /// operator working out which machine it belongs to.
  final String label;

  final Color onColor;
  const EquipmentStatusBit(this.suffix, this.label, this.onColor);

  /// [label] with the machine name filled in, sentence-cased.
  ///
  /// The names are stored the way they read MID-sentence -- "box erector",
  /// "batch aligner", but "Multivac", which is a make and capitalised
  /// wherever it falls. Some rows start with the name and some do not, so the
  /// first letter of the finished label is what gets capitalised, not the
  /// name: "Box erector is ready for box bottom", "Way out of box erector is
  /// clear".
  String labelFor(String machine) {
    final filled = label.replaceAll('{m}', machine);
    if (filled.isEmpty) return filled;
    return filled[0].toUpperCase() + filled.substring(1);
  }
}

/// The diodes each kind shows, in display order.
///
/// Hardcoded, like [speedBatcherStatusBits]: every box erector on the site
/// exposes the same three permits, every strapper the same two. What differs
/// per machine is only which line it is on, and that is the prefix.
const Map<ThirdPartyEquipmentKind, List<EquipmentStatusBit>>
    kEquipmentStatusBits = {
  // One vocabulary across every machine, in the order product moves through it.
  // "Permit infeed/outfeed" is the PLC's language, not the floor's: an operator
  // asks whether a machine can take the next one and whether it can pass it on.
  //
  // Each machine is named for what it actually receives -- a box, a box bottom,
  // fish -- because that is what the operator is looking at when they ask why
  // it stopped.
  //
  //   Ready for <thing>     -- can accept another one now  (i_xDropOk / permit infeed)
  //   Way out clear         -- allowed to send onward      (permit outfeed)
  //   Fish waiting to drop  -- the conveyor before it is asking to drop  (i_xDropRequest)
  //   Drop complete         -- that hand-over finished     (q_xDropFinished)
  //   Waiting to release    -- a batch has been held at the door too long
  //                            (TON_waitingFrustration)
  //
  // Waiting to release is first and red because it is the only one that says
  // something is wrong rather than describing where in the cycle the machine
  // is. Note the direction: the batch is upstream, ready, and NOT being taken
  // -- the machine named on this pane is the one refusing it, not the one
  // waiting. The three below explain why.
  //
  // The question an operator opens this pane to answer is "why has product
  // stopped moving", and these say it directly: either it cannot take another
  // one, or it cannot send the one it has.
  //
  // Green means "yes, now", amber something in progress, blue the outfeed side,
  // so a glance down the column reads the same on every machine.
  ThirdPartyEquipmentKind.strappingLine: [
    EquipmentStatusBit('PermitInfeed', '{m} is ready for box', Colors.green),
    EquipmentStatusBit('PermitOutfeed', 'Way out of {m} is clear', Colors.blue),
  ],
  ThirdPartyEquipmentKind.boxErector: [
    EquipmentStatusBit('PermitBottomInfeed', '{m} is ready for box bottom', Colors.green),
    EquipmentStatusBit('PermitBlockInfeed', '{m} is ready for block', Colors.green),
    EquipmentStatusBit('PermitOutfeed', 'Way out of {m} is clear', Colors.blue),
  ],
  ThirdPartyEquipmentKind.multivac: [
    EquipmentStatusBit('WaitingFrustration', 'Waiting too long to release to {m}', Colors.red),
    EquipmentStatusBit('DropRequestFeedback', 'Fish waiting to drop to {m}', Colors.amber),
    EquipmentStatusBit('DropOk', '{m} is ready for fish', Colors.green),
    EquipmentStatusBit('DropFinished', 'Drop to {m} is complete', Colors.blue),
  ],
  ThirdPartyEquipmentKind.fishAligner: [
    EquipmentStatusBit('WaitingFrustration', 'Waiting too long to release to {m}', Colors.red),
    EquipmentStatusBit('DropRequestFeedback', 'Fish waiting to drop to {m}', Colors.amber),
    EquipmentStatusBit('DropOk', '{m} is ready for fish', Colors.green),
    EquipmentStatusBit('DropFinished', 'Drop to {m} is complete', Colors.blue),
  ],
};

/// The Status section body for the non-SpeedBatcher kinds.
///
/// A plain [StatelessWidget] fed a value per bit, exactly like
/// [SpeedBatcherStatusDiodes] -- NOT a ConsumerWidget reading
/// `keyStreamProvider` itself. The side pane is built into an overlay through
/// `showSidePane`, and a widget that reaches for `ref` from there is not on
/// the page's tree; the subscriptions belong to the parent state, which
/// outlives the pane and already owns the machine's other streams.
class EquipmentStatusDiodes extends StatelessWidget {
  const EquipmentStatusDiodes({
    super.key,
    required this.bits,
    required this.values,
    required this.machine,
  });

  final List<EquipmentStatusBit> bits;

  /// Name filled into each label's `{m}`.
  final String machine;

  /// Latest value per suffix. A missing entry renders unknown -- the same grey
  /// `!` a missing struct member gets on the SpeedBatcher.
  final Map<String, bool?> values;

  @override
  Widget build(BuildContext context) {
    // A hairline between rows, at the same alpha the pane chrome uses for its
    // header and footer borders, so the section reads as a list of separate
    // states rather than one block of text with dots beside it. Between only:
    // a rule under the last row would fight the section's own boundary.
    final rule = Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
    );
    return Column(
      children: [
        for (final (i, bit) in bits.indexed) ...[
          if (i > 0) rule,
          PaneDetailRow(
            // The diode is a fixed 22 px against a label that wraps, so centre
            // it -- top-aligned it hangs off the first line of a two-line row.
            crossAxisAlignment: CrossAxisAlignment.center,
            label: bit.labelFor(machine),
            child: SizedBox(
              // 22 px for the same reason as the SpeedBatcher's: below this the
              // unknown state's `!` blurs into the off state.
              width: 22,
              height: 22,
              child: CustomPaint(
                painter: LEDPainter(
                  color: switch (values[bit.suffix]) {
                    null => null,
                    true => bit.onColor,
                    false => Colors.white,
                  },
                  ledType: LEDType.circle,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Reads one handshake bit out of the status struct, degrading to unknown.
///
/// `null` — the unknown state — covers every way the bit can be absent: no
/// struct received yet, a non-struct value on the key, or a struct without
/// this member. The last one matters because `DynamicValue.operator[]` THROWS
/// on a missing member, and three of the five bits have never been confirmed
/// against the live PLC — a missing bit must render as the grey `!`, not take
/// the pane down.
bool? speedBatcherStatusBitOf(DynamicValue? status, String member) {
  if (status == null || !status.isObject) return null;
  if (!status.contains(member)) return null;
  return status[member].asBool;
}

/// Resolves the pane's header badge from the handshake struct.
///
/// The run key alone cannot tell "stopped" from "cleaning": during a wash the
/// Running bit drops, and a runKey-only badge would claim Stopped while the
/// machine is busy rinsing — which is exactly the lie the badge existed to
/// avoid. Cleaning outranks Running because the struct can raise both at
/// once mid-cycle. When neither bit is readable — no struct yet, no status
/// key — the caller's runKey-derived [fallback] stands.
PaneStatus speedBatcherPaneStatus(DynamicValue? status, PaneStatus fallback) {
  if (speedBatcherStatusBitOf(status, 'p_stat_Cleaning') == true) {
    // Blue to match the Cleaning diode below it.
    return const PaneStatus(
      label: 'Cleaning',
      color: Colors.blue,
      icon: Icons.cleaning_services,
    );
  }
  switch (speedBatcherStatusBitOf(status, 'p_stat_Running')) {
    case true:
      return const PaneStatus.running();
    case false:
      return const PaneStatus.stopped();
    case null:
      return fallback;
  }
}

/// The Status section body: one diode row per handshake bit.
///
/// Split out as its own widget — same seam as [ThirdPartyEquipmentBody] — so
/// tests and goldens can render every diode state from a hand-built
/// [DynamicValue] without a `StateMan`.
class SpeedBatcherStatusDiodes extends StatelessWidget {
  const SpeedBatcherStatusDiodes({
    super.key,
    required this.status,
  });

  /// Latest struct off the wire; `null` renders every diode unknown.
  final DynamicValue? status;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final bit in speedBatcherStatusBits)
          PaneDetailRow(
            crossAxisAlignment: CrossAxisAlignment.center,
            label: bit.label,
            // 22 px, not smaller: the unknown state is a grey fill with a
            // white `!`, and below this size the glyph blurs out and unknown
            // becomes indistinguishable from off — the exact confusion the
            // unknown state exists to prevent.
            child: SizedBox(
              width: 22,
              height: 22,
              child: CustomPaint(
                painter: LEDPainter(
                  color: switch (speedBatcherStatusBitOf(status, bit.member)) {
                    null => null,
                    true => bit.onColor,
                    false => Colors.white,
                  },
                  ledType: LEDType.circle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Picks the painter for [kind].
///
/// Exhaustive switch with no `default` — a new [ThirdPartyEquipmentKind] must
/// come with a painter or this stops compiling. Shared by the runtime widget
/// and the config-editor preview so the two can never drift.
ThirdPartyMachinePainter thirdPartyPainterFor(
  ThirdPartyEquipmentKind kind, {
  required Color color,
  required double strokeWidth,
  int strapMachines = 3,
}) {
  switch (kind) {
    case ThirdPartyEquipmentKind.multivac:
      return MultivacPainter(color: color, strokeWidth: strokeWidth);
    case ThirdPartyEquipmentKind.speedBatcher:
      return SpeedBatcherPainter(color: color, strokeWidth: strokeWidth);
    case ThirdPartyEquipmentKind.boxErector:
      return BoxErectorPainter(color: color, strokeWidth: strokeWidth);
    case ThirdPartyEquipmentKind.strappingLine:
      return StrappingLinePainter(
        color: color,
        strokeWidth: strokeWidth,
        machines: strapMachines.clamp(1, StrappingLinePainter.maxMachines),
      );
    case ThirdPartyEquipmentKind.fishAligner:
      return FishAlignerPainter(color: color, strokeWidth: strokeWidth);
  }
}

// ---------------------------------------------------------------------------
// Station scaffolding
// ---------------------------------------------------------------------------

/// A conveyor for use inside the box.
///
/// Bidirectional by default: on this station the belts are jogged both ways,
/// and a one-way belt would draw an arrow that contradicts what the operator
/// can see happening. `reverseDirection` stays off — the painter picks the
/// arrow direction from the sign of the live frequency.
ConveyorConfig thirdPartyConveyor({RelativeSize? size, double angleDegrees = 0}) {
  final conveyor = ConveyorConfig(bidirectional: true);
  if (size != null) conveyor.size = size;
  if (angleDegrees != 0) conveyor.coordinates.angle = angleDegrees;
  return conveyor;
}

/// A readout for use inside the box, sized to sit beside a weigh belt.
NumberConfig thirdPartyNumber({
  required String units,
  required int decimalPlaces,
  RelativeSize? size,
}) {
  final number = NumberConfig(
    key: '',
    units: units,
    decimalPlaces: decimalPlaces,
    // No graph: these sit inside another asset's box, and a tap-through to a
    // trend from a nested child is a surprise. The operator gets trends from
    // the number's own page placement.
    graphConfig: null,
  );
  if (size != null) number.size = size;
  return number;
}

/// The accept-rate readout for a checkweigher.
///
/// A `RatioNumberConfig`, not a plain number with a `%` suffix: accept rate is
/// accepted-over-total across a rolling window, which is precisely what this
/// asset models. Its `sinceMinutes` carries the window natively, so the figure
/// cannot be mistaken for an instantaneous reading and nothing has to be
/// smuggled into a units string.
RatioNumberConfig thirdPartyAcceptRatio({
  required int windowMinutes,
  bool clockAlignedBars = true,
  RelativeSize? size,
}) {
  final ratio = RatioNumberConfig(
    // Operator points these at accepted-count and total-count.
    key1: '',
    key2: '',
    key1Label: 'accepted',
    key2Label: 'total',
    sinceMinutes: Duration(minutes: windowMinutes),
    // The chart's interval toggles come from here, and the readout opens that
    // chart on [windowMinutes]. Leaving the RatioNumber default in place
    // ([1, 5, 10, 60, 240]) meant a 30-minute station opened its chart on a
    // window the toggles could not show: none of them lit up, and there was
    // no way back to 30 once another was pressed.
    intervalPresets: acceptWindowPresets(windowMinutes),
    barsClockAligned: clockAlignedBars,
    // The bars count packs. A Y axis offering 2.5 of one is noise, and on a
    // short window — where the counts are single digits — it is most of the
    // axis.
    integersOnly: true,
    decimalPlaces: 1,
  );
  if (size != null) ratio.size = size;
  return ratio;
}

/// The accept-rate window as it reads to an operator — `30 min`, `4 h`, `1 d`.
///
/// The space is non-breaking: this string is dropped into a parenthesis at the
/// end of a pane row label narrow enough to wrap, and the break must fall
/// before the parenthesis, never inside it.
String formatAcceptWindow(int minutes) {
  if (minutes < 60) return '$minutes\u{00A0}min';
  if (minutes % 1440 == 0) return '${minutes ~/ 1440}\u{00A0}d';
  if (minutes % 60 == 0) return '${minutes ~/ 60}\u{00A0}h';
  return '$minutes\u{00A0}min';
}

/// Interval toggles for an accept-rate readout's chart.
///
/// The standard ladder with the station's own averaging window folded in, so
/// the window the figure is quoted over is always one of the offered ones.
List<int> acceptWindowPresets(int windowMinutes) =>
    <int>{1, 5, 10, 30, 60, 240, if (windowMinutes > 0) windowMinutes}.toList()
      ..sort();

/// The windows the side pane offers for the accept-rate readouts.
///
/// The configured [acceptWindowMinutes] plus whatever intervals the readouts
/// themselves were given — the same presets the accept/reject chart's toggles
/// use, so the picker and the chart it opens never disagree about which
/// windows exist. Sorted, de-duplicated, and always containing the configured
/// window so the pane opens on a window it can actually offer.
List<int> thirdPartyAcceptWindowOptions(
  Iterable<RatioNumberConfig> ratios, {
  required int acceptWindowMinutes,
}) {
  final options = <int>{
    acceptWindowMinutes,
    for (final ratio in ratios) ...ratio.intervalPresets,
  }.where((m) => m > 0).toList()
    ..sort();
  return options;
}

/// Builds the standard set of live assets for the SpeedBatcher station.
///
/// One bidirectional conveyor on each checkweigher's weigh belt, with its
/// weight readout to the right and its accept rate to the left — the layout
/// Jón asked for. Keys are left empty on purpose: the scaffold places and
/// sizes everything, then the operator points each child at its tag through
/// the per-child Configure button.
///
/// The two conveyor LANES are not scaffolded: they run up the page, so a
/// conveyor there would need a 90-degree angle and a thickness that depends
/// on the asset's pixel aspect. They stay part of the painted drawing — the
/// SpeedBatcher box is static, and its editor offers no free-form add
/// buttons; this scaffold is everything that lives inside it.
///
/// [acceptWindowMinutes] is folded into the accept readout's units so the
/// averaging window is visible on the mimic rather than assumed.
List<ThirdPartyChildEntry> buildSpeedBatcherStationChildren({
  int acceptWindowMinutes = 30,
  bool acceptBarsClockAligned = true,
}) {
  final entries = <ThirdPartyChildEntry>[];

  void addCheckweigher(String name, Rect frame) {
    final deck = SpeedBatcherPainter.deckOf(frame);
    final accept = SpeedBatcherPainter.acceptAnchorOf(frame);
    final weight = SpeedBatcherPainter.weightAnchorOf(frame);

    entries.add(ThirdPartyChildEntry(
      offsetX: deck.center.dx,
      offsetY: deck.center.dy,
      // Half a revolution: product runs right-to-left across the weigh
      // belts on the real machine, so the belt drawing is turned to make a
      // positive live frequency draw its arrow with the product flow.
      child: thirdPartyConveyor(
        size: RelativeSize(width: deck.width, height: deck.height),
        angleDegrees: 180,
      ),
    ));
    // Readout slots, sitting ON the belt either side of the run-direction
    // arrow. The arrow owns the middle 40% of the belt, so a slot may be at
    // most ~0.28 wide before it collides with the arrowhead.
    //
    // `NumberWidget` scales its text with BoxFit.contain, so slot width sets
    // the font size and a long units string shrinks the number to a smear —
    // which is why the averaging window is NOT spelled out here. `% 30m` is
    // the longest suffix that stays legible; the full wording lives in the
    // side pane, where there is room for it.
    final slot = RelativeSize(width: 0.22, height: frame.height * 0.6);

    entries.add(ThirdPartyChildEntry(
      offsetX: accept.dx,
      offsetY: accept.dy,
      keepUpright: true,
      child: thirdPartyAcceptRatio(
        windowMinutes: acceptWindowMinutes,
        clockAlignedBars: acceptBarsClockAligned,
        size: slot,
      ),
    ));
    entries.add(ThirdPartyChildEntry(
      offsetX: weight.dx,
      offsetY: weight.dy,
      keepUpright: true,
      child: thirdPartyNumber(
        units: '',
        decimalPlaces: 0,
        size: slot,
      ),
    ));
  }

  // Product order: checkweigher 1 first, then 2.
  addCheckweigher('CW1', SpeedBatcherPainter.checkweigher1Frame);
  addCheckweigher('CW2', SpeedBatcherPainter.checkweigher2Frame);
  return entries;
}

// ---------------------------------------------------------------------------
// Runtime widget
// ---------------------------------------------------------------------------

/// Live third-party equipment widget driven by a bool run-status key.
///
/// The stream is hoisted to `initState` and only rebuilt when `runKey` changes
/// — building it in `build()` would create and cancel an OPC UA monitored item
/// every frame. Same lifecycle contract as `Sensor` in `sensor.dart`.
class ThirdPartyEquipment extends ConsumerStatefulWidget {
  final ThirdPartyEquipmentConfig config;
  const ThirdPartyEquipment({super.key, required this.config});

  @override
  ConsumerState<ThirdPartyEquipment> createState() =>
      _ThirdPartyEquipmentState();
}

class _ThirdPartyEquipmentState extends ConsumerState<ThirdPartyEquipment> {
  /// `null` means no stream is needed — the run key is empty.
  Stream<bool>? _runStream;

  /// The single subscription to [_runStream].
  ///
  /// The state is fanned out through [_raw] rather than by letting each
  /// consumer wrap the stream in its own `StreamBuilder`. Two reasons: the
  /// hoisted stream is single-subscription, so a second listener throws
  /// "Stream has already been listened to" the moment an operator opens the
  /// pane on a machine that has a run key; and one subscription means the LED
  /// and the pane can never disagree about what the machine is doing.
  StreamSubscription<bool>? _sub;

  /// Latest RAW value off the wire, before polarity is applied. `null` is the
  /// unknown state — no key, nothing received yet, or the stream errored.
  ///
  /// Polarity is deliberately NOT baked in here: the editor can flip
  /// `invertRunPolarity` without the key changing, and re-hoisting the stream
  /// just to re-map a bool would drop and recreate a PLC subscription.
  final ValueNotifier<bool?> _raw = ValueNotifier<bool?>(null);

  /// The key `_runStream` was built for. Compared against the live config
  /// rather than `oldWidget.config.runKey` because the page editor mutates the
  /// same config instance in place, so both widgets hold the same reference.
  String? _hoistedKey;

  /// `null` means no status stream is needed — not a SpeedBatcher, or the
  /// status key is empty. Same hoisted lifecycle as [_runStream].
  Stream<DynamicValue>? _statusStream;

  /// The single subscription to [_statusStream], fanned out through
  /// [_statusRaw] for the same single-subscription reasons as [_sub].
  StreamSubscription<DynamicValue>? _statusSub;

  /// Latest handshake struct off the wire. `null` renders every diode in the
  /// pane's Status section unknown — nothing received yet, or the stream
  /// errored.
  final ValueNotifier<DynamicValue?> _statusRaw =
      ValueNotifier<DynamicValue?>(null);

  /// Latest value per status-bit suffix, for the kinds whose diodes come from
  /// separate keys rather than one struct. Held here rather than in the pane
  /// because the pane lives in an overlay and is torn down and rebuilt every
  /// time it opens; the subscriptions should not be.
  final ValueNotifier<Map<String, bool?>> _statusBits =
      ValueNotifier<Map<String, bool?>>({});

  /// One subscription per bit, keyed by suffix.
  final Map<String, StreamSubscription<DynamicValue>> _bitSubs = {};

  /// The averaging window the pane's accept-rate readouts are counting over.
  ///
  /// Pane-local and deliberately not written back to the config: widening the
  /// view to see whether a bad minute was a blip is a question, not a page
  /// edit. Reopening the pane comes back on the configured window. Held here
  /// rather than in the pane body because the pane lives in an overlay that is
  /// rebuilt on every open, and it is merged into the pane's listenable so a
  /// pick repaints the rows exactly like a value arriving does.
  late final ValueNotifier<int> _acceptWindow =
      ValueNotifier<int>(widget.config.acceptWindowMinutes);

  /// The key [_statusStream] was built for; compared against [_wantedStatusKey]
  /// so a kind change away from SpeedBatcher drops the subscription too.
  String? _hoistedStatusKey;

  /// The status key this config actually wants a subscription for. Empty for
  /// every kind but the SpeedBatcher — a leftover [ThirdPartyEquipmentConfig.statusKey]
  /// on a config switched to another kind must not hold a PLC subscription
  /// open for a section the pane no longer shows.
  String get _wantedStatusKey =>
      widget.config.kind == ThirdPartyEquipmentKind.speedBatcher
          ? widget.config.statusKey
          : '';

  bool? get _isRunning {
    final raw = _raw.value;
    if (raw == null) return null;
    return thirdPartyIsRunning(
      rawBool: raw,
      invertRunPolarity: widget.config.invertRunPolarity,
    );
  }

  @override
  void initState() {
    super.initState();
    _hoistStream();
    _hoistStatusStream();
    _hoistStatusBits();
  }

  /// Subscribe every bit this kind shows, dropping any that no longer apply.
  ///
  /// Re-entrant: called again when the prefix or the kind changes, so a config
  /// edit in the page editor moves the diodes onto the new keys without a
  /// restart, and a kind switch releases the old machine's subscriptions.
  void _hoistStatusBits() {
    final bits = kEquipmentStatusBits[widget.config.kind];
    final prefix = widget.config.statusKey;
    final wanted = <String, String>{
      if (bits != null && prefix.isNotEmpty)
        for (final bit in bits) bit.suffix: '$prefix.${bit.suffix}',
    };
    for (final suffix in _bitSubs.keys.toList()) {
      if (!wanted.containsKey(suffix)) {
        _bitSubs.remove(suffix)?.cancel();
        _statusBits.value = Map.of(_statusBits.value)..remove(suffix);
      }
    }
    for (final entry in wanted.entries) {
      if (_bitSubs.containsKey(entry.key)) continue;
      // Straight through StateMan like [_hoistStream], NOT through
      // `keyStreamProvider`: that provider is autoDispose, and a bare
      // `ref.read` from here registers no listener, so it is disposed at the
      // end of the frame and closes its subject before the first value can
      // arrive — the diode would sit at unknown forever.
      _bitSubs[entry.key] = ref
          .read(stateManProvider.future)
          .asStream()
          .asyncExpand((sm) => sm.subscribe(entry.value).asStream())
          .asyncExpand((s) => s)
          .listen((v) {
        if (!mounted) return;
        _statusBits.value = Map.of(_statusBits.value)..[entry.key] = v.asBool;
      }, onError: (_) {
        if (!mounted) return;
        // Unknown, not false: a key that errors has told us nothing.
        _statusBits.value = Map.of(_statusBits.value)..[entry.key] = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ThirdPartyEquipment oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hoistedKey != widget.config.runKey) {
      _hoistStream();
    }
    if (_hoistedStatusKey != _wantedStatusKey) {
      _hoistStatusStream();
    }
    // The prefix or the kind may have changed under us -- the page editor
    // mutates the same config instance in place, so comparing against
    // oldWidget would miss it. _hoistStatusBits is re-entrant and diffs.
    _hoistStatusBits();
  }

  void _hoistStream() {
    final key = widget.config.runKey;
    _hoistedKey = key;
    _sub?.cancel();
    _sub = null;
    _raw.value = null;
    if (key.isEmpty) {
      _runStream = null;
      return;
    }
    _runStream = ref
        .read(stateManProvider.future)
        .asStream()
        .asyncExpand((sm) => sm.subscribe(key).asStream())
        .asyncExpand((s) => s)
        .map((dv) => dv.asBool);
    _sub = _runStream!.listen(
      (value) => _raw.value = value,
      // Fall back to unknown rather than latching the last good value: a
      // stale "running" is worse than an honest "we don't know".
      onError: (Object _) => _raw.value = null,
    );
  }

  /// Hoists the SpeedBatcher status-struct stream, mirroring [_hoistStream].
  /// Unlike the run stream the value stays a [DynamicValue]: the pane reads
  /// individual `p_stat_*` members out of it per diode.
  void _hoistStatusStream() {
    final key = _wantedStatusKey;
    _hoistedStatusKey = key;
    _statusSub?.cancel();
    _statusSub = null;
    _statusRaw.value = null;
    if (key.isEmpty) {
      _statusStream = null;
      return;
    }
    _statusStream = ref
        .read(stateManProvider.future)
        .asStream()
        .asyncExpand((sm) => sm.subscribe(key).asStream())
        .asyncExpand((s) => s);
    _statusSub = _statusStream!.listen(
      (value) => _statusRaw.value = value,
      // Same honesty rule as the run stream: unknown beats a stale latch.
      onError: (Object _) => _statusRaw.value = null,
    );
  }

  /// Test-only window onto the hoisted stream identity, so the stream
  /// lifecycle can be asserted without a real `StateMan`.
  @visibleForTesting
  Stream<bool>? get debugRunStream => _runStream;

  /// Test-only window onto the hoisted status stream, as [debugRunStream].
  @visibleForTesting
  Stream<DynamicValue>? get debugStatusStream => _statusStream;

  @override
  void dispose() {
    // A docked pane lives in the root overlay, so it would survive a page
    // change and go on showing a machine that is no longer on screen. Scoped
    // by id so we never close someone else's pane.
    closeSidePane(id: _paneId, immediate: true);
    _sub?.cancel();
    _raw.dispose();
    _statusSub?.cancel();
    _statusRaw.dispose();
    for (final sub in _bitSubs.values) {
      sub.cancel();
    }
    _bitSubs.clear();
    // Safe because the closeSidePane above is `immediate` -- the overlay entry
    // is gone in this frame, not gliding out over the next dozen. Without that
    // the pane would still be mounted and rebuilding against this notifier,
    // and disposing it here threw on the next rebuild.
    _statusBits.dispose();
    _acceptWindow.dispose();
    super.dispose();
  }

  /// Opens the read-only side pane — the "more information" behind the tap.
  ///
  /// A [SidePane] rather than a dialog because this is equipment on a running
  /// line: the operator wants to read the handshake while still watching the
  /// mimic, and a modal barrier would hide the very machine they are
  /// diagnosing. The pane rebuilds itself from the run stream, so the status
  /// chip stays live while it is open.
  ///
  /// No writes: we report what the handshake says, we do not command other
  /// people's machines.
  /// Identifies this asset's pane. Tapping the same machine twice toggles its
  /// pane shut; tapping a different one swaps.
  String get _paneId {
    final config = widget.config;
    return 'third-party:${config.tag ?? ''}:${config.runKey}:'
        '${config.kind.name}';
  }

  void _showPane(BuildContext context) {
    // Pane copies of the weight readouts: same key and format as on the
    // mimic, but WITH a trend graph — the tap-through that would be a
    // surprise on a nested child is exactly what the pane exists for.
    // Cloned once per open, not per rebuild, so the graph dialog id and the
    // value subscription stay stable while the pane repaints off the run
    // and status notifiers.
    final weights = <NumberConfig>[];
    for (final entry in widget.config.children) {
      final child = entry.child;
      if (child is! NumberConfig) continue;
      weights.add(NumberConfig(
        key: child.key,
        showDecimalPoint: child.showDecimalPoint,
        decimalPlaces: child.decimalPlaces,
        // The belt readout is unitless — there is no room beside the arrow —
        // but the pane has the room, so the unit goes here: whatever the
        // operator configured on the child, kg otherwise.
        units: (child.units?.isNotEmpty ?? false) ? child.units : 'kg',
        scale: child.scale,
        graphConfig: GraphAssetConfig.preview(
            key: child.key.isEmpty ? null : child.key)
          ..headerText = 'Weight, checkweigher ${weights.length + 1} — trend',
      ));
    }

    showSidePane(
      context: context,
      id: _paneId,
      // Rebuilds off the same notifiers the body uses, so the status chip
      // stays live while the pane is open and always agrees with the LED.
      // Merged rather than nested: the status struct only feeds the pane, so
      // the body's ValueListenableBuilder stays on `_raw` alone.
      builder: (context) => ListenableBuilder(
        listenable:
            Listenable.merge([_raw, _statusRaw, _statusBits, _acceptWindow]),
        builder: (context, _) => _paneFor(context, _isRunning, weights),
      ),
    );
  }

  /// A compact trailing chart button for a pane row.
  ///
  /// The live figure beside it is tappable too — the readouts keep their own
  /// tap-through — but a figure does not LOOK tappable, so the button is the
  /// visible way into the chart.
  Widget _chartButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
      onPressed: onPressed,
    );
  }

  Widget _paneFor(
      BuildContext context, bool? isRunning, List<NumberConfig> weights) {
    final config = widget.config;
    PaneStatus status;
    if (config.runKey.isEmpty) {
      status = const PaneStatus.unknown('No key');
    } else if (isRunning == null) {
      status = const PaneStatus.stale();
    } else {
      status =
          isRunning ? const PaneStatus.running() : const PaneStatus.stopped();
    }
    if (config.kind == ThirdPartyEquipmentKind.speedBatcher) {
      // The handshake struct outranks the bare run bool: it can say
      // "Cleaning", which the run key would misreport as Stopped.
      status = speedBatcherPaneStatus(_statusRaw.value, status);
    }

    // The scaffolded accept-rate readouts, in checkweigher order. Surfaced
    // as LIVE figures in the pane — the operator opens it to read the
    // machine, not its wiring, so keys and static wording stay out.
    final acceptRatios = [
      for (final entry in config.children)
        if (entry.child case final RatioNumberConfig ratio) ratio,
    ];
    final acceptOptions = thirdPartyAcceptWindowOptions(acceptRatios,
        acceptWindowMinutes: config.acceptWindowMinutes);
    // A window the options no longer contain — the page was edited while the
    // pane was open — falls back to the configured one rather than leaving the
    // dropdown on a value it has no item for, which asserts.
    final acceptWindow = acceptOptions.contains(_acceptWindow.value)
        ? _acceptWindow.value
        : config.acceptWindowMinutes;

    return SidePane(
      title: config.tag?.isNotEmpty == true
          ? config.tag!
          : config.kind.labelFor(strapMachines: config.strapMachines),
      subtitle: config.tag?.isNotEmpty == true
          ? config.kind.labelFor(strapMachines: config.strapMachines)
          : 'Third-party equipment',
      icon: Icons.precision_manufacturing,
      status: status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PaneSection(
            title: 'Equipment',
            child: Column(
              children: [
                PaneDetailRow(
                  label: 'Machine',
                  value:
                      config.kind.labelFor(strapMachines: config.strapMachines),
                ),
                if (config.kind.hasStrapMachines)
                  PaneDetailRow(
                    label: 'Strappers on the line',
                    value: '${config.strapMachines}',
                  ),
                // Live figures, not key names or static wording — the pane
                // is for reading the machine, not its wiring. Charts stay
                // behind a tap so the pane itself does not crowd: the accept
                // figure opens its accept/reject bar chart (the
                // RatioNumberWidget's own tap-through), the weight opens its
                // trend.
                // The window, stated once for both scales rather than
                // repeated in each figure's label: a rolling average read as
                // "right now" is the whole reason this asset carries a window,
                // and one row directly above the figures says it without
                // pushing every label onto three lines.
                //
                // One picker for both, too — they are the same product stream
                // a few metres apart, and reading them over different windows
                // would compare nothing to nothing.
                //
                // Nothing to pick between: an empty picker is worse than
                // none, but the window still has to be on the pane.
                if (acceptRatios.isNotEmpty && acceptOptions.length == 1)
                  PaneDetailRow(
                    label: 'Accept rate window',
                    value: formatAcceptWindow(acceptWindow),
                  ),
                if (acceptRatios.isNotEmpty && acceptOptions.length > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    // Full width, and explicitly so: the section's Column
                    // centres whatever does not stretch, which left this
                    // block floating a few pixels right of every label
                    // beside it.
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Accept rate window',
                              style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: 4),
                          // Literally the chart's picker, one size down.
                          // Full width rather than in a [PaneDetailRow]'s
                          // value column, which is too narrow for a ladder of
                          // chips to reflow in.
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: ratioIntervalChips(
                              options: acceptOptions,
                              selectedMinutes: acceptWindow,
                              onSelected: (m) => _acceptWindow.value = m,
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final (i, ratio) in acceptRatios.indexed)
                  PaneDetailRow(
                    label: 'Accept rate, checkweigher ${i + 1}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 22,
                          child: RatioNumberWidget(
                            config: ratio,
                            intervalOverride: Duration(minutes: acceptWindow),
                            intervalOptions: acceptOptions,
                          ),
                        ),
                        _chartButton(
                          icon: Icons.bar_chart,
                          tooltip: 'Accept/reject chart',
                          // The chart opens on the window the pane is
                          // showing, not on the configured one — otherwise
                          // tapping through to explain a figure changes the
                          // figure.
                          onPressed: () => showRatioAnalysisDialog(
                              context, ref, ratio,
                              interval: Duration(minutes: acceptWindow)),
                        ),
                      ],
                    ),
                  ),
                for (final (i, weight) in weights.indexed)
                  PaneDetailRow(
                    label: 'Weight, checkweigher ${i + 1}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 22,
                          child: NumberWidget(config: weight),
                        ),
                        _chartButton(
                          icon: Icons.show_chart,
                          tooltip: 'Weight trend',
                          onPressed: () =>
                              showNumberGraphDialog(context, weight),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (config.kind == ThirdPartyEquipmentKind.speedBatcher)
            // Always present for a SpeedBatcher, key configured or not: five
            // grey `!` diodes tell the operator the section exists and is
            // unconfigured, which a silently absent section would not.
            PaneSection(
              title: 'Status',
              child: SpeedBatcherStatusDiodes(
                status: _statusRaw.value,
              ),
            ),
          if (config.kind != ThirdPartyEquipmentKind.speedBatcher &&
              kEquipmentStatusBits[config.kind] != null)
            PaneSection(
              title: 'Status',
              child: EquipmentStatusDiodes(
                bits: kEquipmentStatusBits[config.kind]!,
                values: _statusBits.value,
                machine: equipmentShortName(config.kind),
              ),
            ),
          if (config.notes != null && config.notes!.isNotEmpty)
            PaneSection(
              title: 'Notes',
              child: SelectableText(config.notes!),
            ),
        ],
      ),
    );
  }

  /// Machine drawing + dotted boundary + run LED, wrapped in the tap target.
  ///
  /// The `GestureDetector` sits OUTSIDE `LayoutRotatedBox` because
  /// `_RenderLayoutRotatedBox.hitTest` (in `common.dart`) does not forward hits
  /// to its child — same arrangement as `Sensor._buildPaint` and
  /// `_buildGate` in `conveyor_gate.dart`.
  Widget _buildBody(bool? isRunning) {
    final config = widget.config;
    final ledColor = isRunning == null
        ? null
        : (isRunning ? config.runningColor : config.stoppedColor);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showPane(context),
      child: LayoutRotatedBox(
        angle: (config.coordinates.angle ?? 0.0) * pi / 180,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Prefer the bounded asset rect; fall back to the configured size
            // resolved against the screen for the standalone/preview path.
            final Size paintSize =
                constraints.hasBoundedWidth && constraints.hasBoundedHeight
                    ? Size(constraints.maxWidth, constraints.maxHeight)
                    : config.size.toSize(MediaQuery.of(context).size);

            return ThirdPartyEquipmentBody(
              painter: thirdPartyPainterFor(
                config.kind,
                color: config.outlineColor,
                strokeWidth: config.strokeWidth,
                strapMachines: config.strapMachines,
              ),
              paintSize: paintSize,
              ledColor: ledColor,
              children: config.children,
              parentAngleDegrees: config.coordinates.angle ?? 0.0,
              childTextAngle: config.childTextAngle,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // All three stale paths — no key, nothing received yet, stream errored —
    // arrive here as a null `_raw`, and `_isRunning` keeps them null.
    return ValueListenableBuilder<bool?>(
      valueListenable: _raw,
      builder: (context, _, __) => _buildBody(_isRunning),
    );
  }
}

/// The painted body: machine glyph + dotted boundary, with the run LED
/// composited into the top-left header strip.
///
/// The LED is a real [LEDPainter] rather than a circle drawn by the machine
/// painter, so it matches every other LED on the page — including the grey `!`
/// it draws for an unknown value (`ledColor == null`).
///
/// Split out as its own widget so the config-editor preview and the golden
/// tests can render it without a `StateMan`.
class ThirdPartyEquipmentBody extends StatelessWidget {
  const ThirdPartyEquipmentBody({
    super.key,
    required this.painter,
    required this.paintSize,
    required this.ledColor,
    this.children = const [],
    this.parentAngleDegrees = 0.0,
    this.childTextAngle = 0.0,
  });

  final ThirdPartyMachinePainter painter;
  final Size paintSize;

  /// `null` renders the LED's unknown state.
  final Color? ledColor;

  /// Live assets composited over the drawing, inside the machine area.
  final List<ThirdPartyChildEntry> children;

  /// Rotation already applied to this body by the parent's `LayoutRotatedBox`.
  /// Upright children are turned back by this much.
  final double parentAngleDegrees;

  /// Extra rotation for upright children, on top of the counter-rotation.
  final double childTextAngle;

  /// Positions one child by its centre within the machine area.
  ///
  /// The child's own `RelativeSize` is resolved against the MACHINE AREA, not
  /// the screen — same convention as `Elevator._buildPositionedChild` — so a
  /// conveyor sized to half a lane stays half a lane at any asset size.
  ///
  /// A child marked [ThirdPartyChildEntry.keepUpright] is counter-rotated out
  /// of the parent's rotation and then turned by [childTextAngle], so
  /// readouts stay level however the machine is placed. The rotation is
  /// visual only — the layout box does not turn — which is what keeps a
  /// readout inside the slot the scaffold gave it.
  Widget _positionedChild(
      BuildContext context, ThirdPartyChildEntry entry, Rect area) {
    final intrinsic = entry.child.size.toSize(area.size);
    final w = intrinsic.width <= 0 ? area.shortestSide / 4 : intrinsic.width;
    final h = intrinsic.height <= 0 ? area.shortestSide / 4 : intrinsic.height;

    // KeyedSubtree on the stable entry id: without it, reordering or editing
    // the list re-creates the child's State and re-subscribes its stream.
    //
    // The MediaQuery override is what makes "the child's size is relative to
    // the machine area" true for EVERY asset. Most resolve their RelativeSize
    // against the incoming constraints, but some — Conveyor among them —
    // resolve it against `MediaQuery.of(context).size`, and would otherwise
    // paint at full-screen scale and spill straight out of the box. Handing
    // them a MediaQuery whose size IS the machine area makes both conventions
    // land on the same pixels.
    Widget built = KeyedSubtree(
      key: ValueKey<String>(entry.id),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(size: area.size),
        child: entry.child.build(context),
      ),
    );
    if (entry.keepUpright) {
      built = Transform.rotate(
        angle: (childTextAngle - parentAngleDegrees) * pi / 180,
        child: built,
      );
    }

    return Positioned(
      left: area.left + entry.offsetX * area.width - w / 2,
      top: area.top + entry.offsetY * area.height - h / 2,
      width: w,
      height: h,
      child: built,
    );
  }

  @override
  Widget build(BuildContext context) {
    final boundary = thirdPartyBoundaryRect(paintSize);
    final area = thirdPartyMachineArea(paintSize);
    final led = thirdPartyLedDiameter(paintSize);
    final inset = thirdPartyLedInset(paintSize);

    return SizedBox(
      width: paintSize.width,
      height: paintSize.height,
      // Clip.none so a child that overhangs its lane is visible rather than
      // silently cropped — the editor needs to show the mistake.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: CustomPaint(painter: painter)),
          for (final entry in children) _positionedChild(context, entry, area),
          Positioned(
            left: boundary.left + inset,
            top: boundary.top + inset,
            width: led,
            height: led,
            child: CustomPaint(
              painter: LEDPainter(color: ledColor, ledType: LEDType.circle),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Config editor
// ---------------------------------------------------------------------------

/// Fits a preview box of [aspect] (width / height) inside the editor column
/// without distorting it. Landscape kinds hit the width limit, the portrait
/// SpeedBatcher hits the height limit.
Size _fitPreview(double aspect, {double maxW = 300, double maxH = 300}) {
  double w = maxW;
  double h = maxW / aspect;
  if (h > maxH) {
    h = maxH;
    w = maxH * aspect;
  }
  return Size(w, h);
}

/// Editor body for [ThirdPartyEquipmentConfig]. Field order follows the
/// house pattern: preview, identity, live keys, colours, label, geometry.
class _ThirdPartyEquipmentConfigEditor extends StatefulWidget {
  final ThirdPartyEquipmentConfig config;
  const _ThirdPartyEquipmentConfigEditor({required this.config});

  @override
  State<_ThirdPartyEquipmentConfigEditor> createState() =>
      _ThirdPartyEquipmentConfigEditorState();
}

class _ThirdPartyEquipmentConfigEditorState
    extends State<_ThirdPartyEquipmentConfigEditor> {
  late TextEditingController _tagController;
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _tagController = TextEditingController(text: widget.config.tag ?? '');
    _notesController = TextEditingController(text: widget.config.notes ?? '');
  }

  @override
  void dispose() {
    _tagController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Widget _colorRow(String label, Color color, ValueChanged<Color> onChanged) {
    return ColorPickerRow(label: label, color: color, onChanged: onChanged);
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    // Preview at the machine's TRUE plan aspect ratio, so the layout is
    // undistorted here even if the asset on the page is sized differently.
    // Fitted rather than clamped: the kinds run from a 5.4:1 Multivac strip
    // to a portrait SpeedBatcher, and clamping either axis would squash one
    // of them — which is exactly the distortion this preview exists to avoid.
    final previewSize = _fitPreview(
      config.kind.aspectRatio(strapMachines: config.strapMachines),
    );

    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ThirdPartyEquipmentBody(
                painter: thirdPartyPainterFor(
                  config.kind,
                  color: config.outlineColor,
                  strokeWidth: config.strokeWidth,
                  strapMachines: config.strapMachines,
                ),
                paintSize: previewSize,
                // Preview always shows the running colour — the operator is
                // picking colours here, not reading live state.
                ledColor: config.runningColor,
                // Children are deliberately NOT rendered in the preview: they
                // subscribe to real keys, and the editor should not open live
                // subscriptions just to draw a thumbnail.
              ),
            ),
            const Divider(),

            // -- Equipment kind --
            Text('Equipment', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            DropdownButton<ThirdPartyEquipmentKind>(
              value: config.kind,
              isExpanded: true,
              onChanged: (value) => setState(() {
                config.kind = value!;
                // A SpeedBatcher without its belts and readouts is not a
                // useful asset — the checkweighers ARE conveyors, and the
                // weight and accept rate are the reason the station is on the
                // mimic. Build them on selection so the operator gets a
                // working station and only has to point the keys at tags.
                // Only when empty, so switching away and back cannot discard
                // configured children.
                if (config.kind == ThirdPartyEquipmentKind.speedBatcher &&
                    config.children.isEmpty) {
                  config.children.addAll(buildSpeedBatcherStationChildren(
                    acceptWindowMinutes: config.acceptWindowMinutes,
                    acceptBarsClockAligned: config.acceptBarsClockAligned,
                  ));
                }
              }),
              items: ThirdPartyEquipmentKind.values
                  .map((e) => DropdownMenuItem<ThirdPartyEquipmentKind>(
                        value: e,
                        child: Text(e.label),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),

            // -- Strappers standing on the line --
            if (config.kind.hasStrapMachines) ...[
              Text('Strappers on the line',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                ],
                selected: {config.strapMachines.clamp(1, 3)},
                onSelectionChanged: (selection) =>
                    setState(() => config.strapMachines = selection.first),
              ),
              const SizedBox(height: 16),
            ],

            // -- Run status key --
            KeyField(
              label: 'Run Status Key',
              initialValue: config.runKey,
              onChanged: (v) => setState(() => config.runKey = v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Invert Run Polarity'),
              subtitle: Text(
                config.invertRunPolarity
                    ? 'Running when state is false'
                    : 'Running when state is true',
              ),
              value: config.invertRunPolarity,
              onChanged: (v) => setState(() => config.invertRunPolarity = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),

            // -- Status key --
            // Every kind's pane has a Status section, so every kind gets the
            // field — without it the diodes can never leave the unknown
            // state. The SpeedBatcher reads members of one struct; the other
            // machines read separate bools, so their key is a prefix and the
            // help text spells out the suffixes the pane appends.
            KeyField(
              label: config.kind == ThirdPartyEquipmentKind.speedBatcher
                  ? 'Status Struct Key'
                  : 'Status Key Prefix',
              initialValue: config.statusKey,
              onChanged: (v) => setState(() => config.statusKey = v),
            ),
            const SizedBox(height: 4),
            Text(
              config.kind == ThirdPartyEquipmentKind.speedBatcher
                  ? 'Struct with the p_stat_* handshake bits — feeds the '
                      'diodes in the side pane\'s Status section.'
                  : 'Feeds the diodes in the side pane\'s Status section: '
                      '${(kEquipmentStatusBits[config.kind] ?? const []).map((b) => '.${b.suffix}').join(', ')} '
                      'are appended to this prefix.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // -- Colours --
            _colorRow('Running Color', config.runningColor,
                (c) => setState(() => config.runningColor = c)),
            const SizedBox(height: 8),
            _colorRow('Stopped Color', config.stoppedColor,
                (c) => setState(() => config.stoppedColor = c)),
            const SizedBox(height: 8),
            _colorRow('Outline Color', config.outlineColor,
                (c) => setState(() => config.outlineColor = c)),
            const SizedBox(height: 16),

            // -- Stroke width --
            TextFormField(
              initialValue: config.strokeWidth.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stroke Width'),
              onChanged: (value) {
                final parsed = double.tryParse(value);
                if (parsed != null && parsed > 0.0 && parsed <= 10.0) {
                  setState(() => config.strokeWidth = parsed);
                }
              },
            ),
            const SizedBox(height: 16),

            // -- Tag --
            TextFormField(
              controller: _tagController,
              decoration: const InputDecoration(
                labelText: 'Tag (e.g. MV-01)',
                hintText: 'Optional',
              ),
              onChanged: (v) =>
                  setState(() => config.tag = v.isEmpty ? null : v),
            ),
            // The page label scales its font with the asset's bounding box,
            // and these machines are big — so on the mimic the tag comes out
            // huge. Off keeps it to the side pane, which shows it regardless.
            SwitchListTile(
              title: const Text('Show tag on page'),
              subtitle: const Text(
                  'The side pane shows the tag either way'),
              value: config.showTag,
              onChanged: (v) => setState(() => config.showTag = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),

            // -- Notes (details dialog) --
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Shown in the details dialog',
              ),
              onChanged: (v) =>
                  setState(() => config.notes = v.isEmpty ? null : v),
            ),
            const SizedBox(height: 16),

            // -- Label position --
            // Only meaningful while the tag is painted on the page.
            if (config.showTag) ...[
              Text('Label Position',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              DropdownButton<TextPos>(
                value: config.textPos ?? TextPos.below,
                isExpanded: true,
                onChanged: (value) => setState(() => config.textPos = value!),
                items: TextPos.values
                    .map((e) => DropdownMenuItem<TextPos>(
                        value: e, child: Text(e.name)))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],

            SizeField(
              initialValue: config.size,
              onChanged: (v) => setState(() => config.size = v),
            ),
            const SizedBox(height: 16),

            CoordinatesField(
              initialValue: config.coordinates,
              onChanged: (c) => setState(() => config.coordinates = c),
              enableAngle: true,
            ),
            const SizedBox(height: 16),
            const Divider(),

            // -- Children --
            // The parts of a third-party machine we DO have signals for get
            // their real asset instead of a painted approximation: a conveyor
            // driven by its actual drive frequency, a sensor on the infeed.
            // Positions are fractions of the machine area, so a child stays
            // on its lane at any asset size.
            Text('Inside the box',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              config.kind == ThirdPartyEquipmentKind.speedBatcher
                  ? 'The SpeedBatcher station is fixed: two checkweigher '
                      'belts with weight and accept-rate readouts. Point '
                      'each one at its tag with Configure below.'
                  : 'Place live assets over the drawing — e.g. a Conveyor '
                      'on an infeed lane, driven by its real frequency.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (config.kind == ThirdPartyEquipmentKind.speedBatcher)
                  // The SpeedBatcher station is static: its checkweigher
                  // belts and readouts are the scaffold and nothing else
                  // belongs in the box, so the free-form add buttons are
                  // withheld for this kind. This button only recovers the
                  // scaffold if the children were removed.
                  FilledButton.icon(
                    onPressed: _addStationScaffold,
                    icon: const Icon(Icons.auto_awesome_motion, size: 18),
                    label: const Text('Build checkweighers'),
                  )
                else ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _addChild(
                        thirdPartyNumber(units: '', decimalPlaces: 1),
                        keepUpright: true),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Readout'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _addChild(thirdPartyConveyor()),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Conveyor'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _addChild(SensorConfig.preview()),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Sensor'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // One angle for every readout in the box. Zero keeps them level
            // on screen whatever angle the machine is placed at.
            Row(
              children: [
                const Expanded(child: Text('Readout angle')),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    initialValue: config.childTextAngle.toStringAsFixed(0),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      suffixText: '°',
                      isDense: true,
                      helperText: '0 = level',
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null) {
                        setState(() => config.childTextAngle = parsed);
                      }
                    },
                  ),
                ),
              ],
            ),
            if (config.kind == ThirdPartyEquipmentKind.speedBatcher) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Accept rate window')),
                  SizedBox(
                    width: 90,
                    child: TextFormField(
                      initialValue: '${config.acceptWindowMinutes}',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        suffixText: 'min',
                        isDense: true,
                      ),
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        if (parsed != null && parsed > 0) {
                          setState(() => config.acceptWindowMinutes = parsed);
                        }
                      },
                    ),
                  ),
                ],
              ),
              Text(
                'Shown in the readout units, so nobody reads a rolling '
                'average as the last pack. Change it before building the '
                'checkweighers.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Clock-aligned accept bars'),
                subtitle: Text(
                  config.acceptBarsClockAligned
                      ? 'Bars sit on the clock — a 10 min interval buckets at '
                          ':00, :10, :20'
                      : 'Bars are measured back from now, so they slide with '
                          'every refresh',
                ),
                value: config.acceptBarsClockAligned,
                onChanged: (v) => setState(() {
                  config.acceptBarsClockAligned = v;
                  config.applyAcceptReadoutSettings();
                }),
              ),
            ],
            const SizedBox(height: 8),
            if (config.children.isEmpty)
              Text('Nothing placed inside',
                  style: Theme.of(context).textTheme.bodyMedium)
            else
              for (int i = 0; i < config.children.length; i++)
                _ChildRow(
                  key: ValueKey(config.children[i].id),
                  entry: config.children[i],
                  onChanged: () => setState(() {}),
                  onRemove: () => setState(() => config.children.removeAt(i)),
                ),
          ],
        ),
      ),
    );
  }

  void _addChild(BaseAsset child, {bool keepUpright = false}) {
    setState(() {
      widget.config.children
          .add(ThirdPartyChildEntry(child: child, keepUpright: keepUpright));
    });
  }

  /// Drops in a bidirectional conveyor plus weight and accept-rate readouts
  /// for each checkweigher, positioned on the drawing. Additive — pressing it
  /// twice stacks a second set rather than silently replacing what is there,
  /// so nothing an operator configured gets thrown away by a stray tap.
  void _addStationScaffold() {
    setState(() {
      widget.config.children.addAll(buildSpeedBatcherStationChildren(
        acceptWindowMinutes: widget.config.acceptWindowMinutes,
        acceptBarsClockAligned: widget.config.acceptBarsClockAligned,
      ));
    });
  }
}

/// One row of the children list: what it is, where it sits, and how to
/// configure or remove it.
class _ChildRow extends StatelessWidget {
  const _ChildRow({
    super.key,
    required this.entry,
    required this.onChanged,
    required this.onRemove,
  });

  final ThirdPartyChildEntry entry;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(entry.child.displayName,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  tooltip: 'Configure',
                  icon: const Icon(Icons.tune, size: 18),
                  onPressed: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        child: SingleChildScrollView(
                          child: entry.child.configure(context),
                        ),
                      ),
                    );
                    onChanged();
                  },
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onRemove,
                ),
              ],
            ),
            // Position within the machine area, 0..1 on each axis.
            _OffsetSlider(
              label: 'X',
              value: entry.offsetX,
              onChanged: (v) {
                entry.offsetX = v;
                onChanged();
              },
            ),
            _OffsetSlider(
              label: 'Y',
              value: entry.offsetY,
              onChanged: (v) {
                entry.offsetY = v;
                onChanged();
              },
            ),
            // Readouts stay level; machinery turns with the machine.
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Keep level when the machine is rotated'),
              value: entry.keepUpright,
              onChanged: (v) {
                entry.keepUpright = v ?? false;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The x/y pair that places a machine's plan view. A one-character label ('X',
/// 'Y') and a fraction of the bounding box, so it reads as a coordinate rather
/// than a percentage.
class _OffsetSlider extends StatelessWidget {
  const _OffsetSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return NumberSlider(
      label: label,
      labelWidth: 16,
      value: value.clamp(0.0, 1.0),
      min: 0.0,
      max: 1.0,
      divisions: 100,
      decimals: 2,
      onChanged: onChanged,
    );
  }
}
