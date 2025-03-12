import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../page_creator/assets/common.dart';
import '../page_creator/assets/registry.dart';
import '../widgets/base_scaffold.dart';
import 'dart:convert'; // For JSON encoding

class PageEditor extends StatefulWidget {
  @override
  _PageEditorState createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  static const String _storageKey = 'page_editor_data';
  List<Asset> assets = []; // Direct list of assets instead of groups

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
      body: Row(
        children: [
          _buildPalette(),
          _buildCanvas(),
        ],
      ),
    );
  }

  Widget _buildPalette() {
    return Expanded(
      flex: 1,
      child: Column(
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: _saveToPrefs,
              icon: const Icon(Icons.save),
              label: const Text('Save Layout'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return Expanded(
      flex: 4,
      child: Container(
        margin: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey.withOpacity(0.3),
            width: 1.0,
          ),
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: DragTarget<Type>(
          onAcceptWithDetails: (details) {
            final newAsset = AssetRegistry.createDefaultAsset(details.data);

            final RenderBox box = context.findRenderObject() as RenderBox;
            final localPosition = box.globalToLocal(details.offset);

            final relativeX =
                (localPosition.dx / box.size.width).clamp(0.0, 1.0);
            final relativeY =
                (localPosition.dy / box.size.height).clamp(0.0, 1.0);

            _updateState(() {
              newAsset.coordinates = Coordinates(x: relativeX, y: relativeY);
              assets.add(newAsset);
            });
          },
          builder: (context, candidateData, rejectedData) {
            return LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: assets.map((asset) {
                    final index = assets.indexOf(asset);
                    return Positioned(
                      left: asset.coordinates.x * constraints.maxWidth,
                      top: asset.coordinates.y * constraints.maxHeight,
                      child: GestureDetector(
                        onTap: () {
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () {
                                              _updateState(() {
                                                assets.remove(asset);
                                              });
                                              Navigator.pop(context);
                                            },
                                            icon: const Icon(Icons.delete,
                                                color: Colors.red),
                                            label: const Text(
                                              'Delete',
                                              style:
                                                  TextStyle(color: Colors.red),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text('Close'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        onPanUpdate: (details) {
                          final newX = (asset.coordinates.x +
                                  details.delta.dx / constraints.maxWidth)
                              .clamp(0.0, 1.0);
                          final newY = (asset.coordinates.y +
                                  details.delta.dy / constraints.maxHeight)
                              .clamp(0.0, 1.0);
                          _updateState(() {
                            assets[index].coordinates =
                                Coordinates(x: newX, y: newY);
                          });
                        },
                        child: asset.build(context),
                      ),
                    );
                  }).toList(),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
