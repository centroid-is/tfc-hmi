import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A [StreamBuilder] whose stream is created once and kept across rebuilds.
///
/// `StreamBuilder(stream: makeStream())` inside `build` hands the builder a
/// new stream object on every rebuild, and it answers a new object by
/// cancelling the old subscription and starting over in `waiting` -- one
/// frame of "no data" per rebuild, visible as a flicker (LEDs all low, a
/// button at its resting colour, a pane saying "Connecting"), and a
/// subscription churned for nothing.
///
/// The caller still builds [stream] in `build` -- that is where
/// `ref.watch(keyStreamProvider(...))` has to run, so the auto-disposed
/// provider stays alive and the source streams stay the same objects -- but
/// only the first stream object is listened to; later ones are ignored until
/// [keys] change (by [listEquals]). Put the source streams themselves in
/// [keys]: when Riverpod hands out a different source (the connection was
/// replaced), the wrapper is rebuilt around it.
class MemoStreamBuilder<T> extends StatefulWidget {
  const MemoStreamBuilder({
    super.key,
    required this.stream,
    required this.builder,
    this.keys = const [],
    this.initialData,
  });

  final Stream<T> stream;
  final AsyncWidgetBuilder<T> builder;

  /// Take the new [stream] when these change; keep the old one otherwise.
  final List<Object?> keys;
  final T? initialData;

  @override
  State<MemoStreamBuilder<T>> createState() => _MemoStreamBuilderState<T>();
}

class _MemoStreamBuilderState<T> extends State<MemoStreamBuilder<T>> {
  late Stream<T> _stream = widget.stream;

  @override
  void didUpdateWidget(covariant MemoStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.keys, widget.keys)) {
      _stream = widget.stream;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _stream,
      initialData: widget.initialData,
      builder: widget.builder,
    );
  }
}
