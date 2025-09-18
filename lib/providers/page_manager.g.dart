// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'page_manager.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(pageManager)
const pageManagerProvider = PageManagerProvider._();

final class PageManagerProvider extends $FunctionalProvider<
        AsyncValue<PageManager>, PageManager, FutureOr<PageManager>>
    with $FutureModifier<PageManager>, $FutureProvider<PageManager> {
  const PageManagerProvider._()
      : super(
          from: null,
          argument: null,
          retry: null,
          name: r'pageManagerProvider',
          isAutoDispose: false,
          dependencies: null,
          $allTransitiveDependencies: null,
        );

  @override
  String debugGetCreateSourceHash() => _$pageManagerHash();

  @$internal
  @override
  $FutureProviderElement<PageManager> $createElement(
          $ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<PageManager> create(Ref ref) {
    return pageManager(ref);
  }
}

String _$pageManagerHash() => r'8e78a565427ac22cf40ec4164033b082c173e163';
