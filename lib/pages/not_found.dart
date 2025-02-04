import 'package:flutter/material.dart';
import 'package:beamer/beamer.dart';
import '../widgets/base_scaffold.dart';

class PageNotFound extends StatelessWidget {
  const PageNotFound({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Maybe show the path used
    var actions = <Widget>[
      TextButton(
          onPressed: () => context.beamToNamed('/'),
          child: const Text('Go home')),
    ];
    if (context.canBeamBack) {
      actions.add(FilledButton(
          onPressed: () => context.beamBack(), child: const Text('Go back')));
    }
    return BaseScaffold(
      title: 'Not found',
      body: AlertDialog(
        icon: const Icon(Icons.error),
        title: const Text('Page not found'),
        content: const Text(
            'The page requested could not be found, please navigate back and try again'),
        actions: actions,
      ),
    );
  }
}
