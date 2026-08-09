/// Helpers for searching a UMAS browse tree by name OR by full dotted path.
///
/// Extracted from `tool/umas_cli.dart` after a 2026-05-20 live-PLC defect:
/// the CLI's `read` subcommand silently dropped every dotted-path query
/// because the inline matcher compared only against [UmasVariableTreeNode.name]
/// (the leaf segment). Operators following the standard FB-browse UX —
/// `M_F2_RC_01.p_CMD_xManFwd` — saw "Variable not found" even though
/// [UmasClient.readVariableByName] resolved the same path through the
/// symbol cache without a hitch.
///
/// Centralising the matcher here keeps the CLI and any future browse-tree
/// tooling on one well-tested code path.
library;

import 'umas_types.dart';

/// Returns the first node in [roots] whose [UmasVariableTreeNode.path]
/// matches [query] exactly, or — falling back to the legacy behaviour —
/// whose leaf [UmasVariableTreeNode.name] matches.
///
/// Path matches always win over name matches: when a leaf segment is
/// duplicated across sibling FBs (e.g. every `M_*` motor FB has a
/// `p_CMD_xManFwd` BOOL) the dotted query disambiguates the hit.
///
/// Returns `null` when nothing matches. Traversal is pre-order, root-first,
/// and aborts as soon as a path match is found at any depth, but it
/// continues scanning siblings until the entire tree is exhausted before
/// settling on a leaf-name fallback. This guarantees a stable, predictable
/// resolution regardless of insertion order at the call site.
UmasVariableTreeNode? findUmasNodeByPathOrName(
  List<UmasVariableTreeNode> roots,
  String query,
) {
  UmasVariableTreeNode? pathHit;
  UmasVariableTreeNode? nameHit;

  void walk(UmasVariableTreeNode n) {
    if (pathHit != null) return;
    if (n.path == query) {
      pathHit = n;
      return;
    }
    if (nameHit == null && n.name == query) {
      nameHit = n;
    }
    for (final c in n.children) {
      walk(c);
      if (pathHit != null) return;
    }
  }

  for (final r in roots) {
    walk(r);
    if (pathHit != null) break;
  }
  return pathHit ?? nameHit;
}
