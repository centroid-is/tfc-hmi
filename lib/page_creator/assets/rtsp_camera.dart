/// A live RTSP camera view on the page.
///
/// Playback is media_kit (libmpv), which is what actually plays RTSP on the
/// desktop platforms (macOS/Windows/Linux — Linux needs the distro's libmpv
/// package at runtime). Platforms without the native pieces — the
/// flutter-elinux stations, `flutter test` — get a "playback unavailable"
/// placeholder instead of a crash: the player is only constructed inside a
/// try/catch, never at import time.
///
/// A dropped stream retries on its own every [RtspCameraView.retryDelay]; an
/// operator should never have to touch a camera tile to bring it back.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../theme.dart';
import 'common.dart';

part 'rtsp_camera.g.dart';

@JsonSerializable(explicitToJson: true)
class RtspCameraConfig extends BaseAsset {
  @override
  String get displayName => 'RTSP camera';
  @override
  String get category => 'Visualization';
  @override
  List<String> get searchKeywords =>
      const ['camera', 'video', 'cctv', 'stream', 'surveillance'];

  /// Stream URL, e.g. `rtsp://user:pass@10.0.0.5:554/stream1`. Empty means
  /// not configured yet and renders a placeholder.
  String url;

  BoxFit fit;

  /// Plant cameras rarely carry useful audio, and eight tiles of compressor
  /// hum would be a nuisance — sound is opt-in.
  bool muted;

  RtspCameraConfig({
    this.url = '',
    this.fit = BoxFit.cover,
    this.muted = true,
  }) {
    size = const RelativeSize(width: 0.2, height: 0.15);
  }

  RtspCameraConfig.preview()
      : url = '',
        fit = BoxFit.cover,
        muted = true {
    size = const RelativeSize(width: 0.2, height: 0.15);
  }

  factory RtspCameraConfig.fromJson(Map<String, dynamic> json) =>
      _$RtspCameraConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$RtspCameraConfigToJson(this);

  @override
  Widget build(BuildContext context) => RtspCameraView(config: this);

  @override
  Widget configure(BuildContext context) =>
      _RtspCameraConfigEditor(config: this);
}

enum RtspCameraStatus { connecting, live, noSignal }

/// What [RtspCameraView] needs from a video backend, so tests (and platforms
/// where libmpv cannot load) never touch media_kit.
abstract class RtspCameraPlayback {
  ValueListenable<RtspCameraStatus> get status;
  Widget buildVideo(BuildContext context, BoxFit fit);
  Future<void> dispose();
}

class RtspCameraView extends StatefulWidget {
  final RtspCameraConfig config;
  const RtspCameraView({super.key, required this.config});

  /// How long a dead stream waits before reopening.
  static const Duration retryDelay = Duration(seconds: 5);

  /// Test hook: replaces the media_kit backend. Reset to null in tearDown.
  @visibleForTesting
  static RtspCameraPlayback Function(RtspCameraConfig config)?
      debugPlaybackFactory;

  @override
  State<RtspCameraView> createState() => _RtspCameraViewState();
}

class _RtspCameraViewState extends State<RtspCameraView> {
  RtspCameraPlayback? _playback;

  /// libmpv failed to load (or the player failed to construct) — a permanent
  /// condition on this platform, not a stream drop, so no retry.
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(RtspCameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.url != widget.config.url ||
        oldWidget.config.muted != widget.config.muted) {
      _close();
      _open();
    }
  }

  void _open() {
    if (widget.config.url.isEmpty) return;
    try {
      _playback = (RtspCameraView.debugPlaybackFactory ??
          _MediaKitPlayback.new)(widget.config);
    } catch (_) {
      _unavailable = true;
    }
  }

  void _close() {
    unawaited(_playback?.dispose().catchError((_) {}));
    _playback = null;
    _unavailable = false;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playback = _playback;
    final Widget content;
    if (widget.config.url.isEmpty) {
      content = _Glyph(icon: Icons.videocam_outlined);
    } else if (_unavailable || playback == null) {
      content = Tooltip(
        message: 'Video playback is not available on this platform',
        child: _Glyph(icon: Icons.videocam_off_outlined),
      );
    } else {
      content = ValueListenableBuilder<RtspCameraStatus>(
        valueListenable: playback.status,
        builder: (context, status, _) => Stack(
          fit: StackFit.expand,
          children: [
            playback.buildVideo(context, widget.config.fit),
            if (status == RtspCameraStatus.connecting)
              const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (status == RtspCameraStatus.noSignal)
              _Glyph(icon: Icons.videocam_off_outlined, caption: 'No signal'),
            if (status == RtspCameraStatus.live)
              Positioned(left: 6, bottom: 6, child: _LiveBadge()),
          ],
        ),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // Video letterbox ground; the glyph states inherit it so a wall of
        // camera tiles reads uniformly whether or not streams are up.
        color: Colors.black87,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: content,
    );
  }
}

/// Centered icon (plus optional caption) sized off the box like the image
/// asset's placeholder — a glyph is a font glyph, scaling it via FittedBox
/// would resample it like text.
class _Glyph extends StatelessWidget {
  final IconData icon;
  final String? caption;
  const _Glyph({required this.icon, this.caption});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final shortest = constraints.biggest.shortestSide;
      final side = shortest.isFinite && shortest > 0 ? shortest : 48.0;
      final iconSide = caption == null ? side * 0.6 : side * 0.45;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSide.clamp(16.0, 96.0), color: Colors.white38),
            if (caption != null && side >= 72) ...[
              const SizedBox(height: 4),
              Text(
                caption!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.white38),
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// Small "LIVE" chip: muted running-green dot (the fleet's "in operation"
/// color — saturated red stays reserved for faults) on a translucent scrim.
class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final running = HmiStateColors.of(context).green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: running, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          const Text(
            'LIVE',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}

/// The real backend. Construction throws where libmpv cannot load — the view
/// catches that and shows the unavailable placeholder.
class _MediaKitPlayback implements RtspCameraPlayback {
  static bool _initialized = false;

  final Player _player;
  late final VideoController _controller;
  final _status = ValueNotifier<RtspCameraStatus>(RtspCameraStatus.connecting);
  final _subscriptions = <StreamSubscription<void>>[];
  final String _url;
  Timer? _retryTimer;
  bool _disposed = false;

  _MediaKitPlayback(RtspCameraConfig config)
      : _url = config.url,
        _player = _construct() {
    _controller = VideoController(_player);
    if (config.muted) {
      unawaited(_player.setVolume(0).catchError((_) {}));
    }
    _subscriptions.add(_player.stream.error.listen((_) => _onDead()));
    // A finished stream is a dead camera feed, not a completed movie.
    _subscriptions.add(_player.stream.completed.listen((completed) {
      if (completed) _onDead();
    }));
    // Width flips non-null when frames actually decode — "connected" at the
    // socket level is not a picture.
    _subscriptions.add(_player.stream.width.listen((width) {
      if (width != null && width > 0 && !_disposed) {
        _status.value = RtspCameraStatus.live;
      }
    }));
    _openMedia();
  }

  static Player _construct() {
    if (!_initialized) {
      MediaKit.ensureInitialized();
      _initialized = true;
    }
    return Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
    );
  }

  void _openMedia() {
    _status.value = RtspCameraStatus.connecting;
    unawaited(_player.open(Media(_url), play: true).catchError((_) {
      _onDead();
    }));
  }

  void _onDead() {
    if (_disposed) return;
    _status.value = RtspCameraStatus.noSignal;
    _retryTimer ??= Timer(RtspCameraView.retryDelay, () {
      _retryTimer = null;
      if (!_disposed) _openMedia();
    });
  }

  @override
  ValueListenable<RtspCameraStatus> get status => _status;

  @override
  Widget buildVideo(BuildContext context, BoxFit fit) => Video(
        controller: _controller,
        fit: fit,
        controls: NoVideoControls,
        // The HMI never sleeps; skip the wakelock plugin round-trip.
        wakelock: false,
      );

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _status.dispose();
    await _player.dispose();
  }
}

class _RtspCameraConfigEditor extends StatefulWidget {
  final RtspCameraConfig config;
  const _RtspCameraConfigEditor({required this.config});

  @override
  State<_RtspCameraConfigEditor> createState() =>
      _RtspCameraConfigEditorState();
}

class _RtspCameraConfigEditorState extends State<_RtspCameraConfigEditor> {
  RtspCameraConfig get config => widget.config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: config.url,
            decoration: const InputDecoration(
              labelText: 'Stream URL',
              hintText: 'rtsp://user:pass@10.0.0.5:554/stream1',
            ),
            onChanged: (value) => setState(() => config.url = value.trim()),
          ),
          const SizedBox(height: 16),
          Text('Fit', style: theme.textTheme.titleMedium),
          DropdownButton<BoxFit>(
            value: config.fit,
            isExpanded: true,
            onChanged: (value) => setState(() => config.fit = value!),
            items: const [BoxFit.cover, BoxFit.contain, BoxFit.fill]
                .map((f) =>
                    DropdownMenuItem<BoxFit>(value: f, child: Text(f.name)))
                .toList(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Muted'),
            value: config.muted,
            onChanged: (value) => setState(() => config.muted = value),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: config.text,
            decoration: const InputDecoration(labelText: 'Label'),
            onChanged: (value) => setState(() => config.text = value),
          ),
          const SizedBox(height: 8),
          DropdownButton<TextPos>(
            value: config.textPos,
            hint: const Text('Label position'),
            isExpanded: true,
            onChanged: (value) => setState(() => config.textPos = value),
            items: TextPos.values
                .map((e) =>
                    DropdownMenuItem<TextPos>(value: e, child: Text(e.name)))
                .toList(),
          ),
          const SizedBox(height: 16),
          SizeField(
            initialValue: config.size,
            onChanged: (size) => setState(() => config.size = size),
          ),
          const SizedBox(height: 16),
          CoordinatesField(
            initialValue: config.coordinates,
            onChanged: (c) => setState(() => config.coordinates = c),
          ),
        ],
      ),
    );
  }
}
