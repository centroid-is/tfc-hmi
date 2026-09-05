/// The USB-A sockets on a CX front panel.
///
/// Was two nested rectangles, which at mimic scale is indistinguishable from
/// any other rectangular hole on the machine. A USB-A port is told apart by
/// the white insulator tongue with its four contacts down one wall inside a
/// bright metal shroud, so that is what [paintUsbA] draws and this is the
/// [CustomPainter] shim over it.
library;

import 'package:flutter/material.dart';

import 'hardware.dart';

// Usage example widget
class USBIconWidget extends StatelessWidget {
  final double size;
  const USBIconWidget({super.key, this.size = 100.0});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * usbPortDesign.width / usbPortDesign.height, size),
      painter: const UsbPortPainter(),
    );
  }
}

/// The socket's design box — 24 x 52, kept from the drawing this replaced so
/// every caller's `canvas.scale(w / 24, h / 52)` still lands where it did.
const Size usbPortDesign = Size(24, 52);

class UsbPortPainter extends CustomPainter {
  final double strokeWidthPx;

  const UsbPortPainter({this.strokeWidthPx = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    paintUsbA(canvas, Rect.fromLTWH(0, 0, size.width, size.height));
  }

  @override
  bool shouldRepaint(covariant UsbPortPainter oldDelegate) =>
      oldDelegate.strokeWidthPx != strokeWidthPx;
}
