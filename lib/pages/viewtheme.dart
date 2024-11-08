import 'package:flutter/material.dart';
import 'package:tfc_hmi/theme.dart';
import '../widgets/base_scaffold.dart';

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
                      labelText: 'What is this?',
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
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: TextField(
                    decoration: InputDecoration(
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
                ElevatedButton(
                  onPressed: () {
                    showDialog(
                        context: context,
                        builder: (context) => const Text("HEY!"));
                  },
                  child: const Text('ElevatedButton non primary'),
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
                ShowTextOnBackgrounds('Yellow', SolarizedColors().yellow,
                    SolarizedColors().base03),
                ShowTextOnBackgrounds(
                    'Red', SolarizedColors().red, SolarizedColors().base03),
                ShowTextOnBackgrounds(
                    'Green', SolarizedColors().green, SolarizedColors().base03),
                ShowTextOnBackgrounds(
                    'Blue', SolarizedColors().blue, SolarizedColors().base03),
                ShowTextOnBackgrounds('Orange', SolarizedColors().orange,
                    SolarizedColors().base03),
                ShowTextOnBackgrounds('Violet', SolarizedColors().violet,
                    SolarizedColors().base03),
                ShowTextOnBackgrounds('Magenta', SolarizedColors().magenta,
                    SolarizedColors().base03),
                ShowTextOnBackgrounds('Base 0', SolarizedColors().base0,
                    SolarizedColors().base03),
                ShowTextOnBackgrounds('Base 1', SolarizedColors().base1,
                    SolarizedColors().base03),
                ShowTextOnBackgrounds('Base 2', SolarizedColors().base2,
                    SolarizedColors().base03),
                ShowTextOnBackgrounds('Base 3', SolarizedColors().base3,
                    SolarizedColors().base03),
                ShowTextOnBackgrounds('Base 00', SolarizedColors().base00,
                    SolarizedColors().base03),
                ShowTextOnBackgrounds('Base 01', SolarizedColors().base01,
                    SolarizedColors().base03),
                ShowTextOnBackgrounds('Base 02', SolarizedColors().base02,
                    SolarizedColors().base2),
                ShowTextOnBackgrounds('Base 03', SolarizedColors().base03,
                    SolarizedColors().base2),
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
      width: 300,
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
    final textTheme = Theme.of(context).textTheme.titleLarge;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      ContainerWPadding(
          oncolor, color, title, textTheme!.copyWith(color: color)),
      ContainerWPadding(
          color, oncolor, 'on$title', textTheme.copyWith(color: oncolor))
    ]);
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
