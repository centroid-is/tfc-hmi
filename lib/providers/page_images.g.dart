// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'page_images.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$pageImageStoreHash() => r'a4b042b0797eb4ce5b0584973424f05c9e5b82af';

/// The store the image asset and the page editor share for image bytes.
///
/// Tests override this with a store on the same fake preferences the page
/// manager persists into, so saved pages and their image blobs land in one
/// place.
///
/// Copied from [pageImageStore].
@ProviderFor(pageImageStore)
final pageImageStoreProvider = FutureProvider<PageImageStore>.internal(
  pageImageStore,
  name: r'pageImageStoreProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$pageImageStoreHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PageImageStoreRef = FutureProviderRef<PageImageStore>;
String _$pageImageBytesHash() => r'ef1fa03f7a413d3ead0c3266c6234a299b344846';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// Bytes of one stored page image; null when the id is unknown.
///
/// Copied from [pageImageBytes].
@ProviderFor(pageImageBytes)
const pageImageBytesProvider = PageImageBytesFamily();

/// Bytes of one stored page image; null when the id is unknown.
///
/// Copied from [pageImageBytes].
class PageImageBytesFamily extends Family<AsyncValue<Uint8List?>> {
  /// Bytes of one stored page image; null when the id is unknown.
  ///
  /// Copied from [pageImageBytes].
  const PageImageBytesFamily();

  /// Bytes of one stored page image; null when the id is unknown.
  ///
  /// Copied from [pageImageBytes].
  PageImageBytesProvider call(
    String imageId,
  ) {
    return PageImageBytesProvider(
      imageId,
    );
  }

  @override
  PageImageBytesProvider getProviderOverride(
    covariant PageImageBytesProvider provider,
  ) {
    return call(
      provider.imageId,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'pageImageBytesProvider';
}

/// Bytes of one stored page image; null when the id is unknown.
///
/// Copied from [pageImageBytes].
class PageImageBytesProvider extends AutoDisposeFutureProvider<Uint8List?> {
  /// Bytes of one stored page image; null when the id is unknown.
  ///
  /// Copied from [pageImageBytes].
  PageImageBytesProvider(
    String imageId,
  ) : this._internal(
          (ref) => pageImageBytes(
            ref as PageImageBytesRef,
            imageId,
          ),
          from: pageImageBytesProvider,
          name: r'pageImageBytesProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$pageImageBytesHash,
          dependencies: PageImageBytesFamily._dependencies,
          allTransitiveDependencies:
              PageImageBytesFamily._allTransitiveDependencies,
          imageId: imageId,
        );

  PageImageBytesProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.imageId,
  }) : super.internal();

  final String imageId;

  @override
  Override overrideWith(
    FutureOr<Uint8List?> Function(PageImageBytesRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PageImageBytesProvider._internal(
        (ref) => create(ref as PageImageBytesRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        imageId: imageId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Uint8List?> createElement() {
    return _PageImageBytesProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PageImageBytesProvider && other.imageId == imageId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, imageId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PageImageBytesRef on AutoDisposeFutureProviderRef<Uint8List?> {
  /// The parameter `imageId` of this provider.
  String get imageId;
}

class _PageImageBytesProviderElement
    extends AutoDisposeFutureProviderElement<Uint8List?>
    with PageImageBytesRef {
  _PageImageBytesProviderElement(super.provider);

  @override
  String get imageId => (origin as PageImageBytesProvider).imageId;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
