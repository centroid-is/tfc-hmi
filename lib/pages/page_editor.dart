import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../page_creator/assets/common.dart';
import '../page_creator/assets/registry.dart';
import '../widgets/base_scaffold.dart';
import 'dart:convert'; // For JSON encoding
import 'page_view.dart';

class PageEditor extends StatefulWidget {
  @override
  _PageEditorState createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  static const String _storageKey = 'page_editor_data';
  List<Asset> assets = []; // Direct list of assets instead of groups
  bool _showPalette = false;

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_storageKey);
    print('Loading from prefs: $jsonString');
    if (jsonString != null) {
      setState(() {
        final json = jsonDecode(jsonString);
        assets = AssetRegistry.parse(json);
      });
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode({
      'assets': assets.map((a) => a.toJson()).toList(),
    });
    print('Saving to prefs: $jsonString');
    await prefs.setString(_storageKey, jsonString);
  }

  void _updateState(VoidCallback fn) {
    setState(() {
      fn();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Page Editor',
      body: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Shared asset stack with editor controls
                  DragTarget<Type>(
                    onAcceptWithDetails: (details) {
                      // Calculate drop position relative to the canvas
                      final RenderBox box =
                          context.findRenderObject() as RenderBox;
                      final localPosition = box.globalToLocal(details.offset);

                      final relativeX =
                          (localPosition.dx / box.size.width).clamp(0.0, 1.0);
                      final relativeY =
                          (localPosition.dy / box.size.height).clamp(0.0, 1.0);

                      final newAsset =
                          AssetRegistry.createDefaultAsset(details.data);
                      setState(() {
                        newAsset.coordinates =
                            Coordinates(x: relativeX, y: relativeY);
                        assets.add(newAsset);
                      });
                    },
                    builder: (context, candidateData, rejectedData) {
                      return AssetStack(
                        assets: assets,
                        constraints: constraints,
                        onTap: (asset) => _showConfigDialog(asset),
                        onPanUpdate: (asset, details) =>
                            _moveAsset(asset, details, constraints),
                        absorb: true,
                      );
                    },
                  ),
                  // Hamburger icon OVER the canvas, bottom left
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: Row(
                      children: [
                        FloatingActionButton(
                          mini: true,
                          heroTag: 'hamburger',
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          onPressed: () => setState(() => _showPalette = true),
                          child: Icon(Icons.menu, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton(
                          mini: true,
                          heroTag: 'save',
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          onPressed: _saveToPrefs,
                          child: Icon(Icons.save, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  // 1. Tap-to-close overlay (only when palette is open)
                  if (_showPalette)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(() => _showPalette = false),
                        behavior: HitTestBehavior
                            .translucent, // Ensures the whole area is tappable
                        child: Container(), // Transparent
                      ),
                    ),
                  // 2. The sliding palette drawer
                  if (_showPalette)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      child: SizedBox(
                        width: 320,
                        child: Material(
                          elevation: 8,
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          child: Stack(
                            children: [
                              _buildPalette(),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: IconButton(
                                  icon: Icon(Icons.close),
                                  onPressed: () =>
                                      setState(() => _showPalette = false),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPalette() {
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16.0),
            itemCount: AssetRegistry.defaultFactories.length,
            separatorBuilder: (context, index) => const SizedBox(height: 24),
            itemBuilder: (context, index) {
              final entry =
                  AssetRegistry.defaultFactories.entries.elementAt(index);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Draggable<Type>(
                    data: entry.key,
                    feedback: Material(
                      color: Colors.transparent,
                      child: entry.value().build(context),
                    ),
                    child: entry.value().build(context),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _showConfigDialog(Asset asset) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: IntrinsicWidth(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                asset.configure(context),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        _updateState(() {
                          assets.remove(asset);
                        });
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      setState(() {});
    });
  }

  void _moveAsset(
      Asset asset, DragUpdateDetails details, BoxConstraints constraints) {
    final newX = (asset.coordinates.x + details.delta.dx / constraints.maxWidth)
        .clamp(0.0, 1.0);
    final newY =
        (asset.coordinates.y + details.delta.dy / constraints.maxHeight)
            .clamp(0.0, 1.0);

    _updateState(() {
      asset.coordinates = Coordinates(x: newX, y: newY);
    });
  }
}
