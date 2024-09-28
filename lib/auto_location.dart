// lib/auto_location.dart
import 'package:beamer/beamer.dart';
import 'package:flutter/material.dart';
import 'route_registry.dart';
import 'widgets/beam_page_scaffold.dart';
import 'models/menu_item.dart';

class AutoLocation extends BeamLocation<BeamState> {
  AutoLocation({RouteInformation? state}) : super(state);

  @override
  List<String> get pathPatterns => ['/.*'];

  @override
  List<BeamPage> buildPages(BuildContext context, BeamState state) {
    final registry = RouteRegistry();
    final uri = state.uri;
    final path = uri.path;

    WidgetBuilder? builder = registry.getBuilder(path);

    if (builder != null) {
      // Retrieve navigation items from the registry or pass them as needed
      List<MenuItem> dropdownMenuItems = registry.dropdownMenuItems;
      List<MenuItem> standardMenuItems = registry.standardMenuItems;

      return [
        BeamPage(
          key: ValueKey(path),
          title: path,
          child: BeamPageScaffold(
            title: 'My App', // Or retrieve from the route
            currentIndex: 0, // Determine based on the path or other logic
            dropdownMenuItems: dropdownMenuItems,
            standardMenuItems: standardMenuItems,
            child: builder(context),
          ),
        ),
      ];
    } else {
      return [
        BeamPage(
          key: ValueKey('not-found'),
          title: 'Page Not Found',
          child: BeamPageScaffold(
            title: 'My App',
            currentIndex: 0,
            dropdownMenuItems: registry.dropdownMenuItems,
            standardMenuItems: registry.standardMenuItems,
            child: Scaffold(
              body: Center(
                child: Text('404 - Page Not Found'),
              ),
            ),
          ),
        ),
      ];
    }
  }
}
