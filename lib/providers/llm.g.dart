// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$llmApiKeyHash() => r'c37489017d96d433b1f64109d995f98843e8eff8';

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

/// Reads the API key for the given [type] from secure storage.
///
/// Returns null if no key is stored.
///
/// Copied from [llmApiKey].
@ProviderFor(llmApiKey)
const llmApiKeyProvider = LlmApiKeyFamily();

/// Reads the API key for the given [type] from secure storage.
///
/// Returns null if no key is stored.
///
/// Copied from [llmApiKey].
class LlmApiKeyFamily extends Family<AsyncValue<String?>> {
  /// Reads the API key for the given [type] from secure storage.
  ///
  /// Returns null if no key is stored.
  ///
  /// Copied from [llmApiKey].
  const LlmApiKeyFamily();

  /// Reads the API key for the given [type] from secure storage.
  ///
  /// Returns null if no key is stored.
  ///
  /// Copied from [llmApiKey].
  LlmApiKeyProvider call(
    LlmProviderType type,
  ) {
    return LlmApiKeyProvider(
      type,
    );
  }

  @override
  LlmApiKeyProvider getProviderOverride(
    covariant LlmApiKeyProvider provider,
  ) {
    return call(
      provider.type,
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
  String? get name => r'llmApiKeyProvider';
}

/// Reads the API key for the given [type] from secure storage.
///
/// Returns null if no key is stored.
///
/// Copied from [llmApiKey].
class LlmApiKeyProvider extends FutureProvider<String?> {
  /// Reads the API key for the given [type] from secure storage.
  ///
  /// Returns null if no key is stored.
  ///
  /// Copied from [llmApiKey].
  LlmApiKeyProvider(
    LlmProviderType type,
  ) : this._internal(
          (ref) => llmApiKey(
            ref as LlmApiKeyRef,
            type,
          ),
          from: llmApiKeyProvider,
          name: r'llmApiKeyProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$llmApiKeyHash,
          dependencies: LlmApiKeyFamily._dependencies,
          allTransitiveDependencies: LlmApiKeyFamily._allTransitiveDependencies,
          type: type,
        );

  LlmApiKeyProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.type,
  }) : super.internal();

  final LlmProviderType type;

  @override
  Override overrideWith(
    FutureOr<String?> Function(LlmApiKeyRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: LlmApiKeyProvider._internal(
        (ref) => create(ref as LlmApiKeyRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        type: type,
      ),
    );
  }

  @override
  FutureProviderElement<String?> createElement() {
    return _LlmApiKeyProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is LlmApiKeyProvider && other.type == type;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, type.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin LlmApiKeyRef on FutureProviderRef<String?> {
  /// The parameter `type` of this provider.
  LlmProviderType get type;
}

class _LlmApiKeyProviderElement extends FutureProviderElement<String?>
    with LlmApiKeyRef {
  _LlmApiKeyProviderElement(super.provider);

  @override
  LlmProviderType get type => (origin as LlmApiKeyProvider).type;
}

String _$llmBaseUrlHash() => r'1fd204db535c0aff768b06f94751b898f9ac0965';

/// Reads the custom base URL for the given [type] from preferences.
///
/// Returns null if no custom base URL is stored (uses provider default).
///
/// Copied from [llmBaseUrl].
@ProviderFor(llmBaseUrl)
const llmBaseUrlProvider = LlmBaseUrlFamily();

/// Reads the custom base URL for the given [type] from preferences.
///
/// Returns null if no custom base URL is stored (uses provider default).
///
/// Copied from [llmBaseUrl].
class LlmBaseUrlFamily extends Family<AsyncValue<String?>> {
  /// Reads the custom base URL for the given [type] from preferences.
  ///
  /// Returns null if no custom base URL is stored (uses provider default).
  ///
  /// Copied from [llmBaseUrl].
  const LlmBaseUrlFamily();

  /// Reads the custom base URL for the given [type] from preferences.
  ///
  /// Returns null if no custom base URL is stored (uses provider default).
  ///
  /// Copied from [llmBaseUrl].
  LlmBaseUrlProvider call(
    LlmProviderType type,
  ) {
    return LlmBaseUrlProvider(
      type,
    );
  }

  @override
  LlmBaseUrlProvider getProviderOverride(
    covariant LlmBaseUrlProvider provider,
  ) {
    return call(
      provider.type,
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
  String? get name => r'llmBaseUrlProvider';
}

/// Reads the custom base URL for the given [type] from preferences.
///
/// Returns null if no custom base URL is stored (uses provider default).
///
/// Copied from [llmBaseUrl].
class LlmBaseUrlProvider extends FutureProvider<String?> {
  /// Reads the custom base URL for the given [type] from preferences.
  ///
  /// Returns null if no custom base URL is stored (uses provider default).
  ///
  /// Copied from [llmBaseUrl].
  LlmBaseUrlProvider(
    LlmProviderType type,
  ) : this._internal(
          (ref) => llmBaseUrl(
            ref as LlmBaseUrlRef,
            type,
          ),
          from: llmBaseUrlProvider,
          name: r'llmBaseUrlProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$llmBaseUrlHash,
          dependencies: LlmBaseUrlFamily._dependencies,
          allTransitiveDependencies:
              LlmBaseUrlFamily._allTransitiveDependencies,
          type: type,
        );

  LlmBaseUrlProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.type,
  }) : super.internal();

  final LlmProviderType type;

  @override
  Override overrideWith(
    FutureOr<String?> Function(LlmBaseUrlRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: LlmBaseUrlProvider._internal(
        (ref) => create(ref as LlmBaseUrlRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        type: type,
      ),
    );
  }

  @override
  FutureProviderElement<String?> createElement() {
    return _LlmBaseUrlProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is LlmBaseUrlProvider && other.type == type;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, type.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin LlmBaseUrlRef on FutureProviderRef<String?> {
  /// The parameter `type` of this provider.
  LlmProviderType get type;
}

class _LlmBaseUrlProviderElement extends FutureProviderElement<String?>
    with LlmBaseUrlRef {
  _LlmBaseUrlProviderElement(super.provider);

  @override
  LlmProviderType get type => (origin as LlmBaseUrlProvider).type;
}

String _$selectedLlmProviderHash() =>
    r'70802b57d80c385964941b9da44595a25a4178b9';

/// Reads the currently selected LLM provider type from preferences.
///
/// Returns null if no provider has been selected.
///
/// Copied from [selectedLlmProvider].
@ProviderFor(selectedLlmProvider)
final selectedLlmProviderProvider = FutureProvider<LlmProviderType?>.internal(
  selectedLlmProvider,
  name: r'selectedLlmProviderProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$selectedLlmProviderHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SelectedLlmProviderRef = FutureProviderRef<LlmProviderType?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
