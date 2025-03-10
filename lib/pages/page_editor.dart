import 'package:flutter/material.dart';
import '../page_creator/assets/common.dart';
import '../page_creator/assets/led.dart';
import '../page_creator/assets/circle_button.dart';
import '../page_creator/assets/registry.dart';
import '../widgets/base_scaffold.dart';

class PageEditor extends StatefulWidget {
  @override
  _PageEditorState createState() => _PageEditorState();
}

class _PageEditorState extends State<PageEditor> {
  List<Group> groups = [Group(name: 'default', assets: [])];
  int selectedGroupIndex = 0;
  int? selectedAssetIndex;

  @override
  Widget build(BuildContext context) {
    final currentGroup = groups[selectedGroupIndex];
    return BaseScaffold(
      title: 'Page Editor',
      body: Row(
        children: [
          _buildPalette(),
          _buildCanvas(currentGroup),
        ],
      ),
    );
  }

  Widget _buildPalette() {
    return Expanded(
      flex: 1,
      child: ListView.separated(
        itemCount: AssetRegistry.defaultFactories.length,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final entry = AssetRegistry.defaultFactories.entries.elementAt(index);
          return Draggable<Type>(
            data: entry.key,
            feedback: entry.value().build(context),
            child: entry.value().build(context),
          );
        },
      ),
    );
  }

  Widget _buildCanvas(Group currentGroup) {
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
          onAccept: (assetType) {
            final newAsset = AssetRegistry.createDefaultAsset(assetType);
            setState(() {
              currentGroup.assets.add(newAsset);
            });
          },
          builder: (context, candidateData, rejectedData) {
            return LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: currentGroup.assets.map((asset) {
                    final index = currentGroup.assets.indexOf(asset);
                    return Positioned(
                      left: asset.coordinates.x * constraints.maxWidth,
                      top: asset.coordinates.y * constraints.maxHeight,
                      child: GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    asset.configure(context),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text('Close'),
                                    ),
                                  ],
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
                          setState(() {
                            currentGroup.assets[index].coordinates =
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

  Map<String, dynamic> toJson() {
    return {
      'groups': groups.map((group) => group.toJson()).toList(),
    };
  }
}

class Group {
  String name;
  List<Asset> assets;

  Group({required this.name, required this.assets});

  Map<String, dynamic> toJson() => {
        'name': name,
        'assets': assets.map((asset) => asset.toJson()).toList(),
      };
}
