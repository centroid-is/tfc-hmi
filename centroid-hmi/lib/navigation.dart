/// The navigation menu's shape, separated from `main.dart` so it can be
/// tested without booting the app: which built-ins sit at the top level,
/// what god mode reveals under Advanced, and where `/` falls back to when
/// the Home page has been deleted.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:tfc/core/feature_flags.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/routes.dart';

/// Top-level menu entries the app itself provides. They are not pages in the
/// page editor, but they share the top level with the pages and order with
/// them through `PageManager.sortTopLevel`. Home is *not* here: Home is an
/// ordinary page in the page manager, deletable and reorderable like any
/// other.
const builtinTopLevelMenuItems = <MenuItem>[
  MenuItem(label: 'Alarm View', path: AppRoutes.alarmView, icon: Icons.alarm),
  MenuItem(label: 'History View', path: AppRoutes.historyView, icon: Icons.history),
];

/// Assembles the whole top-level menu in registration order: the pages, the
/// built-ins, then Advanced pinned last. The persisted top-level order is
/// applied afterwards by `PageManager.sortTopLevel` on the registry.
///
/// God mode (`TFC_GOD=true`) only controls menu visibility — the gated
/// entries' routes stay registered either way, matching how the Page Editor
/// has always been gated. Server Config stays visible without god mode:
/// commissioning a Windows HMI (pointing it at a PLC) must not require an
/// environment variable, and on non-Linux non-god installs it is the only
/// thing keeping Advanced alive. Key Repository surfaces stored secrets, so
/// it is god-gated.
List<MenuItem> buildTopLevelMenuItems({
  required bool god,
  required bool isLinux,
  required List<MenuItem> pageMenuItems,
}) {
  final advancedChildren = <MenuItem>[
    if (isLinux) MenuItem(label: 'IP Settings', path: '/advanced/ip-settings', icon: Icons.settings_ethernet),
    if (isLinux) MenuItem(label: 'About Linux', path: '/advanced/about-linux', icon: Icons.info),
    if (god) MenuItem(label: 'Page Editor', path: '/advanced/page-editor', icon: Icons.edit),
    if (god) MenuItem(label: 'Preferences', path: '/advanced/preferences', icon: Icons.settings),
    if (god) MenuItem(label: 'Alarm Editor', path: '/advanced/alarm-editor', icon: Icons.alarm),
    MenuItem(label: 'Server Config', path: '/advanced/server-config', icon: FontAwesomeIcons.server.data),
    if (god) MenuItem(label: 'Key Repository', path: '/advanced/key-repository', icon: FontAwesomeIcons.key.data),
    if (kKnowledgeEnabled)
      MenuItem(label: 'Knowledge Base', path: '/advanced/knowledge-base', icon: Icons.library_books),
  ];

  return [
    ...pageMenuItems,
    ...builtinTopLevelMenuItems,
    // An Advanced section with nothing in it would just be a dead menu entry.
    if (advancedChildren.isNotEmpty)
      MenuItem(
        label: 'Advanced',
        path: '/advanced',
        icon: Icons.settings,
        children: advancedChildren,
      ),
  ];
}

/// Whether this process runs in god mode.
bool get environmentVariableIsGod => Platform.environment['TFC_GOD'] == 'true';

/// Depth-first first path in [items] — where `/` and refused pages fall back
/// to when the Home page itself is gone. Null when no page is reachable at
/// all.
String? firstMenuPath(List<MenuItem> items) {
  for (final item in items) {
    final path = item.path;
    if (path != null && path.isNotEmpty) return path;
    final childPath = firstMenuPath(item.children);
    if (childPath != null) return childPath;
  }
  return null;
}
