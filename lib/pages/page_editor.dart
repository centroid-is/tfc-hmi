import 'dart:convert'; // For JSON encoding

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../page_creator/assets/common.dart';
import '../page_creator/assets/registry.dart';
import '../widgets/base_scaffold.dart';
import 'page_view.dart';
import '../providers/preferences.dart';

class PageEditor extends ConsumerStatefulWidget {
  @override
  ConsumerState<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<PageEditor> {
  static const String _storageKey = 'page_editor_data';
  List<Asset> assets = [];
  bool _showPalette = false;
  bool _showJsonEditor = false;
  String? _jsonError;
  final TextEditingController _jsonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await ref.read(preferencesProvider.future);
    final String? jsonString = await prefs.getString(_storageKey);
    print('Loading from prefs: $jsonString');
    if (jsonString != null) {
      try {
        final json = jsonDecode(jsonString);
        final newAssets = AssetRegistry.parse(json);
        setState(() {
          assets = newAssets;
          _showJsonEditor = false;
          _jsonError = null;
        });
      } catch (e) {
        setState(() {
          _showJsonEditor = true;
          _jsonError = e.toString();
          _jsonController.text = jsonString;
        });
      }
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await ref.read(preferencesProvider.future);
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

  String _formatJson(String jsonString) {
    try {
      var json = jsonDecode(jsonString);
      return JsonEncoder.withIndent('  ').convert(json);
    } catch (e) {
      // If we can't parse the JSON, return the original string
      return jsonString;
    }
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
              if (_showJsonEditor) {
                return _buildJsonEditor();
              }
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
                          child: const Icon(Icons.menu, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton(
                          mini: true,
                          heroTag: 'save',
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          onPressed: _saveToPrefs,
                          child: const Icon(Icons.save, color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton(
                          mini: true,
                          heroTag: 'json',
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          onPressed: () {
                            setState(() {
                              if (!_showJsonEditor) {
                                // Going to JSON editor
                                _jsonController.text = _formatJson(jsonEncode({
                                  'assets':
                                      assets.map((a) => a.toJson()).toList(),
                                }));
                                _showJsonEditor = true;
                              } else {
                                // Going back to canvas
                                _showJsonEditor = false;
                              }
                              _jsonError = null;
                            });
                          },
                          child: Icon(
                            _showJsonEditor ? Icons.edit : Icons.code,
                            color: Colors.white,
                          ),
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
      asset.coordinates =
          Coordinates(x: newX, y: newY, angle: asset.coordinates.angle);
    });
  }

  Widget _buildJsonEditor() {
    final scrollController = ScrollController();

    return Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'JSON Editor',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                // Add Format button
                TextButton.icon(
                  onPressed: () {
                    final formatted = _formatJson(_jsonController.text);
                    _jsonController.value = TextEditingValue(
                      text: formatted,
                      selection:
                          TextSelection.collapsed(offset: formatted.length),
                    );
                  },
                  icon: Icon(Icons.format_align_left),
                  label: Text('Format JSON'),
                ),
              ],
            ),
            if (_jsonError != null) ...[
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _jsonError!,
                  style: TextStyle(
                    color: Colors.red,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Line numbers column
                      Container(
                        width: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceVariant
                              .withOpacity(0.7),
                          borderRadius:
                              BorderRadius.horizontal(left: Radius.circular(4)),
                        ),
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _jsonController,
                          builder: (context, value, child) {
                            final lineCount =
                                '\n'.allMatches(value.text).length + 1;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (var i = 1; i <= lineCount; i++)
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 1),
                                    child: SizedBox(
                                      height: 21, // Match line height
                                      child: Text(
                                        '$i',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withOpacity(0.5),
                                          fontFamily: 'monospace',
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      // Vertical divider
                      Container(
                        width: 1,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.1),
                      ),
                      // Text editor
                      Expanded(
                        child: TextField(
                          controller: _jsonController,
                          maxLines: null,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            height: 1.5, // Line height to match line numbers
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(8),
                            hintText: 'Edit JSON configuration',
                            fillColor: Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    try {
                      final json = jsonDecode(_jsonController.text);
                      final newAssets = AssetRegistry.parse(json);
                      setState(() {
                        assets = newAssets;
                        _showJsonEditor = false;
                        _jsonError = null;
                      });
                      _saveToPrefs();
                    } catch (e) {
                      setState(() {
                        _jsonError = e.toString();
                      });
                    }
                  },
                  child: Text('Save Configuration'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
