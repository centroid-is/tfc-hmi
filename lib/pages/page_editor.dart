import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tfc/providers/page_manager.dart';
import '../page_creator/assets/common.dart';
import '../page_creator/assets/registry.dart';
import '../widgets/base_scaffold.dart';
import 'page_view.dart';
import '../widgets/zoomable_canvas.dart';
import '../page_creator/page.dart';
import '../models/menu_item.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class PageEditor extends ConsumerStatefulWidget {
  @override
  ConsumerState<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<PageEditor> {
  final List<Map<String, AssetPage>> _undoHistory = [];
  bool _showPalette = false;
  bool _isSelectMode = false;
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  Set<Asset> _selectedAssets = {};
  bool _isDraggingAsset = false;
  String? _copiedAssets;
  Map<String, AssetPage> _temporaryPages = {};
  String? _currentPage;
  String _paletteSearchQuery = '';
  String _savedJson = '';
  String _currentJson = '';

  List<Asset> get assets {
    if (_currentPage == null) {
      return [];
    }
    if (_temporaryPages[_currentPage] == null) {
      return [];
    }
    return _temporaryPages[_currentPage]!.assets;
  }

  @override
  void initState() {
    super.initState();
    ref.read(pageManagerProvider.future).then((pageManager) {
      setState(() {
        _temporaryPages = pageManager.copyWith().pages;
        _currentPage = pageManager.pages.keys.firstOrNull;
        _updateCurrentJson();
        _savedJson = _currentJson;
      });
    });
  }

  void _updateCurrentJson() {
    _currentJson = jsonEncode(
        _temporaryPages.map((name, page) => MapEntry(name, page.toJson())));
  }

  bool get _hasUnsavedChanges => _currentJson != _savedJson;

  String _assetsToJson(List<Asset> theAssets) {
    return jsonEncode({
      'assets': theAssets.map((a) => a.toJson()).toList(),
    });
  }

  Future<void> _saveToPrefs() async {
    final pageManager = await ref.read(pageManagerProvider.future);
    pageManager.pages = PageManager.copyPages(_temporaryPages);
    await pageManager.save();
    setState(() {
      _updateCurrentJson();
      _savedJson = _currentJson;
    });
  }

  void _updateState(VoidCallback fn) {
    setState(() {
      fn();
      _updateCurrentJson();
    });
  }

  void _saveToHistory() {
    _undoHistory.add(PageManager.copyPages(_temporaryPages));
    if (_undoHistory.length > 50) {
      _undoHistory.removeAt(0);
    }
  }

  void _handleUndo() {
    if (_undoHistory.isNotEmpty) {
      setState(() {
        _temporaryPages = _undoHistory.removeLast();
        _updateCurrentJson();
      });
    }
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

  void _handleCopy() {
    if (_selectedAssets.isEmpty) return;
    _copiedAssets = _assetsToJson(_selectedAssets.toList());
  }

  void _handlePaste() {
    if (_copiedAssets == null) return;

    _saveToHistory();
    setState(() {
      _selectedAssets.clear();

      final copiedAssets = AssetRegistry.parse(jsonDecode(_copiedAssets!));

      for (final asset in copiedAssets) {
        asset.coordinates = Coordinates(
          x: (asset.coordinates.x + 0.02).clamp(0.0, 1.0),
          y: (asset.coordinates.y + 0.02).clamp(0.0, 1.0),
          angle: asset.coordinates.angle,
        );
        assets.add(asset);
        _selectedAssets.add(asset);
      }
      _updateCurrentJson();
    });
  }

  void _handleDelete() {
    if (_selectedAssets.isEmpty) return;

    _saveToHistory();
    setState(() {
      assets.removeWhere((asset) => _selectedAssets.contains(asset));
      _selectedAssets.clear();
      _updateCurrentJson();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // Don't intercept keys when a text field has focus
        final primaryFocus = FocusManager.instance.primaryFocus;
        if (primaryFocus != null &&
            primaryFocus.context?.widget is EditableText) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent) {
          if (_isModifierPressed(
              HardwareKeyboard.instance.logicalKeysPressed)) {
            if (event.logicalKey == LogicalKeyboardKey.keyZ) {
              _handleUndo();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyC) {
              _handleCopy();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.keyV) {
              _handlePaste();
              return KeyEventResult.handled;
            }
          } else if (event.logicalKey == LogicalKeyboardKey.delete ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            _handleDelete();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: BaseScaffold(
        title: 'Page Editor',
        body: ZoomableCanvas(
          scaleEnabled: !_showPalette,
          panEnabled: !_isSelectMode,
          child: LayoutBuilder(
            builder: (context, constraints) {
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
                      _saveToHistory();
                      setState(() {
                        newAsset.coordinates =
                            Coordinates(x: relativeX, y: relativeY);
                        assets.add(newAsset);
                        _updateCurrentJson();
                      });
                    },
                    builder: (context, candidateData, rejectedData) {
                      return AssetStack(
                        assets: assets,
                        constraints: constraints,
                        onTap: (asset) {
                          if (_isSelectMode) {
                            _handleAssetSelection(
                              asset,
                              HardwareKeyboard.instance.logicalKeysPressed,
                            );
                          } else {
                            _showConfigDialog(asset);
                          }
                        },
                        onPanUpdate: (asset, details) {
                          _moveAsset(asset, details, constraints);
                        },
                        onPanStart: (asset, details) {
                          _saveToHistory();
                        },
                        absorb: true,
                        selectedAssets: _selectedAssets,
                        mirroringDisabled:
                            _temporaryPages[_currentPage]?.mirroringDisabled ??
                                false,
                      );
                    },
                  ),
                  if (_isSelectMode)
                    Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (pointerEvent) {
                        // Check if we're clicking on an asset first
                        bool hitAsset = assets.any((asset) {
                          final cx = asset.coordinates.x * constraints.maxWidth;
                          final cy =
                              asset.coordinates.y * constraints.maxHeight;
                          final halfW =
                              (asset.size.width * constraints.maxWidth) / 2;
                          final halfH =
                              (asset.size.height * constraints.maxHeight) / 2;

                          final assetRect = Rect.fromLTWH(
                            cx -
                                halfW, // Offset by half width to match Positioned widget
                            cy -
                                halfH, // Offset by half height to match Positioned widget
                            asset.size.width * constraints.maxWidth,
                            asset.size.height * constraints.maxHeight,
                          );
                          final localPosition = pointerEvent.localPosition;
                          return assetRect.contains(localPosition);
                        });

                        // Only start selection box if we didn't hit an asset
                        if (!hitAsset) {
                          // If no Ctrl/Cmd, clear any existing selection
                          if (!_isModifierPressed(
                              HardwareKeyboard.instance.logicalKeysPressed)) {
                            setState(() {
                              _selectedAssets.clear();
                            });
                          }
                          // Record the start of the drag‐selection
                          final box = context.findRenderObject() as RenderBox;
                          final local =
                              box.globalToLocal(pointerEvent.position);
                          setState(() {
                            _selectionStart = local;
                            _selectionCurrent = local;
                          });
                        }
                      },
                      onPointerMove: (pointerEvent) {
                        // Only update selection if we have a valid selection start AND we're not dragging an asset
                        if (_selectionStart != null && !_isDraggingAsset) {
                          final box = context.findRenderObject() as RenderBox;
                          final local =
                              box.globalToLocal(pointerEvent.position);
                          setState(() {
                            _selectionCurrent = local;

                            final bounds = Rect.fromPoints(
                                _selectionStart!, _selectionCurrent!);
                            _selectedAssets = assets.where((asset) {
                              final cx =
                                  asset.coordinates.x * constraints.maxWidth;
                              final cy =
                                  asset.coordinates.y * constraints.maxHeight;
                              final halfW =
                                  (asset.size.width * constraints.maxWidth) / 2;
                              final halfH =
                                  (asset.size.height * constraints.maxHeight) /
                                      2;

                              final assetRect = Rect.fromLTWH(
                                cx -
                                    halfW, // Offset by half width to match Positioned widget
                                cy -
                                    halfH, // Offset by half height to match Positioned widget
                                asset.size.width * constraints.maxWidth,
                                asset.size.height * constraints.maxHeight,
                              );
                              return bounds.overlaps(assetRect);
                            }).toSet();
                          });
                        }
                      },
                      onPointerUp: (pointerEvent) {
                        setState(() {
                          _isDraggingAsset = false;
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
                    top: 16,
                    right: 16,
                    child: _buildPageSelector(),
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
                          backgroundColor: _hasUnsavedChanges
                              ? Colors.orange
                              : Theme.of(context).colorScheme.primary,
                          onPressed: _saveToPrefs,
                          child: const Icon(Icons.save, color: Colors.white),
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
    final entries = AssetRegistry.defaultFactories.entries.where((entry) {
      if (_paletteSearchQuery.isEmpty) return true;
      final asset = entry.value();
      return asset.displayName
          .toLowerCase()
          .contains(_paletteSearchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 48, 8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search assets...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (value) =>
                setState(() => _paletteSearchQuery = value),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final previewAsset = entry.value();
              return _PaletteItem(
                assetType: entry.key,
                asset: previewAsset,
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
              children: [
                Expanded(child: asset.configure(context)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        _saveToHistory();
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
                      onPressed: () {
                        Navigator.pop(context);
                      },
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
      setState(() {
        _updateCurrentJson();
      });
    });
  }

  void _moveAsset(
      Asset asset, DragUpdateDetails details, BoxConstraints constraints) {
    // If the dragged asset is selected, move all selected assets
    final assetsToMove =
        _selectedAssets.contains(asset) ? _selectedAssets.toList() : [asset];

    _updateState(() {
      for (final assetToMove in assetsToMove) {
        final newX = (assetToMove.coordinates.x +
                details.delta.dx / constraints.maxWidth)
            .clamp(0.0, 1.0);
        final newY = (assetToMove.coordinates.y +
                details.delta.dy / constraints.maxHeight)
            .clamp(0.0, 1.0);

        assetToMove.coordinates =
            Coordinates(x: newX, y: newY, angle: assetToMove.coordinates.angle);
      }
    });
  }

  void _adjustSelectedAssetsSize(double factor) {
    _saveToHistory();
    setState(() {
      for (final asset in _selectedAssets) {
        asset.size = RelativeSize(
          width: (asset.size.width * factor).clamp(0.01, 1.0),
          height: (asset.size.height * factor).clamp(0.01, 1.0),
        );
      }
      _updateCurrentJson();
    });
  }

  Widget _buildPageSelector() {
    final currentPage = _currentPage ?? _temporaryPages.keys.firstOrNull ?? 'Empty';

    return GestureDetector(
      onTap: _showPageManagerDialog,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(currentPage),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  /// Returns page names that are not referenced as children of any OTHER page.
  /// Handles self-references (e.g. "IOs" entry with menuItem.label "Diagnostics"
  /// that has child {label: "IOs"}).
  List<String> _getRootPageNames() {
    final childLabels = <String>{};
    for (final entry in _temporaryPages.entries) {
      PageManager.collectChildLabels(
          entry.value.menuItem.children, childLabels, entry.key);
    }
    final roots = _temporaryPages.keys
        .where((name) => !childLabels.contains(name))
        .toList();
    roots.sort((a, b) {
      final pa = _temporaryPages[a]?.navigationPriority ?? 999;
      final pb = _temporaryPages[b]?.navigationPriority ?? 999;
      return pa.compareTo(pb);
    });
    return roots;
  }

  void _showPageManagerDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, dialogSetState) {
          final roots = _getRootPageNames();
          return AlertDialog(
            title: const Text('Pages'),
            content: SizedBox(
              width: 550,
              height: 550,
              child: Column(
                children: [
                  Text(
                    'Tap to select. Sections are navigation groups.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ReorderableListView(
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) {
                        _onReorderRoots(
                            roots, oldIndex, newIndex, dialogSetState);
                      },
                      children: [
                        for (int i = 0; i < roots.length; i++)
                          _buildTreeNode(
                            roots[i],
                            dialogSetState,
                            dialogContext,
                            depth: 0,
                            reorderIndex: i,
                          ),
                      ],
                    ),
                  ),
                  const Divider(),
                  _buildAddButtons(null, dialogSetState, dialogContext),
                ],
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Navigation changes require app restart.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTreeNode(
    String pageName,
    StateSetter dialogSetState,
    BuildContext dialogContext, {
    required int depth,
    required int reorderIndex,
  }) {
    final page = _temporaryPages[pageName];
    if (page == null) return SizedBox(key: ValueKey(pageName));

    final isSelected = _currentPage == pageName;
    final displayName = page.menuItem.label;
    final hasChildren = page.menuItem.children.isNotEmpty;
    final hasSelfRef =
        page.menuItem.children.any((c) => c.label == pageName);
    final isSection = (page.menuItem.path ?? '').isEmpty || hasSelfRef;

    return Padding(
      key: ValueKey(pageName),
      padding: EdgeInsets.only(left: depth > 0 ? 20.0 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            dense: true,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReorderableDragStartListener(
                  index: reorderIndex,
                  child: const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
                ),
                const SizedBox(width: 4),
                Icon(
                  page.menuItem.icon,
                  color: isSelected && !isSection
                      ? Theme.of(dialogContext).colorScheme.primary
                      : null,
                ),
              ],
            ),
            title: Text(
              displayName,
              style: TextStyle(
                fontWeight:
                    isSelected && !isSection ? FontWeight.bold : FontWeight.normal,
                color: isSelected && !isSection
                    ? Theme.of(dialogContext).colorScheme.primary
                    : null,
              ),
            ),
            subtitle: isSection ? const Text('Section') : null,
            selected: isSelected && !isSection,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSection && depth < 3)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: 'Add child',
                    onSelected: (value) {
                      _addItem(
                        parentName: pageName,
                        isSection: value == 'section',
                        dialogSetState: dialogSetState,
                        dialogContext: dialogContext,
                      );
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'page',
                        child: Text('Add Page'),
                      ),
                      const PopupMenuItem(
                        value: 'section',
                        child: Text('Add Section'),
                      ),
                    ],
                  )
                else if (isSection)
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: 'Add page',
                    onPressed: () => _addItem(
                      parentName: pageName,
                      isSection: false,
                      dialogSetState: dialogSetState,
                      dialogContext: dialogContext,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _editPage(
                      pageName, page, dialogSetState, dialogContext),
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  onPressed: () => _deletePage(
                      pageName, dialogSetState, dialogContext),
                  tooltip: 'Delete',
                ),
              ],
            ),
            onTap: isSection
                ? null
                : () {
                    setState(() => _currentPage = pageName);
                    Navigator.pop(dialogContext);
                  },
          ),
          // Render children recursively with reordering
          if (hasChildren)
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) {
                _onReorderChildren(
                    pageName, oldIndex, newIndex, dialogSetState);
              },
              children: [
                for (int i = 0; i < page.menuItem.children.length; i++)
                  if (page.menuItem.children[i].label == pageName)
                    _buildSelfRefChild(
                      page.menuItem.children[i],
                      pageName,
                      dialogSetState,
                      dialogContext,
                      depth: depth + 1,
                      reorderIndex: i,
                    )
                  else
                    _buildTreeNode(
                      page.menuItem.children[i].label,
                      dialogSetState,
                      dialogContext,
                      depth: depth + 1,
                      reorderIndex: i,
                    ),
              ],
            ),
        ],
      ),
    );
  }

  /// Renders a self-referencing child as a leaf page.
  /// E.g. the "IOs" entry has label "Diagnostics" with child {label: "IOs"}.
  /// The child is the actual clickable page that selects this entry for editing.
  Widget _buildSelfRefChild(
    MenuItem childItem,
    String mapKey,
    StateSetter dialogSetState,
    BuildContext dialogContext, {
    required int depth,
    required int reorderIndex,
  }) {
    final isSelected = _currentPage == mapKey;
    final page = _temporaryPages[mapKey];

    return Padding(
      key: ValueKey('selfref-$mapKey'),
      padding: const EdgeInsets.only(left: 20.0),
      child: ListTile(
        dense: true,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReorderableDragStartListener(
              index: reorderIndex,
              child: const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
            ),
            const SizedBox(width: 4),
            Icon(
              childItem.icon,
              color: isSelected
                  ? Theme.of(dialogContext).colorScheme.primary
                  : null,
            ),
          ],
        ),
        title: Text(
          childItem.label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Theme.of(dialogContext).colorScheme.primary
                : null,
          ),
        ),
        selected: isSelected,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (page != null)
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => _editSelfRefChild(
                    mapKey, childItem, dialogSetState, dialogContext),
                tooltip: 'Edit',
              ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18),
              onPressed: () =>
                  _deletePage(mapKey, dialogSetState, dialogContext),
              tooltip: 'Delete',
            ),
          ],
        ),
        onTap: () {
          setState(() => _currentPage = mapKey);
          Navigator.pop(dialogContext);
        },
      ),
    );
  }

  void _onReorderRoots(
    List<String> roots,
    int oldIndex,
    int newIndex,
    StateSetter dialogSetState,
  ) {
    if (oldIndex < newIndex) newIndex -= 1;
    setState(() {
      final movedName = roots[oldIndex];
      roots.removeAt(oldIndex);
      roots.insert(newIndex, movedName);
      for (int i = 0; i < roots.length; i++) {
        final page = _temporaryPages[roots[i]]!;
        _temporaryPages[roots[i]] = AssetPage(
          menuItem: page.menuItem,
          assets: page.assets,
          mirroringDisabled: page.mirroringDisabled,
          navigationPriority: i,
        );
      }
      _updateCurrentJson();
    });
    dialogSetState(() {});
  }

  void _onReorderChildren(
    String parentName,
    int oldIndex,
    int newIndex,
    StateSetter dialogSetState,
  ) {
    if (oldIndex < newIndex) newIndex -= 1;
    setState(() {
      final parent = _temporaryPages[parentName]!;
      final children = List<MenuItem>.from(parent.menuItem.children);
      final moved = children.removeAt(oldIndex);
      children.insert(newIndex, moved);
      _temporaryPages[parentName] = AssetPage(
        menuItem: MenuItem(
          label: parent.menuItem.label,
          path: parent.menuItem.path,
          icon: parent.menuItem.icon,
          children: children,
        ),
        assets: parent.assets,
        mirroringDisabled: parent.mirroringDisabled,
        navigationPriority: parent.navigationPriority,
      );
      // Update navigationPriority on each child page
      for (int i = 0; i < children.length; i++) {
        final childPage = _temporaryPages[children[i].label];
        if (childPage != null) {
          _temporaryPages[children[i].label] = AssetPage(
            menuItem: childPage.menuItem,
            assets: childPage.assets,
            mirroringDisabled: childPage.mirroringDisabled,
            navigationPriority: i,
          );
        }
      }
      _updateCurrentJson();
    });
    dialogSetState(() {});
  }

  /// Edit a self-referencing child's properties (label, path, icon).
  /// Updates both the child MenuItem in the parent and the map entry.
  void _editSelfRefChild(
    String mapKey,
    MenuItem childItem,
    StateSetter dialogSetState,
    BuildContext dialogContext,
  ) {
    final page = _temporaryPages[mapKey]!;
    // Create a temporary AssetPage with the child's MenuItem for editing
    final childPage = AssetPage(
      menuItem: childItem,
      assets: page.assets,
      mirroringDisabled: page.mirroringDisabled,
      navigationPriority: page.navigationPriority,
    );

    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Page'),
        content: SizedBox(
          width: 400,
          child: CreatePageWidget(
            initialPage: childPage,
            basePath: _buildBasePath(mapKey),
            onSave: (updatedPage) {
              setState(() {
                final newLabel = updatedPage.menuItem.label;
                // Update the child MenuItem in the parent's children list
                final parentPage = _temporaryPages[mapKey]!;
                final updatedChildren =
                    parentPage.menuItem.children.map((c) {
                  if (c.label == childItem.label) {
                    return MenuItem(
                      label: newLabel,
                      path: updatedPage.menuItem.path,
                      icon: updatedPage.menuItem.icon,
                      children: c.children,
                    );
                  }
                  return c;
                }).toList();
                _temporaryPages[mapKey] = AssetPage(
                  menuItem: MenuItem(
                    label: parentPage.menuItem.label,
                    path: parentPage.menuItem.path,
                    icon: parentPage.menuItem.icon,
                    children: updatedChildren,
                  ),
                  assets: parentPage.assets,
                  mirroringDisabled: updatedPage.mirroringDisabled,
                  navigationPriority: updatedPage.navigationPriority,
                );
                _updateCurrentJson();
              });
              dialogSetState(() {});
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAddButtons(
    String? parentName,
    StateSetter dialogSetState,
    BuildContext dialogContext, {
    int depth = 0,
  }) {
    if (depth >= 3) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Page'),
          onPressed: () => _addItem(
            parentName: parentName,
            isSection: false,
            dialogSetState: dialogSetState,
            dialogContext: dialogContext,
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.create_new_folder, size: 16),
          label: const Text('Section'),
          onPressed: () => _addItem(
            parentName: parentName,
            isSection: true,
            dialogSetState: dialogSetState,
            dialogContext: dialogContext,
          ),
        ),
      ],
    );
  }

  String _buildBasePath(String? parentName) {
    if (parentName == null) return '';
    final segments = <String>[];
    String? current = parentName;
    final visited = <String>{};
    while (current != null && !visited.contains(current)) {
      visited.add(current);
      final page = _temporaryPages[current];
      if (page == null) break;
      final path = page.menuItem.path ?? '';
      if (path.isNotEmpty) {
        segments.insertAll(
            0, path.split('/').where((s) => s.isNotEmpty).toList());
        break;
      }
      // Section without path — use label as slug
      segments.insert(0, _slugify(page.menuItem.label));
      current = _findParentOf(current);
    }
    if (segments.isEmpty) return '';
    return '/${segments.join('/')}';
  }

  String? _findParentOf(String childName) {
    for (final entry in _temporaryPages.entries) {
      if (entry.key != childName &&
          entry.value.menuItem.children.any((c) => c.label == childName)) {
        return entry.key;
      }
    }
    return null;
  }

  static String _slugify(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
  }

  void _addItem({
    required String? parentName,
    required bool isSection,
    required StateSetter dialogSetState,
    required BuildContext dialogContext,
  }) {
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: Text(isSection ? 'Add Section' : 'Add Page'),
        content: SizedBox(
          width: 400,
          child: CreatePageWidget(
          isSection: isSection,
          basePath: isSection ? '' : _buildBasePath(parentName),
          onSave: (page) {
            setState(() {
              // Auto-assign priority: put at end of its level
              final int priority;
              if (parentName != null) {
                final parent = _temporaryPages[parentName];
                priority = parent?.menuItem.children.length ?? 0;
              } else {
                priority = _getRootPageNames().length;
              }
              final pageWithPriority = AssetPage(
                menuItem: page.menuItem,
                assets: page.assets,
                mirroringDisabled: page.mirroringDisabled,
                navigationPriority: priority,
              );
              _temporaryPages[pageWithPriority.menuItem.label] = pageWithPriority;
              // Add as child of parent if specified
              if (parentName != null) {
                final parent = _temporaryPages[parentName];
                if (parent != null) {
                  final updatedChildren =
                      List<MenuItem>.from(parent.menuItem.children)
                        ..add(pageWithPriority.menuItem);
                  _temporaryPages[parentName] = AssetPage(
                    menuItem: MenuItem(
                      label: parent.menuItem.label,
                      path: parent.menuItem.path,
                      icon: parent.menuItem.icon,
                      children: updatedChildren,
                    ),
                    assets: parent.assets,
                    mirroringDisabled: parent.mirroringDisabled,
                    navigationPriority: parent.navigationPriority,
                  );
                }
              }
              if (!isSection) {
                _currentPage = pageWithPriority.menuItem.label;
              }
              _updateCurrentJson();
            });
            dialogSetState(() {});
          },
        ),
        ),
      ),
    );
  }

  void _editPage(
    String pageName,
    AssetPage page,
    StateSetter dialogSetState,
    BuildContext dialogContext,
  ) {
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit'),
        content: SizedBox(
          width: 400,
          child: CreatePageWidget(
            initialPage: page,
            isSection: (page.menuItem.path ?? '').isEmpty,
            basePath: _buildBasePath(_findParentOf(pageName)),
            onSave: (updatedPage) {
              setState(() {
                final newName = updatedPage.menuItem.label;
                if (newName != pageName) {
                  _temporaryPages.remove(pageName);
                  // Update parent references
                  _renameChildInParents(pageName, newName);
                  if (_currentPage == pageName) {
                    _currentPage = newName;
                  }
                }
                _temporaryPages[newName] = updatedPage;
                _updateCurrentJson();
              });
              dialogSetState(() {});
            },
          ),
        ),
      ),
    );
  }

  void _renameChildInParents(String oldName, String newName) {
    final updates = <String, AssetPage>{};
    for (final entry in _temporaryPages.entries) {
      final page = entry.value;
      final updated = _renameInChildren(page.menuItem.children, oldName, newName);
      if (updated != null) {
        updates[entry.key] = AssetPage(
          menuItem: MenuItem(
            label: page.menuItem.label,
            path: page.menuItem.path,
            icon: page.menuItem.icon,
            children: updated,
          ),
          assets: page.assets,
          mirroringDisabled: page.mirroringDisabled,
          navigationPriority: page.navigationPriority,
        );
      }
    }
    _temporaryPages.addAll(updates);
  }

  List<MenuItem>? _renameInChildren(
      List<MenuItem> children, String oldName, String newName) {
    bool changed = false;
    final result = children.map((child) {
      MenuItem updated = child;
      if (child.label == oldName) {
        changed = true;
        final newPage = _temporaryPages[newName];
        updated = MenuItem(
          label: newName,
          path: newPage?.menuItem.path ?? child.path,
          icon: newPage?.menuItem.icon ?? child.icon,
          children: child.children,
        );
      }
      final subUpdated = _renameInChildren(updated.children, oldName, newName);
      if (subUpdated != null) {
        changed = true;
        updated = MenuItem(
          label: updated.label,
          path: updated.path,
          icon: updated.icon,
          children: subUpdated,
        );
      }
      return updated;
    }).toList();
    return changed ? result : null;
  }

  void _deletePage(
    String pageName,
    StateSetter dialogSetState,
    BuildContext dialogContext,
  ) {
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Delete "$pageName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _temporaryPages.remove(pageName);
                // Remove from parent children lists
                _removeChildFromParents(pageName);
                if (_currentPage == pageName) {
                  _currentPage = _temporaryPages.keys.firstOrNull;
                }
                _updateCurrentJson();
              });
              dialogSetState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _removeChildFromParents(String name) {
    final updates = <String, AssetPage>{};
    for (final entry in _temporaryPages.entries) {
      final page = entry.value;
      final updated = _removeFromChildren(page.menuItem.children, name);
      if (updated != null) {
        updates[entry.key] = AssetPage(
          menuItem: MenuItem(
            label: page.menuItem.label,
            path: page.menuItem.path,
            icon: page.menuItem.icon,
            children: updated,
          ),
          assets: page.assets,
          mirroringDisabled: page.mirroringDisabled,
          navigationPriority: page.navigationPriority,
        );
      }
    }
    _temporaryPages.addAll(updates);
  }

  List<MenuItem>? _removeFromChildren(List<MenuItem> children, String name) {
    bool changed = false;
    final result = <MenuItem>[];
    for (final child in children) {
      if (child.label == name) {
        changed = true;
        continue;
      }
      final subUpdated = _removeFromChildren(child.children, name);
      if (subUpdated != null) {
        changed = true;
        result.add(MenuItem(
          label: child.label,
          path: child.path,
          icon: child.icon,
          children: subUpdated,
        ));
      } else {
        result.add(child);
      }
    }
    return changed ? result : null;
  }
}

class _PaletteItem extends StatelessWidget {
  final Type assetType;
  final Asset asset;

  const _PaletteItem({
    required this.assetType,
    required this.asset,
  });

  @override
  Widget build(BuildContext context) {
    return Draggable<Type>(
      data: assetType,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 80,
          height: 80,
          child: Opacity(
            opacity: 0.7,
            child: asset.build(context),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildThumbnail(context),
      ),
      child: _buildThumbnail(context),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 80,
                height: 80,
                child: IgnorePointer(
                  child: asset.build(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            asset.displayName,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
