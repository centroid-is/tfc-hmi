import 'package:flutter/material.dart';
import '../widgets/base_scaffold.dart';
import '../theme.dart';

class ViewTheme extends StatelessWidget {
  const ViewTheme({super.key});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return BaseScaffold(
        title: 'Display Theme!',
        body: Row(
          children: [
            Expanded(
              child: ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Text('Input fields',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Outlined text field',
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: TextField(
                    decoration: InputDecoration(
                      border: UnderlineInputBorder(),
                      filled: true,
                      labelText: 'Filled text field',
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Disabled text input',
                    ),
                    enabled: false,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    maxLength: 1,
                    controller: TextEditingController.fromValue(
                        const TextEditingValue(text: 'ERROR!')),
                    decoration: const InputDecoration(
                      labelText: 'This should be in error TODO',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Text('Different buttons',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog(
                          context: context,
                          builder: (context) {
                            return const Dialog.fullscreen(child: Text('hi'));
                          });
                    },
                    child: const Text('ElevatedButton'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: FilledButton(
                    onPressed: () {
                      showDialog(
                          context: context,
                          builder: (context) =>
                              const AlertDialog(content: Text("HEY!")));
                    },
                    child: const Text('Filled Button'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: OutlinedButton(
                    onPressed: () {
                      showDialog(
                          context: context,
                          builder: (context) => const Text("HEY!"));
                    },
                    child: const Text('Outlined Button'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextButton(
                    onPressed: () {
                      showDialog(
                          context: context,
                          builder: (context) => const Text("HEY!"));
                    },
                    child: const Text('Text Button'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Text('Different text themes demo!',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ),
                DisplayTextTheme(Text('Label Small', style: tt.labelSmall)),
                DisplayTextTheme(Text('Label Medium', style: tt.labelMedium)),
                DisplayTextTheme(Text('Label Large', style: tt.labelLarge)),
                DisplayTextTheme(Text('Body Small', style: tt.bodySmall)),
                DisplayTextTheme(Text('Body Medium', style: tt.bodyMedium)),
                DisplayTextTheme(Text('Body Large', style: tt.bodyLarge)),
                DisplayTextTheme(Text('Title Small', style: tt.titleSmall)),
                DisplayTextTheme(Text('Title Medium', style: tt.titleMedium)),
                DisplayTextTheme(Text('Title Large', style: tt.titleLarge)),
                DisplayTextTheme(
                    Text('Headline Small', style: tt.headlineSmall)),
                DisplayTextTheme(
                    Text('Headline Medium', style: tt.headlineMedium)),
                DisplayTextTheme(
                    Text('Headline Large', style: tt.headlineLarge)),
                DisplayTextTheme(Text('Display Small', style: tt.displaySmall)),
                DisplayTextTheme(
                    Text('Display Medium', style: tt.displayMedium)),
                DisplayTextTheme(Text('Display Large', style: tt.displayLarge)),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Text('Cards',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Card.filled(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('Filled card'),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('Elevated card'),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Card.outlined(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('Outlined card'),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Text('Current Theme in use',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ),
                ShowTextOnBackgrounds(
                  'Primary',
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.onPrimary,
                  container: Theme.of(context).colorScheme.primaryContainer,
                  onContainer: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                ShowTextOnBackgrounds(
                  'Secondary',
                  Theme.of(context).colorScheme.secondary,
                  Theme.of(context).colorScheme.onSecondary,
                  container: Theme.of(context).colorScheme.secondaryContainer,
                  onContainer:
                      Theme.of(context).colorScheme.onSecondaryContainer,
                ),
                ShowTextOnBackgrounds(
                  'Error',
                  Theme.of(context).colorScheme.error,
                  Theme.of(context).colorScheme.onError,
                  container: Theme.of(context).colorScheme.errorContainer,
                  onContainer: Theme.of(context).colorScheme.onErrorContainer,
                ),
                ShowTextOnBackgrounds(
                  'Tertiary',
                  Theme.of(context).colorScheme.tertiary,
                  Theme.of(context).colorScheme.onTertiary,
                  container: Theme.of(context).colorScheme.tertiaryContainer,
                  onContainer:
                      Theme.of(context).colorScheme.onTertiaryContainer,
                ),
                ShowTextOnBackgrounds(
                  'Surface',
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.onSurface,
                  container: Theme.of(context).colorScheme.surfaceContainer,
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Text('Solarized dark colors',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ),
                const ShowTextOnBackgrounds(
                    'Yellow', SolarizedColors.yellow, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Red', SolarizedColors.red, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Green', SolarizedColors.green, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Blue', SolarizedColors.blue, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Orange', SolarizedColors.orange, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Violet', SolarizedColors.violet, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Magenta', SolarizedColors.magenta, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Base 0', SolarizedColors.base0, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Base 1', SolarizedColors.base1, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Base 2', SolarizedColors.base2, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Base 3', SolarizedColors.base3, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Base 00', SolarizedColors.base00, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Base 01', SolarizedColors.base01, SolarizedColors.base03),
                const ShowTextOnBackgrounds(
                    'Base 02', SolarizedColors.base02, SolarizedColors.base2),
                const ShowTextOnBackgrounds(
                    'Base 03', SolarizedColors.base03, SolarizedColors.base2),
              ]),
            ),
          ],
        ));
  }
}

class ContainerWPadding extends StatelessWidget {
  final Color background;
  final Color color;
  final String title;
  final TextStyle style;
  const ContainerWPadding(this.color, this.background, this.title, this.style,
      {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 70,
      decoration:
          BoxDecoration(border: Border.all(color: color), color: background),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(title, style: style.copyWith(color: color)),
      ),
    );
  }
}

class ShowTextOnBackgrounds extends StatelessWidget {
  final Color color;
  final Color oncolor;
  final Color? container;
  final Color? onContainer;
  final String title;
  const ShowTextOnBackgrounds(this.title, this.color, this.oncolor,
      {this.container, this.onContainer, super.key});
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
        ContainerWPadding(
            oncolor, color, title, textTheme!.copyWith(color: color)),
        ContainerWPadding(
            color, oncolor, 'on$title', textTheme.copyWith(color: oncolor)),
        container != null
            ? ContainerWPadding(oncolor, container!, '$title container',
                textTheme.copyWith(color: oncolor))
            : Container(),
        onContainer != null
            ? ContainerWPadding(color, onContainer!, '$title onContainer',
                textTheme.copyWith(color: oncolor))
            : Container(),
      ]),
    );
  }
}

class DisplayTextTheme extends StatelessWidget {
  final Text t;
  const DisplayTextTheme(this.t, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: t,
    );
  }
}
