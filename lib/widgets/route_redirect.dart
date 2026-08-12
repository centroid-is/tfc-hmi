import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';

/// Beams straight to [target] instead of rendering anything.
///
/// Registered as the "page" for paths that must refuse direct navigation —
/// `/` when the Home page has been deleted, or an unpublished (draft) page's
/// path — so typing an address or following a stale link lands the operator
/// on a real page instead of a dead not-found screen.
class RouteRedirect extends StatefulWidget {
  const RouteRedirect({super.key, required this.target});

  /// The path to land on instead.
  final String target;

  @override
  State<RouteRedirect> createState() => _RouteRedirectState();
}

class _RouteRedirectState extends State<RouteRedirect> {
  @override
  void initState() {
    super.initState();
    // Beaming rebuilds the router, which cannot happen during this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Beamer.of(context).beamToReplacementNamed(widget.target);
    });
  }

  @override
  Widget build(BuildContext context) {
    // On screen for a single frame at most.
    return const Scaffold(body: SizedBox.shrink());
  }
}
