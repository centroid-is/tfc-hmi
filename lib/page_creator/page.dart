import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';
import 'assets/common.dart';
import 'assets/registry.dart';
import '../models/menu_item.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc/converter/icon.dart';

part 'page.g.dart';

@JsonSerializable()
class AssetPage {
  @JsonKey(name: 'menu_item')
  final MenuItem menuItem;
  @AssetListConverter()
  final List<Asset> assets;
  @JsonKey(name: 'mirroring_disabled')
  bool mirroringDisabled;
  @JsonKey(name: 'navigation_priority')
  int? navigationPriority;

  AssetPage(
      {required this.menuItem,
      required this.assets,
      required this.mirroringDisabled,
      this.navigationPriority});

  factory AssetPage.fromJson(Map<String, dynamic> json) =>
      _$AssetPageFromJson(json);
  Map<String, dynamic> toJson() => _$AssetPageToJson(this);
}

class AssetListConverter implements JsonConverter<List<Asset>, List<dynamic>> {
  const AssetListConverter();

  @override
  List<Asset> fromJson(List<dynamic> json) {
    return AssetRegistry.parse({'assets': json});
  }

  @override
  List<dynamic> toJson(List<Asset> assets) {
    return assets.map((asset) => asset.toJson()).toList();
  }
}

class PageManager {
  static const String storageKey = 'page_editor_data';
  Map<String, AssetPage> pages;
  final PreferencesApi prefs;

  PageManager({required this.pages, required this.prefs});

  Future<void> load() async {
    String? jsonString = await prefs.getString(storageKey);
    final defaultPages = {
      'Home': AssetPage(
        menuItem: const MenuItem(label: 'Home', path: '/', icon: Icons.home),
        assets: [],
        mirroringDisabled: false,
      ),
    };
    if (jsonString != null) {
      try {
        fromJson(jsonString);
        if (pages.isEmpty) {
          pages = defaultPages;
        }
      } catch (e) {
        pages = defaultPages;
      }
    } else {
      // some sane default
      jsonString = r'''
        {
          "Home": {
            "menu_item": {
              "label": "Home",
              "path": "/",
              "icon": "home",
              "children": []
            },
            "assets": [
              {
                "asset_name": "ButtonConfig",
                "coordinates": {
                  "x": 0.3062472475044039,
                  "y": 0.13612415997912186,
                  "angle": null
                },
                "size": {
                  "width": 0.03,
                  "height": 0.03
                },
                "text": "A button",
                "textPos": "right",
                "key": "Button preview",
                "feedback": null,
                "icon": null,
                "outward_color": {
                  "red": 0.2980392156862745,
                  "green": 0.6862745098039216,
                  "blue": 0.3137254901960784,
                  "alpha": 1.0
                },
                "inward_color": {
                  "red": 0.2980392156862745,
                  "green": 0.6862745098039216,
                  "blue": 0.3137254901960784,
                  "alpha": 1.0
                },
                "button_type": "circle",
                "is_toggle": false
              },
              {
                "asset_name": "LEDConfig",
                "coordinates": {
                  "x": 0.3060637477980035,
                  "y": 0.23322812683499702,
                  "angle": null
                },
                "size": {
                  "width": 0.03,
                  "height": 0.03
                },
                "text": "A light",
                "textPos": "right",
                "key": "Led preview",
                "on_color": {
                  "red": 0.2980392156862745,
                  "green": 0.6862745098039216,
                  "blue": 0.3137254901960784,
                  "alpha": 1.0
                },
                "off_color": {
                  "red": 0.2980392156862745,
                  "green": 0.6862745098039216,
                  "blue": 0.3137254901960784,
                  "alpha": 1.0
                },
                "led_type": "circle"
              },
              {
                "asset_name": "BeckhoffCX5010Config",
                "coordinates": {
                  "x": 0.5455216896652962,
                  "y": 0.602119625497488,
                  "angle": null
                },
                "size": {
                  "width": 0.5,
                  "height": 0.5
                },
                "text": null,
                "textPos": null,
                "subdevices": [
                  {
                    "asset_name": "BeckhoffEL1008Config",
                    "coordinates": {
                      "x": 0.0,
                      "y": 0.0,
                      "angle": null
                    },
                    "size": {
                      "width": 0.03,
                      "height": 0.03
                    },
                    "text": null,
                    "textPos": null,
                    "nameOrId": "1",
                    "descriptionsKey": null,
                    "rawStateKey": null,
                    "processedStateKey": null,
                    "forceValuesKey": null,
                    "onFiltersKey": null,
                    "offFiltersKey": null
                  },
                  {
                    "asset_name": "BeckhoffEL2008Config",
                    "coordinates": {
                      "x": 0.0,
                      "y": 0.0,
                      "angle": null
                    },
                    "size": {
                      "width": 0.03,
                      "height": 0.03
                    },
                    "text": null,
                    "textPos": null,
                    "nameOrId": "1",
                    "descriptionsKey": null,
                    "rawStateKey": null,
                    "forceValuesKey": null
                  }
                ]
              }
            ],
            "mirroring_disabled": false,
            "navigation_priority": 0
          }
        }
      ''';
      fromJson(jsonString);
      prefs.setString(storageKey, jsonString);
    }
  }

  Future<void> save() async {
    await prefs.setString(storageKey, toJson());
  }

  String toJson() {
    return jsonEncode(pages.map((name, page) => MapEntry(name, page.toJson())));
  }

  void fromJson(String jsonString) {
    pages = PageManager._fromJson(jsonString);
  }

  PageManager copyWith({
    Map<String, AssetPage>? otherPages,
  }) {
    final manager = PageManager(
      pages: otherPages ?? pages,
      prefs: prefs,
    );
    final json = manager.toJson();
    manager.fromJson(json);
    return manager;
  }

  static Map<String, AssetPage> copyPages(Map<String, AssetPage> otherPages) {
    final json = jsonEncode(
        otherPages.map((name, page) => MapEntry(name, page.toJson())));
    return _fromJson(json);
  }

  /// Returns fully resolved root menu items with children looked up
  /// from the flat map so nested sections have their actual children.
  List<MenuItem> getRootMenuItems() {
    final childLabels = <String>{};
    for (final entry in pages.entries) {
      collectChildLabels(entry.value.menuItem.children, childLabels, entry.key);
    }
    final rootNames = pages.keys
        .where((name) => !childLabels.contains(name))
        .toList();
    rootNames.sort((a, b) =>
        (pages[a]?.navigationPriority ?? 0)
            .compareTo(pages[b]?.navigationPriority ?? 0));
    return rootNames.map((name) => _resolveMenuItem(name)).toList();
  }

  /// Recursively resolves a page's MenuItem by looking up each child
  /// from the flat map to get its current children list.
  MenuItem _resolveMenuItem(String pageName) {
    final page = pages[pageName]!;
    final resolvedChildren = page.menuItem.children.map((child) {
      // Don't recurse into self-references
      if (child.label == pageName) return child;
      // Resolve from the flat map if the child exists there
      if (pages.containsKey(child.label)) {
        return _resolveMenuItem(child.label);
      }
      return child;
    }).toList();
    return MenuItem(
      label: page.menuItem.label,
      path: page.menuItem.path,
      icon: page.menuItem.icon,
      children: resolvedChildren,
    );
  }

  static void collectChildLabels(
      List<MenuItem> items, Set<String> labels, String excludeKey) {
    for (final item in items) {
      if (item.label != excludeKey) {
        labels.add(item.label);
      }
      collectChildLabels(item.children, labels, excludeKey);
    }
  }

  static Map<String, AssetPage> _fromJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return json.map((name, pageJson) => MapEntry(
          name,
          AssetPage.fromJson(pageJson as Map<String, dynamic>),
        ));
  }
}

class CreatePageWidget extends StatefulWidget {
  final AssetPage? initialPage;
  final Function(AssetPage) onSave;
  final bool isSection;
  final String basePath;

  const CreatePageWidget({
    super.key,
    this.initialPage,
    required this.onSave,
    this.isSection = false,
    this.basePath = '',
  });

  @override
  State<CreatePageWidget> createState() => _CreatePageWidgetState();
}

class _CreatePageWidgetState extends State<CreatePageWidget> {
  late TextEditingController _labelController;
  late IconData _selectedIcon;
  late bool _mirroringDisabled;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.initialPage?.menuItem.label ?? '');
    _selectedIcon = widget.initialPage?.menuItem.icon ??
        (widget.isSection ? Icons.folder : Icons.pageview);
    _mirroringDisabled = widget.initialPage?.mirroringDisabled ?? false;
  }

  String _buildPath(String label) {
    if (widget.isSection) return '';
    final slug = label.toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
    final base = widget.basePath;
    return slug.isEmpty ? '$base/' : '$base/$slug';
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _showIconPicker() {
    // Pre-build icon name pairs for searching
    final iconEntries = iconList.map((icon) {
      final name = IconDataConverter.getIconName(icon);
      return (icon: icon, name: name);
    }).toList();

    showDialog(
      context: context,
      builder: (context) {
        return _IconPickerDialog(
          iconEntries: iconEntries,
          onSelected: (icon) {
            setState(() {
              _selectedIcon = icon;
            });
            Navigator.pop(context);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelController,
            decoration: InputDecoration(
                labelText: widget.isSection ? 'Section Name' : 'Page Name'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Icon: '),
              Icon(_selectedIcon),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: _showIconPicker,
              ),
            ],
          ),
          if (!widget.isSection) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Mirroring Disabled: '),
                Switch(
                    value: _mirroringDisabled,
                    onChanged: (value) {
                      setState(() {
                        _mirroringDisabled = value;
                      });
                    }),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final label = _labelController.text.trim();
                  if (label.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Name cannot be empty')),
                    );
                    return;
                  }
                  final menuItem = MenuItem(
                    label: label,
                    path: _buildPath(label),
                    icon: _selectedIcon,
                    // Preserve existing children from the tree structure
                    children:
                        widget.initialPage?.menuItem.children ?? const [],
                  );
                  final page = AssetPage(
                    menuItem: menuItem,
                    assets: widget.initialPage?.assets ?? [],
                    mirroringDisabled: _mirroringDisabled,
                    navigationPriority: widget.initialPage?.navigationPriority,
                  );
                  widget.onSave(page);
                  Navigator.pop(context);
                },
                child: Text(widget.initialPage != null ? 'Update' : 'Create'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

typedef _IconEntry = ({IconData icon, String name});

class _IconPickerDialog extends StatefulWidget {
  final List<_IconEntry> iconEntries;
  final ValueChanged<IconData> onSelected;

  const _IconPickerDialog({
    required this.iconEntries,
    required this.onSelected,
  });

  @override
  State<_IconPickerDialog> createState() => _IconPickerDialogState();
}

class _IconPickerDialogState extends State<_IconPickerDialog> {
  final _searchController = TextEditingController();
  List<_IconEntry> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.iconEntries;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.iconEntries;
        return;
      }
      final queryWords =
          query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
      _filtered = widget.iconEntries.where((entry) {
        final name = entry.name.replaceAll('_', ' ').toLowerCase();
        return queryWords.every((word) => name.contains(word));
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Icon'),
      content: SizedBox(
        width: 350,
        height: 450,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search icons...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                isDense: true,
              ),
              onChanged: _onSearchChanged,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('No icons found'))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final entry = _filtered[index];
                        final displayName =
                            entry.name.replaceAll('_', ' ');
                        return Tooltip(
                          message: displayName,
                          child: InkWell(
                            onTap: () => widget.onSelected(entry.icon),
                            borderRadius: BorderRadius.circular(8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(entry.icon, size: 28),
                                const SizedBox(height: 2),
                                Text(
                                  displayName,
                                  style: const TextStyle(fontSize: 9),
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
