import 'dart:typed_data';

import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../page_creator/assets/image_store.dart';
import 'preferences.dart';

part 'page_images.g.dart';

/// The store the image asset and the page editor share for image bytes.
///
/// Tests override this with a store on the same fake preferences the page
/// manager persists into, so saved pages and their image blobs land in one
/// place.
@Riverpod(keepAlive: true)
Future<PageImageStore> pageImageStore(Ref ref) async {
  final prefs = await ref.watch(preferencesProvider.future);
  return PageImageStore(prefs);
}

/// Bytes of one stored page image; null when the id is unknown.
@riverpod
Future<Uint8List?> pageImageBytes(Ref ref, String imageId) async {
  final store = await ref.watch(pageImageStoreProvider.future);
  return store.load(imageId);
}
