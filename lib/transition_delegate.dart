import 'package:flutter/material.dart';

class MyNoAnimationTransitionDelegate extends TransitionDelegate<void> {
  const MyNoAnimationTransitionDelegate();

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord?>
        locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>>
        pageRouteToPagelessRoutes,
  }) {
    final List<RouteTransitionRecord> results = <RouteTransitionRecord>[];

    // Handle exiting routes
    locationToExitingPageRoute.forEach((_, exitingPageRoute) {
      if (exitingPageRoute != null &&
          exitingPageRoute.isWaitingForExitingDecision) {
        exitingPageRoute.markForRemove();
        results.add(exitingPageRoute);
      }
    });

    // Handle entering routes
    for (final RouteTransitionRecord pageRoute in newPageRouteHistory) {
      if (pageRoute.isWaitingForEnteringDecision) {
        pageRoute.markForAdd();
      }
      results.add(pageRoute);
    }

    return results;
  }
}
