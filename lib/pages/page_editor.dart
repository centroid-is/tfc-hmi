import 'dart:convert';
import 'package:tfc/core/platform_io.dart';

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
import '../providers/current_page_assets.dart';
import '../tech_docs/tech_doc_picker.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import '../chat/ai_context_action.dart';
import '../chat/chat_overlay.dart' show ChatContext;
import '../chat/hamburger_context_menu.dart';
import '../chat/page_context_menu.dart';
import '../chat/palette_context_menu.dart';
import '../widgets/proposal_visual.dart';
import '../providers/proposal_state.dart';
import 'package:flutter/services.dart';

class PageEditor extends ConsumerStatefulWidget {
  /// Optional proposal JSON passed via Beamer route data.
  /// When non-null, the editor pre-populates from the proposal instead of
  /// loading only from [pageManagerProvider].
  final String? proposalData;

  const PageEditor({super.key, this.proposalData});

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

  /// True when the editor was opened with AI proposal data that has not yet
  /// been saved by the operator.
  bool _isProposal = false;
  String? _proposalTitle;
  int? _proposalId;

  /// Assets that were added by the AI proposal (for visual indicators).
  Set<Asset> _proposedAssets = {};

  /// Snapshot of pages before proposal was applied (for reject/revert).
  Map<String, AssetPage>? _preProposalPages;

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

        // Apply proposal data if present.
        _applyProposalData(widget.proposalData);

        _updateCurrentJson();
        _savedJson =
            _isProposal ? '' : _currentJson; // Mark unsaved if proposal
      });
    });
  }

  /// Parses proposal JSON and merges it into [_temporaryPages].
  ///
  /// For `_proposal_type: 'page'`: expects keys like `title`, `key`, `assets`,
  /// `mirroring_disabled`. Creates or replaces a page entry.
  ///
  /// For `_proposal_type: 'asset'`: expects `key`, `title`, `children` (list
  /// of asset JSON). Adds assets to the page identified by `key`, or creates
  /// a new page.
  void _applyProposalData(String? proposalJson) {
    if (proposalJson == null) return;

    // Store pre-proposal snapshot for reject/revert.
    _preProposalPages = PageManager.copyPages(_temporaryPages);

    try {
      final Map<String, dynamic> proposal;
      final decoded = jsonDecode(proposalJson);
      if (decoded is Map<String, dynamic>) {
        proposal = decoded;
      } else {
        return;
      }

      final type = proposal['_proposal_type'] as String?;
      if (type == null) return;

      // Try to match proposal to universal state for ID tracking.
      try {
        final state = ref.read(proposalStateProvider);
        for (final p in state.proposals) {
          if (p.proposalJson == proposalJson) {
            _proposalId = p.id;
            break;
          }
        }
      } catch (_) {}

      if (type == 'page') {
        _applyPageProposal(proposal);
      } else if (type == 'asset') {
        _applyAssetProposal(proposal);
      }
    } catch (_) {
      // Best-effort: if proposal JSON is malformed, ignore it.
    }
  }

  void _applyPageProposal(Map<String, dynamic> proposal) {
    final title = proposal['title'] as String? ?? 'AI Proposal';
    final key = proposal['key'] as String? ?? '/$title';
    final mirroringDisabled = proposal['mirroring_disabled'] as bool? ?? false;

    List<Asset> assets = [];
    if (proposal['assets'] is List) {
      final items = proposal['assets'] as List;
      // Try full parse first (works when JSON has all required fields).
      try {
        final parsed = AssetRegistry.parse({'assets': items});
        if (parsed.isNotEmpty) {
          assets = parsed;
        }
      } catch (_) {}
      // Fallback: create default assets by type name for minimal MCP JSON.
      if (assets.isEmpty) {
        for (final item in items) {
          if (item is! Map<String, dynamic>) continue;
          final assetName =
              item['asset_name'] as String? ?? item['asset_type'] as String?;
          if (assetName == null) continue;
          final asset = AssetRegistry.createDefaultAssetByName(assetName);
          if (asset == null) continue;
          if (item['key'] is String) {
            try {
              (asset as dynamic).key = item['key'] as String;
            } catch (_) {}
          }
          final label = item['title'] as String? ??
              item['label'] as String? ??
              item['text'] as String?;
          if (label != null) {
            asset.text = label;
            asset.textPos ??= TextPos.below;
          }
          if (item['coordinates'] is Map<String, dynamic>) {
            final c = item['coordinates'] as Map<String, dynamic>;
            asset.coordinates = Coordinates(
              x: (c['x'] as num?)?.toDouble() ?? 0.0,
              y: (c['y'] as num?)?.toDouble() ?? 0.0,
            );
          } else if (item['x'] is num || item['y'] is num) {
            asset.coordinates = Coordinates(
              x: (item['x'] as num?)?.toDouble() ?? 0.1,
              y: (item['y'] as num?)?.toDouble() ?? 0.1,
            );
          }
          assets.add(asset);
        }
      }
    }

    final page = AssetPage(
      menuItem: MenuItem(label: title, path: key, icon: Icons.auto_awesome),
      assets: assets,
      mirroringDisabled: mirroringDisabled,
    );

    _temporaryPages[key] = page;
    _currentPage = key;
    _isProposal = true;
    _proposalTitle = title;
    _proposedAssets = Set.of(assets);
  }

  void _applyAssetProposal(Map<String, dynamic> proposal) {
    final title = proposal['title'] as String? ?? 'AI Asset Proposal';
    // Use page_key to find the target page; fall back to current page.
    // proposal['key'] is the asset identifier, not a page key.
    final targetPage = proposal['page_key'] as String? ?? _currentPage;

    List<Asset> newAssets = [];
    for (final sourceKey in ['children', 'assets']) {
      if (proposal[sourceKey] is! List) continue;
      final items = proposal[sourceKey] as List;
      // First, try full parse (works when the JSON has all required fields).
      try {
        final parsed = AssetRegistry.parse({'assets': items});
        if (parsed.isNotEmpty) {
          newAssets.addAll(parsed);
          continue;
        }
      } catch (_) {}
      // Fallback: create default assets by type name and apply key/title/
      // coordinates from the proposal. This handles MCP proposals that only
      // provide minimal fields (asset_type, key, title).
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final assetName =
            item['asset_name'] as String? ?? item['asset_type'] as String?;
        if (assetName == null) continue;
        final asset = AssetRegistry.createDefaultAssetByName(assetName);
        if (asset == null) continue;
        // Apply key — most asset types store it as a direct `key` field.
        if (item['key'] is String) {
          try {
            (asset as dynamic).key = item['key'] as String;
          } catch (_) {}
        }
        // Apply display text.
        final label = item['title'] as String? ?? item['text'] as String?;
        if (label != null) {
          asset.text = label;
          asset.textPos ??= TextPos.below;
        }
        // Apply coordinates.
        if (item['coordinates'] is Map<String, dynamic>) {
          final c = item['coordinates'] as Map<String, dynamic>;
          asset.coordinates = Coordinates(
            x: (c['x'] as num?)?.toDouble() ?? 0.0,
            y: (c['y'] as num?)?.toDouble() ?? 0.0,
          );
        } else if (item['x'] is num || item['y'] is num) {
          asset.coordinates = Coordinates(
            x: (item['x'] as num?)?.toDouble() ?? 0.1,
            y: (item['y'] as num?)?.toDouble() ?? 0.1,
          );
        }
        // Apply config overrides: merge LLM-provided config into the
        // default asset's JSON representation, then re-parse to get a
        // fully configured asset with all type-safe fields.
        final config = item['config'];
        if (config is Map<String, dynamic> && config.isNotEmpty) {
          try {
            final baseJson = asset.toJson();
            baseJson.addAll(config);
            // Ensure asset_name survives the merge so parse() finds it.
            baseJson[constAssetName] = assetName;
            final reparsed =
                AssetRegistry.parse({constAssetName: assetName, ...baseJson});
            if (reparsed.isNotEmpty) {
              newAssets.add(reparsed.first);
              continue;
            }
          } catch (_) {
            // If re-parse fails, fall through and use the default asset.
          }
        }
        newAssets.add(asset);
      }
    }

    _proposedAssets = Set.of(newAssets);

    if (targetPage != null && _temporaryPages.containsKey(targetPage)) {
      // Add assets to existing page.
      _temporaryPages[targetPage]!.assets.addAll(newAssets);
      _currentPage = targetPage;
    } else {
      // Create a new page with the proposed assets.
      final pageKey = targetPage ?? '/$title';
      _temporaryPages[pageKey] = AssetPage(
        menuItem:
            MenuItem(label: title, path: pageKey, icon: Icons.auto_awesome),
        assets: newAssets,
        mirroringDisabled: false,
      );
      _currentPage = pageKey;
    }

    _isProposal = true;
    _proposalTitle = title;
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
    ref.invalidate(pageManagerProvider);
    if (!mounted) return;

    // Update universal proposal state if this was a proposal accept.
    if (_isProposal && _proposalId != null) {
      try {
        ref.read(proposalStateProvider.notifier).acceptProposal(_proposalId!);
      } catch (_) {}
    }

    setState(() {
      _updateCurrentJson();
      _savedJson = _currentJson;
      _isProposal = false; // Proposal accepted and saved.
      _proposedAssets = {};
      _preProposalPages = null;
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
    // Reactively watch for new page/asset proposals arriving via MCP.
    ref.listen<ProposalState>(proposalStateProvider, (prev, next) {
      if (_isProposal) return; // Already showing a proposal.
      final pageProposals = next.proposals.where((p) =>
          p.proposalType == 'page' || p.proposalType == 'asset');
      if (pageProposals.isEmpty) return;
      final proposal = pageProposals.first;
      _applyProposalData(proposal.proposalJson);
      if (_isProposal) {
        _updateCurrentJson();
        _savedJson = ''; // Mark unsaved for proposal.
        setState(() {});
      }
    });

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
        title: _isProposal ? 'Page Editor — AI Proposal' : 'Page Editor',
        body: Column(
          children: [
            if (_isProposal)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: Colors.amber.shade50,
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'AI Proposal: ${_proposalTitle ?? "Untitled"}. '
                        'Review the proposed layout.',
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saveToPrefs,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Accept'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        if (_proposalId != null) {
                          try {
                            ref.read(proposalStateProvider.notifier)
                                .rejectProposal(_proposalId!);
                          } catch (_) {}
                        }
                        setState(() {
                          if (_preProposalPages != null) {
                            _temporaryPages = _preProposalPages!;
                            _currentPage = _temporaryPages.keys.firstOrNull;
                          }
                          _isProposal = false;
                          _proposedAssets = {};
                          _preProposalPages = null;
                          _updateCurrentJson();
                          _savedJson = _currentJson;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text('Reject'),
                    ),
                  ],
                ),
              ),
            Expanded(
                child: ZoomableCanvas(
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
                          final localPosition =
                              box.globalToLocal(details.offset);

                          final relativeX = (localPosition.dx / box.size.width)
                              .clamp(0.0, 1.0);
                          final relativeY = (localPosition.dy / box.size.height)
                              .clamp(0.0, 1.0);

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
                            proposedAssets: _proposedAssets,
                            mirroringDisabled: _temporaryPages[_currentPage]
                                    ?.mirroringDisabled ??
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
                              final localPosition = pointerEvent.localPosition;
                              return assetRect.contains(localPosition);
                            });

                            // Only start selection box if we didn't hit an asset
                            if (!hitAsset) {
                              // If no Ctrl/Cmd, clear any existing selection
                              if (!_isModifierPressed(HardwareKeyboard
                                  .instance.logicalKeysPressed)) {
                                setState(() {
                                  _selectedAssets.clear();
                                });
                              }
                              // Record the start of the drag‐selection
                              final box =
                                  context.findRenderObject() as RenderBox;
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
                              final box =
                                  context.findRenderObject() as RenderBox;
                              final local =
                                  box.globalToLocal(pointerEvent.position);
                              setState(() {
                                _selectionCurrent = local;

                                final bounds = Rect.fromPoints(
                                    _selectionStart!, _selectionCurrent!);
                                _selectedAssets = assets.where((asset) {
                                  final cx = asset.coordinates.x *
                                      constraints.maxWidth;
                                  final cy = asset.coordinates.y *
                                      constraints.maxHeight;
                                  final halfW = (asset.size.width *
                                          constraints.maxWidth) /
                                      2;
                                  final halfH = (asset.size.height *
                                          constraints.maxHeight) /
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
                            AiContextMenuWrapper(
                              menuItems: buildHamburgerMenuItems(
                                pageName: _currentPage ?? 'Untitled',
                                assets: assets,
                              ),
                              child: FloatingActionButton(
                                mini: true,
                                heroTag: 'hamburger',
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                onPressed: () =>
                                    setState(() => _showPalette = true),
                                child: const Icon(Icons.menu,
                                    color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FloatingActionButton(
                              mini: true,
                              heroTag: 'save',
                              backgroundColor: _hasUnsavedChanges
                                  ? Colors.orange
                                  : Theme.of(context).colorScheme.primary,
                              onPressed: _saveToPrefs,
                              child:
                                  const Icon(Icons.save, color: Colors.white),
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
                                child:
                                    const Icon(Icons.add, color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              FloatingActionButton(
                                mini: true,
                                heroTag: 'decrease',
                                onPressed: () => _adjustSelectedAssetsSize(0.9),
                                child: const Icon(Icons.remove,
                                    color: Colors.white),
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
                                _isSelectMode
                                    ? Icons.select_all
                                    : Icons.pan_tool,
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
            )),
          ],
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
            onChanged: (value) => setState(() => _paletteSearchQuery = value),
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
              return AiContextMenuWrapper(
                menuItems: buildPaletteItemMenuItems(
                  asset: previewAsset,
                  pageName: _currentPage,
                  existingAssetSummary: summarizeExistingAssets(assets),
                ),
                child: _PaletteItem(
                  assetType: entry.key,
                  asset: previewAsset,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showConfigDialog(Asset asset) {
    ref.read(currentPageAssetsProvider.notifier).state = assets;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: IntrinsicWidth(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: asset.configure(context)),
                      if (asset is BaseAsset)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: TechDocPicker(
                            selectedDocId: asset.techDocId,
                            onChanged: (id) {
                              asset.techDocId = id;
                            },
                          ),
                        ),
                    ],
                  ),
                ),
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
    final currentPagePath = _currentPage ?? _temporaryPages.keys.firstOrNull;
    final displayName = currentPagePath != null
        ? (_temporaryPages[currentPagePath]?.menuItem.label ?? 'Empty')
        : 'Empty';
    final currentPage = currentPagePath != null
        ? _temporaryPages[currentPagePath]
        : null;

    final selector = GestureDetector(
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
            Text(displayName),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );

    // Wrap with right-click context menu that includes both direct actions
    // (Create New Page) and AI chat actions when page data is available.
    if (currentPagePath != null && currentPage != null) {
      return GestureDetector(
        onSecondaryTapUp: (details) {
          _showPageSelectorContextMenu(
            details.globalPosition,
            currentPagePath,
            currentPage,
          );
        },
        child: selector,
      );
    }

    // No page selected -- still allow right-click to create a new page.
    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showCreateNewPageContextMenu(details.globalPosition);
      },
      child: selector,
    );
  }

  /// Shows a context menu for the page selector with "Create New Page" and
  /// AI actions. Intercepts the [kCreateNewPageAction] sentinel to open the
  /// page manager dialog instead of chat.
  Future<void> _showPageSelectorContextMenu(
    Offset position,
    String pagePath,
    AssetPage page,
  ) async {
    final menuItems = buildPageSelectorMenuItems(pagePath, page);

    final result = await showMenu<int>(
      context: context,
      useRootNavigator: true,
      clipBehavior: Clip.antiAlias,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        for (var i = 0; i < menuItems.length; i++) ...[
          // Add a divider after "Create New Page" to separate direct actions
          // from AI actions.
          if (i == 1)
            const PopupMenuDivider(),
          PopupMenuItem<int>(
            value: i,
            child: ListTile(
              leading: Icon(menuItems[i].icon),
              title: Text(menuItems[i].label),
              dense: true,
            ),
          ),
        ],
      ],
    );

    if (result == null || !mounted) return;

    final item = menuItems[result];

    // Intercept "Create New Page" -- open the page manager dialog directly.
    if (item.prefillText == kCreateNewPageAction) {
      _showPageManagerDialog();
      return;
    }

    // Otherwise delegate to AI chat action.
    if (item.sendImmediately) {
      AiContextAction.openChatAndSend(ref: ref, message: item.prefillText);
    } else {
      ChatContext? chatContext;
      if (item.contextBlock != null) {
        chatContext = ChatContext(
          label: item.contextLabel ?? item.label,
          type: item.contextType,
          contextBlock: item.contextBlock!,
        );
      }
      AiContextAction.openChat(
        ref: ref,
        prefillText: item.prefillText,
        context: chatContext,
      );
    }
  }

  /// Shows a minimal context menu with just "Create New Page" when no page
  /// is currently selected.
  Future<void> _showCreateNewPageContextMenu(Offset position) async {
    final result = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      clipBehavior: Clip.antiAlias,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'create',
          child: ListTile(
            leading: Icon(Icons.add_circle_outline),
            title: Text('Create New Page'),
            dense: true,
          ),
        ),
      ],
    );

    if (result == 'create' && mounted) {
      _showPageManagerDialog();
    }
  }

  /// Returns page paths that are not referenced as children of any OTHER page.
  List<String> _getRootPageNames() {
    final childPaths = <String>{};
    for (final entry in _temporaryPages.entries) {
      PageManager.collectChildPaths(
          entry.value.menuItem.children, childPaths, entry.key);
    }
    final roots = _temporaryPages.keys
        .where((path) => !childPaths.contains(path))
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
    final isSection = hasChildren;

    return Padding(
      key: ValueKey(pageName),
      padding: EdgeInsets.only(left: depth > 0 ? 20.0 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiContextMenuWrapper(
            menuItems: [
              AiMenuItem(
                label: 'Describe this page',
                prefillText:
                    'Describe page "$displayName" (key: $pageName) — what assets does it contain and what is it monitoring?',
              ),
              AiMenuItem(
                label: 'Improve layout',
                prefillText:
                    'Review page "$displayName" (key: $pageName) and suggest layout improvements or missing assets.',
              ),
              AiMenuItem(
                label: 'Duplicate with AI',
                prefillText:
                    'Create a new page similar to "$displayName" (key: $pageName) but for [describe the target system].',
              ),
            ],
            child: ListTile(
              dense: true,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReorderableDragStartListener(
                    index: reorderIndex,
                    child: const Icon(Icons.drag_handle,
                        size: 20, color: Colors.grey),
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
                  fontWeight: isSelected && !isSection
                      ? FontWeight.bold
                      : FontWeight.normal,
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
                    onPressed: () =>
                        _editPage(pageName, page, dialogSetState, dialogContext),
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    onPressed: () =>
                        _deletePage(pageName, dialogSetState, dialogContext),
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
                  if (page.menuItem.children[i].path == pageName)
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
                      page.menuItem.children[i].path ?? '',
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
              child:
                  const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
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
            color:
                isSelected ? Theme.of(dialogContext).colorScheme.primary : null,
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
        final childPath = children[i].path ?? '';
        final childPage = _temporaryPages[childPath];
        if (childPage != null) {
          _temporaryPages[childPath] = AssetPage(
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
                // Update the child MenuItem in the parent's children list
                final parentPage = _temporaryPages[mapKey]!;
                final updatedChildren = parentPage.menuItem.children.map((c) {
                  if (c.path == childItem.path) {
                    return MenuItem(
                      label: updatedPage.menuItem.label,
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

  String _buildBasePath(String? parentPath) {
    if (parentPath == null) return '';
    final page = _temporaryPages[parentPath];
    if (page == null) return '';
    // Since all pages/sections now have paths, just use the parent's path
    return page.menuItem.path ?? '';
  }

  String? _findParentOf(String childPath) {
    for (final entry in _temporaryPages.entries) {
      if (entry.key != childPath &&
          entry.value.menuItem.children.any((c) => c.path == childPath)) {
        return entry.key;
      }
    }
    return null;
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
            basePath: _buildBasePath(parentName),
            onSave: (page) {
              final newPath = page.menuItem.path ?? '';
              if (_temporaryPages.containsKey(newPath)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                        'A page with path "$newPath" already exists. Please choose a different name.'),
                  ),
                );
                return;
              }
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
                _temporaryPages[newPath] = pageWithPriority;
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
                  _currentPage = newPath;
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
    String pagePath,
    AssetPage page,
    StateSetter dialogSetState,
    BuildContext dialogContext,
  ) {
    final isSection = page.menuItem.children.isNotEmpty;
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit'),
        content: SizedBox(
          width: 400,
          child: CreatePageWidget(
            initialPage: page,
            isSection: isSection,
            basePath: _buildBasePath(_findParentOf(pagePath)),
            onSave: (updatedPage) {
              final newPath = updatedPage.menuItem.path ?? '';
              if (newPath != pagePath && _temporaryPages.containsKey(newPath)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                        'A page with path "$newPath" already exists. Please choose a different name.'),
                  ),
                );
                return;
              }
              setState(() {
                if (newPath != pagePath) {
                  _temporaryPages.remove(pagePath);
                  // Update parent references
                  _updateChildPathInParents(
                      pagePath, newPath, updatedPage.menuItem);
                  if (_currentPage == pagePath) {
                    _currentPage = newPath;
                  }
                }
                _temporaryPages[newPath] = updatedPage;
                _updateCurrentJson();
              });
              dialogSetState(() {});
            },
          ),
        ),
      ),
    );
  }

  void _updateChildPathInParents(
      String oldPath, String newPath, MenuItem newMenuItem) {
    final updates = <String, AssetPage>{};
    for (final entry in _temporaryPages.entries) {
      final page = entry.value;
      final updated = _updatePathInChildren(
          page.menuItem.children, oldPath, newPath, newMenuItem);
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

  List<MenuItem>? _updatePathInChildren(List<MenuItem> children, String oldPath,
      String newPath, MenuItem newMenuItem) {
    bool changed = false;
    final result = children.map((child) {
      MenuItem updated = child;
      if (child.path == oldPath) {
        changed = true;
        updated = MenuItem(
          label: newMenuItem.label,
          path: newPath,
          icon: newMenuItem.icon,
          children: child.children,
        );
      }
      final subUpdated = _updatePathInChildren(
          updated.children, oldPath, newPath, newMenuItem);
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
    String pagePath,
    StateSetter dialogSetState,
    BuildContext dialogContext,
  ) {
    final displayName = _temporaryPages[pagePath]?.menuItem.label ?? pagePath;
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Delete "$displayName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _temporaryPages.remove(pagePath);
                // Remove from parent children lists
                _removeChildFromParents(pagePath);
                if (_currentPage == pagePath) {
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

  void _removeChildFromParents(String path) {
    final updates = <String, AssetPage>{};
    for (final entry in _temporaryPages.entries) {
      final page = entry.value;
      final updated = _removeFromChildren(page.menuItem.children, path);
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

  List<MenuItem>? _removeFromChildren(List<MenuItem> children, String path) {
    bool changed = false;
    final result = <MenuItem>[];
    for (final child in children) {
      if (child.path == path) {
        changed = true;
        continue;
      }
      final subUpdated = _removeFromChildren(child.children, path);
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
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                child: ClipRect(
                  child: IgnorePointer(
                    child: asset.build(context),
                  ),
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
