// Stub — Task 2 of Plan 01-02 implements the real STBDDI3725BodyPainter +
// STBDDI3725Widget. This stub exists only so the Task 1 import in
// `lib/page_creator/assets/advantys_stb.dart` resolves during codegen +
// data-shape test runs.

import 'package:flutter/widgets.dart';
import 'package:tfc/painter/beckhoff/io8.dart' show IOState;

class STBDDI3725Widget extends StatelessWidget {
  final List<IOState> ledStates;
  final bool isStale;
  final bool isDisconnected;
  final Animation<int> animation;
  final double height;

  const STBDDI3725Widget({
    super.key,
    required this.ledStates,
    required this.isStale,
    required this.isDisconnected,
    required this.animation,
    this.height = 300,
  });

  @override
  Widget build(BuildContext context) {
    // Task 2 replaces this stub.
    return SizedBox(width: height * (107 / 152), height: height);
  }
}
