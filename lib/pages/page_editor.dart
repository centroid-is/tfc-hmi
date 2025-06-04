import 'dart:convert'; // For JSON encoding
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../page_creator/assets/common.dart';
import '../page_creator/assets/registry.dart';
import '../widgets/base_scaffold.dart';
import 'page_view.dart';
import '../providers/preferences.dart';
import '../widgets/zoomable_canvas.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

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
  bool _isSelectMode = false;
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  Set<Asset> _selectedAssets = {};

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

  void _handleSelectionBox(Offset position, BoxConstraints constraints) {
    if (_selectionStart == null) {
      setState(() {
        _selectionStart = position;
        _selectionCurrent = position;
      });
    } else {
      setState(() {
        _selectionCurrent = position;

        // Calculate selection bounds in relative coordinates
        final bounds = Rect.fromPoints(
          _selectionStart!,
          _selectionCurrent!,
        );

        // Select assets that intersect with the selection box
        _selectedAssets = assets.where((asset) {
          final assetRect = Rect.fromLTWH(
            asset.coordinates.x * constraints.maxWidth,
            asset.coordinates.y * constraints.maxHeight,
            asset.size.width * constraints.maxWidth,
            asset.size.height * constraints.maxHeight,
          );
          return bounds.overlaps(assetRect);
        }).toSet();
      });
    }
  }

  void _adjustSelectedAssetsSize(double factor) {
    setState(() {
      for (final asset in _selectedAssets) {
        asset.size = RelativeSize(
          width: (asset.size.width * factor).clamp(0.01, 1.0),
          height: (asset.size.height * factor).clamp(0.01, 1.0),
        );
      }
    });
    _saveToPrefs();
  }

  bool _isModifierPressed(Set<LogicalKeyboardKey> keysPressed) {
    if (kIsWeb || Platform.isWindows || Platform.isLinux) {
      return keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
          keysPressed.contains(LogicalKeyboardKey.controlRight);
    } else if (Platform.isMacOS) {
      return keysPressed.contains(LogicalKeyboardKey.metaLeft) ||
          keysPressed.contains(LogicalKeyboardKey.metaRight);
    }
    return false;
  }

  void _handleAssetSelection(Asset asset, Set<LogicalKeyboardKey> keysPressed) {
    setState(() {
      if (_isModifierPressed(keysPressed)) {
        if (_selectedAssets.contains(asset)) {
          _selectedAssets.remove(asset);
        } else {
          _selectedAssets.add(asset);
        }
      } else {
        _selectedAssets = {asset};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (keyEvent) {
        setState(() {});
      },
      child: BaseScaffold(
        title: 'Page Editor',
        body: ZoomableCanvas(
          panEnabled: !_isSelectMode,
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (_showJsonEditor) {
                return _buildJsonEditor();
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  DragTarget<Type>(
                    onAcceptWithDetails: (details) {
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
                        onTap: (asset) {
                          print('Asset tapped!');
                          if (_isSelectMode) {
                            _handleAssetSelection(
                              asset,
                              HardwareKeyboard.instance.logicalKeysPressed,
                            );
                          } else {
                            _showConfigDialog(asset);
                          }
                        },
                        onPanUpdate: (asset, details) =>
                            _moveAsset(asset, details, constraints),
                        absorb: true,
                        selectedAssets: _selectedAssets,
                      );
                    },
                  ),
                  if (_isSelectMode)
                    Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (pointerEvent) {
                        // If no Ctrl/Cmd, clear any existing selection
                        if (!_isModifierPressed(
                            HardwareKeyboard.instance.logicalKeysPressed)) {
                          setState(() {
                            _selectedAssets.clear();
                          });
                        }
                        // Record the start of the drag‐selection
                        final box = context.findRenderObject() as RenderBox;
                        final local = box.globalToLocal(pointerEvent.position);
                        setState(() {
                          _selectionStart = local;
                          _selectionCurrent = local;
                        });
                      },
                      onPointerMove: (pointerEvent) {
                        // Continue updating the selection rectangle
                        final box = context.findRenderObject() as RenderBox;
                        final local = box.globalToLocal(pointerEvent.position);
                        setState(() {
                          _selectionCurrent = local;

                          // Compute the rectangle in relative coords and update _selectedAssets
                          final bounds = Rect.fromPoints(
                              _selectionStart!, _selectionCurrent!);
                          _selectedAssets = assets.where((asset) {
                            final assetRect = Rect.fromLTWH(
                              asset.coordinates.x * constraints.maxWidth,
                              asset.coordinates.y * constraints.maxHeight,
                              asset.size.width * constraints.maxWidth,
                              asset.size.height * constraints.maxHeight,
                            );
                            return bounds.overlaps(assetRect);
                          }).toSet();
                        });
                      },
                      onPointerUp: (pointerEvent) {
                        // Finish the selection‐box
                        setState(() {
                          _selectionStart = null;
                          _selectionCurrent = null;
                        });
                      },
                    ),
                  if (_selectionStart != null && _selectionCurrent != null)
                    CustomPaint(
                      painter: SelectionBoxPainter(
                        start: _selectionStart!,
                        current: _selectionCurrent!,
                      ),
                    ),
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
                                _jsonController.text = _formatJson(jsonEncode({
                                  'assets':
                                      assets.map((a) => a.toJson()).toList(),
                                }));
                                _showJsonEditor = true;
                              } else {
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
                  if (_showPalette)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => setState(() => _showPalette = false),
                        behavior: HitTestBehavior.translucent,
                        child: Container(),
                      ),
                    ),
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
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedAssets.isNotEmpty) ...[
                          FloatingActionButton(
                            mini: true,
                            heroTag: 'increase',
                            onPressed: () => _adjustSelectedAssetsSize(1.1),
                            child: const Icon(Icons.add, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton(
                            mini: true,
                            heroTag: 'decrease',
                            onPressed: () => _adjustSelectedAssetsSize(0.9),
                            child:
                                const Icon(Icons.remove, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                        ],
                        FloatingActionButton(
                          mini: true,
                          heroTag: 'mode',
                          backgroundColor: _isSelectMode
                              ? Colors.orange
                              : Theme.of(context).colorScheme.primary,
                          onPressed: () => setState(() {
                            _isSelectMode = !_isSelectMode;
                            if (!_isSelectMode) {
                              _selectedAssets.clear();
                            }
                          }),
                          child: Icon(
                            _isSelectMode ? Icons.select_all : Icons.pan_tool,
                            color: Colors.white,
                          ),
                        ),
                      ],
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
                  SizedBox(
                    child: Draggable<Type>(
                      data: entry.key,
                      feedback: Material(
                        color: Colors.transparent,
                        child: SizedBox(
                          width: 100,
                          height: 100,
                          child: entry.value().build(context),
                        ),
                      ),
                      child: SizedBox(
                        width: 100,
                        height: 100,
                        child: entry.value().build(context),
                      ),
                    ),
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
                                      height: 21,
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
                      Container(
                        width: 1,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withOpacity(0.1),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _jsonController,
                          maxLines: null,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            height: 1.5,
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

class SelectionBoxPainter extends CustomPainter {
  final Offset start;
  final Offset current;

  SelectionBoxPainter({required this.start, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final rect = Rect.fromPoints(start, current);
    canvas.drawRect(rect, paint);

    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(SelectionBoxPainter oldDelegate) {
    return start != oldDelegate.start || current != oldDelegate.current;
  }
}
