// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'menu_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MenuItem _$MenuItemFromJson(Map<String, dynamic> json) => MenuItem(
      label: json['label'] as String,
      icon: const IconDataConverter().fromJson(json['icon'] as String),
      children: (json['children'] as List<dynamic>?)
              ?.map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      path: json['path'] as String?,
    );

Map<String, dynamic> _$MenuItemToJson(MenuItem instance) => <String, dynamic>{
      'label': instance.label,
      'path': instance.path,
      'icon': const IconDataConverter().toJson(instance.icon),
      'children': instance.children,
    };
