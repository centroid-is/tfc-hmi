import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/material.dart';

import 'assets/common.dart';
import 'assets/registry.dart';
import '../models/menu_item.dart';
import '../core/preferences.dart';

part 'page.g.dart';

@JsonSerializable()
class AssetPage {
  @JsonKey(name: 'menu_item')
  final MenuItem menuItem;
  @AssetListConverter()
  final List<Asset> assets;
  @JsonKey(name: 'mirroring_disabled')
  bool mirroringDisabled;

  AssetPage(
      {required this.menuItem,
      required this.assets,
      required this.mirroringDisabled});

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
    final String? jsonString = await prefs.getString(storageKey);
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

  const CreatePageWidget({
    super.key,
    this.initialPage,
    required this.onSave,
  });

  @override
  State<CreatePageWidget> createState() => _CreatePageWidgetState();
}

class _CreatePageWidgetState extends State<CreatePageWidget> {
  late TextEditingController _labelController;
  late TextEditingController _pathController;
  late IconData _selectedIcon;
  late MenuItem? _child;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.initialPage?.menuItem.label ?? '');
    _pathController =
        TextEditingController(text: widget.initialPage?.menuItem.path ?? '/');
    _selectedIcon = widget.initialPage?.menuItem.icon ?? Icons.pageview;
    // Get the first child if it exists, otherwise null
    _child = widget.initialPage?.menuItem.children.isNotEmpty == true
        ? widget.initialPage!.menuItem.children.first
        : null;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _showIconPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Icon'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              childAspectRatio: 1,
            ),
            itemCount: _iconList.length,
            itemBuilder: (context, index) {
              final icon = _iconList[index];
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedIcon = icon;
                  });
                  Navigator.pop(context);
                },
                child: Icon(icon),
              );
            },
          ),
        ),
      ),
    );
  }

  void _addChild() {
    setState(() {
      _child = MenuItem(
        label: 'New Child',
        path: '/child',
        icon: Icons.folder,
      );
    });
  }

  void _removeChild() {
    setState(() {
      _child = null;
    });
  }

  void _updateChild(MenuItem updatedChild) {
    setState(() {
      _child = updatedChild;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(labelText: 'Page Name'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pathController,
            decoration: const InputDecoration(labelText: 'Path'),
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
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Mirroring Disabled: '),
              Switch(
                  value: widget.initialPage?.mirroringDisabled ?? false,
                  onChanged: (value) {
                    setState(() {
                      widget.initialPage?.mirroringDisabled = value;
                    });
                  }),
            ],
          ),
          // Child management section
          Row(
            children: [
              const Text('Child Menu Item:'),
              const Spacer(),
              if (_child == null)
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addChild,
                  tooltip: 'Add Child',
                ),
            ],
          ),
          if (_child != null) ...[
            const SizedBox(height: 8),
            _ChildMenuItemEditor(
              child: _child!,
              onUpdate: _updateChild,
              onRemove: _removeChild,
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
                  final menuItem = MenuItem(
                    label: _labelController.text,
                    path: _pathController.text,
                    icon: _selectedIcon,
                    children: _child != null ? [_child!] : [],
                  );
                  final page = AssetPage(
                    menuItem: menuItem,
                    assets: widget.initialPage?.assets ?? [],
                    mirroringDisabled:
                        widget.initialPage?.mirroringDisabled ?? false,
                  );
                  widget.onSave(page);
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Updated widget for editing child menu items with recursive support
class _ChildMenuItemEditor extends StatefulWidget {
  final MenuItem child;
  final Function(MenuItem) onUpdate;
  final VoidCallback onRemove;

  const _ChildMenuItemEditor({
    required this.child,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  State<_ChildMenuItemEditor> createState() => _ChildMenuItemEditorState();
}

class _ChildMenuItemEditorState extends State<_ChildMenuItemEditor> {
  late TextEditingController _labelController;
  late TextEditingController _pathController;
  late IconData _selectedIcon;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.child.label);
    _pathController = TextEditingController(text: widget.child.path ?? '');
    _selectedIcon = widget.child.icon;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  void _showIconPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Icon'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              childAspectRatio: 1,
            ),
            itemCount: _iconList.length,
            itemBuilder: (context, index) {
              final icon = _iconList[index];
              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedIcon = icon;
                  });
                  _updateParent(); // Add this line to update the parent when icon changes
                  Navigator.pop(context);
                },
                child: Icon(icon),
              );
            },
          ),
        ),
      ),
    );
  }

  void _updateParent() {
    final updatedChild = MenuItem(
      label: _labelController.text,
      path: _pathController.text,
      icon: _selectedIcon,
      children: widget.child.children,
    );
    widget.onUpdate(updatedChild);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: Icon(_selectedIcon),
            title: Text(_labelController.text.isEmpty
                ? 'New Child'
                : _labelController.text),
            subtitle: Text(_pathController.text.isEmpty
                ? 'No path'
                : _pathController.text),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon:
                      Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
          ),
          if (_isExpanded) ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _labelController,
                    decoration: const InputDecoration(labelText: 'Child Name'),
                    onChanged: (value) => _updateParent(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pathController,
                    decoration: const InputDecoration(labelText: 'Child Path'),
                    onChanged: (value) => _updateParent(),
                  ),
                  const SizedBox(height: 8),
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
                  // Recursive child management - this child can have its own child
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Grandchild Menu Item:'),
                      const Spacer(),
                      if (widget.child.children.isEmpty)
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final newGrandchild = MenuItem(
                              label: 'New Grandchild',
                              path: '/grandchild',
                              icon: Icons.folder_open,
                            );
                            final updatedChild = MenuItem(
                              label: _labelController.text,
                              path: _pathController.text,
                              icon: _selectedIcon,
                              children: [newGrandchild],
                            );
                            widget.onUpdate(updatedChild);
                          },
                          tooltip: 'Add Grandchild',
                        ),
                    ],
                  ),
                  if (widget.child.children.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _ChildMenuItemEditor(
                      child: widget.child.children.first,
                      onUpdate: (updatedGrandchild) {
                        final updatedChild = MenuItem(
                          label: _labelController.text,
                          path: _pathController.text,
                          icon: _selectedIcon,
                          children: [updatedGrandchild],
                        );
                        widget.onUpdate(updatedChild);
                      },
                      onRemove: () {
                        final updatedChild = MenuItem(
                          label: _labelController.text,
                          path: _pathController.text,
                          icon: _selectedIcon,
                          children: [], // Remove grandchild
                        );
                        widget.onUpdate(updatedChild);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const IconData baadericon =
    IconData(0xe800, fontFamily: "Baader", fontPackage: "tfc");

const List<IconData> _iconList = [
  Icons.home,
  Icons.settings,
  Icons.dashboard,
  Icons.analytics,
  Icons.monitor,
  Icons.tune,
  Icons.build,
  Icons.engineering,
  Icons.precision_manufacturing,
  Icons.factory,
  Icons.warehouse,
  Icons.inventory,
  Icons.assessment,
  Icons.trending_up,
  Icons.show_chart,
  Icons.bar_chart,
  Icons.pie_chart,
  Icons.table_chart,
  Icons.view_list,
  Icons.grid_view,
  Icons.view_module,
  Icons.view_quilt,
  Icons.view_agenda,
  Icons.view_column,
  Icons.view_headline,
  Icons.view_stream,
  Icons.view_week,
  Icons.view_day,
  Icons.view_carousel,
  Icons.view_comfy,
  Icons.view_compact,
  Icons.view_compact_alt,
  Icons.view_cozy,
  Icons.view_in_ar,
  Icons.view_kanban,
  Icons.view_sidebar,
  Icons.view_timeline,
  Icons.view_week,
  baadericon,
];
