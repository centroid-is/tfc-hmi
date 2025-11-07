import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tfc/page_creator/assets/button.dart';
import 'package:tfc/page_creator/assets/common.dart';
import 'package:tfc/core/state_man.dart';
import 'package:tfc/providers/state_man.dart';
import 'package:tfc/providers/preferences.dart';
import 'package:tfc/widgets/dynamic_value.dart';
import 'package:tfc/converter/dynamic_value_converter.dart';

import 'package:open62541/open62541.dart' show DynamicValue;

part 'recipes.g.dart';

@JsonSerializable()
class RecipesConfig extends BaseAsset {
  String key;
  String label;

  RecipesConfig({
    required this.key,
    required this.label,
  });

  factory RecipesConfig.fromJson(Map<String, dynamic> json) => _$RecipesConfigFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$RecipesConfigToJson(this);

  @override
  Widget build(BuildContext context) => Recipes(config: this);

  static const previewStr = 'Recipes preview';

  RecipesConfig.preview()
      : key = '',
        label = 'Line';

  @override
  Widget configure(BuildContext context) => _RecipesConfigEditor(config: this);
}

@JsonSerializable()
class Recipe {
  String name;
  @DynamicValueConverter()
  DynamicValue value;

  Recipe({required this.name, required this.value});

  factory Recipe.fromJson(Map<String, dynamic> json) => _$RecipeFromJson(json);
  Map<String, dynamic> toJson() => _$RecipeToJson(this);
}

class _RecipesConfigEditor extends StatefulWidget {
  final RecipesConfig config;
  const _RecipesConfigEditor({required this.config});

  @override
  State<_RecipesConfigEditor> createState() => _RecipesConfigEditorState();
}

class _RecipesConfigEditorState extends State<_RecipesConfigEditor> {
  late TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.config.label);
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyField(
            initialValue: widget.config.key,
            onChanged: (val) => setState(() => widget.config.key = val),
          ),
          SizedBox(height: 16),
          Text('Label', style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _labelController,
            onChanged: (val) => setState(() => widget.config.label = val),
          ),
          SizedBox(height: 10),
          SizeField(initialValue: widget.config.size, onChanged: (size) => setState(() => widget.config.size = size)),
        ],
      ),
    );
  }
}

class PillText extends StatelessWidget {
  final String text;
  final bool selected;
  final TextStyle? selectedStyle;
  final TextStyle? unselectedStyle;
  final EdgeInsetsGeometry padding;
  final Color? selectedColor;

  const PillText({
    super.key,
    required this.text,
    required this.selected,
    this.selectedStyle,
    this.unselectedStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: selected
          ? BoxDecoration(
              color: selectedColor,
              borderRadius: BorderRadius.circular(30),
            )
          : null,
      padding: padding,
      child: Text(
        text,
        style: selected
            ? selectedStyle ?? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
            : unselectedStyle ?? Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class Recipes extends ConsumerStatefulWidget {
  final RecipesConfig config;
  const Recipes({super.key, required this.config});

  @override
  ConsumerState<Recipes> createState() => _RecipesState();
}

class _RecipesState extends ConsumerState<Recipes> {
  int selectedLine = 0;
  int? selectedRecipeIndex;
  final _newRecipeNameController = TextEditingController();

  Future<List<Recipe>> _getRecipes() async {
    final prefs = await ref.read(preferencesProvider.future);
    final prefKey = '${widget.config.key}.recipes';
    if (!(await prefs.containsKey(prefKey))) {
      var recipes = <Recipe>[];
      await prefs.setString(prefKey, jsonEncode(recipes));
    }
    final str = await prefs.getString(prefKey);
    final decoded = jsonDecode(str ?? '[]') as List<dynamic>;
    final recipes = decoded.map((item) => Recipe.fromJson(item)).toList();

    return recipes;
  }

  Future<void> _saveRecipes(List<Recipe> recipes) async {
    final prefs = await ref.watch(preferencesProvider.future);
    final prefKey = '${widget.config.key}.recipes';
    await prefs.setString(prefKey, jsonEncode(recipes));
  }

  void _addRecipe(String name, List<Recipe> recipes, DynamicValue data, void Function(VoidCallback) setState) {
    final initial = <String, dynamic>{};
    data.asObject.forEach((k, v) => initial[k] = v.value);
    setState(() {
      recipes.add(Recipe(name: name, value: data));
      _newRecipeNameController.clear();
      _saveRecipes(recipes);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDialog(context),
      child: CustomPaint(
        painter: ButtonPainter(
          color: Theme.of(context).colorScheme.primary,
          isPressed: false,
          buttonType: ButtonType.square,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                "Recipes",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogContent(StateMan stateMan, DynamicValue data, List<Recipe> recipes) {
    return StatefulBuilder(builder: (dialogContext, dialogSetState) {
      return AlertDialog(
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 1000, maxHeight: 700),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Lines
              Container(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(data.asArray.length, (i) {
                    final selected = i == selectedLine;
                    return InkWell(
                      onTap: () => dialogSetState(() {
                        selectedLine = i;
                        selectedRecipeIndex = null;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: PillText(
                          text: '${widget.config.label} ${i + 1}',
                          selected: selected,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              VerticalDivider(),
              // Recipes list
              Container(
                width: 200,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double listMaxHeight = constraints.maxHeight * 0.6;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recipes', style: Theme.of(context).textTheme.titleMedium),
                          Divider(),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: listMaxHeight),
                            child: ListView(
                              shrinkWrap: true,
                              children: List.generate(recipes.length, (r) {
                                final recipe = recipes[r];
                                final selected = r == selectedRecipeIndex;
                                return Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.delete),
                                      onPressed: () => dialogSetState(() {
                                        recipes.removeAt(r);
                                        selectedRecipeIndex = null;
                                        _saveRecipes(recipes);
                                      }),
                                    ),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => dialogSetState(() {
                                          selectedRecipeIndex = r;
                                        }),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                                          child: PillText(
                                            text: recipe.name,
                                            selected: selected,
                                            selectedStyle:
                                                const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                                            unselectedStyle: const TextStyle(color: Colors.grey),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: TextField(
                              controller: _newRecipeNameController,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'New recipe',
                              ),
                              onSubmitted: (v) => _addRecipe(v, recipes, data[selectedLine], dialogSetState),
                            ),
                          ),
                          Center(
                            child: ElevatedButton.icon(
                              icon: Icon(Icons.add),
                              label: Text('Add recipe'),
                              onPressed: () => _addRecipe(
                                  _newRecipeNameController.text, recipes, data[selectedLine], dialogSetState),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              VerticalDivider(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recipe values', style: Theme.of(context).textTheme.titleMedium),
                      Divider(),
                      if (selectedRecipeIndex != null)
                        DynamicValueWidget(
                          value: recipes[selectedRecipeIndex!].value,
                          onSubmitted: (v) => dialogSetState(() {
                            recipes[selectedRecipeIndex!].value = v;
                            print(recipes[selectedRecipeIndex!].value);
                            _saveRecipes(recipes);
                          }),
                        ),
                      Spacer(),
                      Row(
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              var newValue = DynamicValue.from(data);
                              newValue[selectedLine] = DynamicValue.from(recipes[selectedRecipeIndex!].value);
                              await stateMan.write(widget.config.key, newValue);
                            },
                            child: Text('Send values ->'),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              VerticalDivider(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Current values', style: Theme.of(context).textTheme.titleMedium),
                      Divider(),
                      DynamicValueWidget(
                        value: data[selectedLine],
                      ),
                      Spacer(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => StreamBuilder<(StateMan, DynamicValue)>(
        stream: ref.watch(stateManProvider.future).asStream().switchMap((stateMan) => stateMan
            .subscribe(widget.config.key)
            .asStream()
            .map((stream) => Rx.combineLatest2(Stream.value(stateMan), stream, (stateMan, value) => (stateMan, value)))
            .switchMap((stream) => stream)),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AlertDialog(
              content: Text('Error loading recipes: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          final (stateMan, data) = snapshot.data!;
          if (!data.isArray) {
            return Center(child: Text('Unsupported type: ${data.type}, needs to be an array'));
          }

          return FutureBuilder<List<Recipe>>(
            future: _getRecipes(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AlertDialog(
                  content: Text('Error loading recipes: ${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }
              final recipes = snapshot.data!;
              return _dialogContent(stateMan, data, recipes);
            },
          );
        },
      ),
    );
  }
}
