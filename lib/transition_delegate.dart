import 'package:flutter/material.dart';

class MyNoAnimationTransitionDelegate extends TransitionDelegate<void> {
  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord>
        locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>>
        pageRouteToPagelessRoutes,
  }) {
    final results = <RouteTransitionRecord>[];

    // Recursively handle any exiting route that sat *below* [location]
    void handleExiting(RouteTransitionRecord? location, bool isLast) {
      final exiting = locationToExitingPageRoute[location];
      if (exiting == null) return;

      // Only call markForComplete/remove if it actually needs it
      if (exiting.isWaitingForExitingDecision) {
        exiting.markForComplete(exiting.route.currentResult);
        for (final pl in pageRouteToPagelessRoutes[exiting] ?? []) {
          if (pl.isWaitingForExitingDecision) {
            pl.markForComplete(pl.route.currentResult);
          }
        }
      }

      results.add(exiting);
      // There may be another exiting *above* this one
      handleExiting(
          exiting, isLast && !locationToExitingPageRoute.containsKey(exiting));
    }

    // 1️⃣ Handle anything exiting *before* the very first new page
    handleExiting(null, newPageRouteHistory.isEmpty);

    // 2️⃣ Now interleave: for each new page, add it then handle whoever was exiting under it
    for (var i = 0; i < newPageRouteHistory.length; i++) {
      final page = newPageRouteHistory[i];
      final isLast = i == newPageRouteHistory.length - 1;

      if (page.isWaitingForEnteringDecision) {
        // no push animation, just slap it on
        page.markForAdd();
      }
      results.add(page);

      handleExiting(page, isLast);
    }

    return results;
  }
}
