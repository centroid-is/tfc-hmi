import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../page_creator/assets/common.dart';

/// Holds the asset list for the page currently being edited.
/// Set by PageEditor before opening a config dialog so that
/// config editors can discover sibling assets (e.g. OptionVariable).
final currentPageAssetsProvider = StateProvider<List<Asset>>((ref) => []);
