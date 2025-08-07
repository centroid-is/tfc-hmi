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

  AssetPage({required this.menuItem, required this.assets});

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
    if (jsonString != null) {
      try {
        fromJson(jsonString);
        if (pages.isEmpty) {
          pages = {
            'Home': AssetPage(
              menuItem:
                  const MenuItem(label: 'Home', path: '/', icon: Icons.home),
              assets: [],
            ),
          };
        }
      } catch (e) {
        pages = {
          'Home': AssetPage(
            menuItem:
                const MenuItem(label: 'Home', path: '/', icon: Icons.home),
            assets: [],
          ),
        };
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
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    pages = json.map((name, pageJson) => MapEntry(
          name,
          AssetPage.fromJson(pageJson as Map<String, dynamic>),
        ));
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
  late MenuItem? _parentMenuItem;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.initialPage?.menuItem.label ?? '');
    _pathController =
        TextEditingController(text: widget.initialPage?.menuItem.path ?? '/');
    _selectedIcon = widget.initialPage?.menuItem.icon ?? Icons.pageview;
    _parentMenuItem = widget.initialPage?.menuItem.children?.isNotEmpty == true
        ? widget.initialPage!.menuItem.children!.first
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

  @override
  Widget build(BuildContext context) {
    return Column(
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
                  children: _parentMenuItem != null ? [_parentMenuItem!] : [],
                );
                final page = AssetPage(
                  menuItem: menuItem,
                  assets: widget.initialPage?.assets ?? [],
                );
                widget.onSave(page);
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  static const List<IconData> _iconList = [
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
  ];
}
