// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AssetPage _$AssetPageFromJson(Map<String, dynamic> json) => AssetPage(
      menuItem: MenuItem.fromJson(json['menu_item'] as Map<String, dynamic>),
      assets: const AssetListConverter().fromJson(json['assets'] as List),
    );

Map<String, dynamic> _$AssetPageToJson(AssetPage instance) => <String, dynamic>{
      'menu_item': instance.menuItem,
      'assets': const AssetListConverter().toJson(instance.assets),
    };
