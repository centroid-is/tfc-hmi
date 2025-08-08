import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

part 'menu_item.g.dart';

@JsonSerializable()
class MenuItem {
  final String label;
  final String? path;
  @IconDataConverter()
  final IconData icon;
  final List<MenuItem> children;

  const MenuItem({
    required this.label,
    required this.icon,
    this.children = const [],
    this.path,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is MenuItem &&
        label == other.label &&
        path == other.path &&
        icon == other.icon;
  }

  factory MenuItem.fromJson(Map<String, dynamic> json) =>
      _$MenuItemFromJson(json);
  Map<String, dynamic> toJson() => _$MenuItemToJson(this);
}

class IconDataConverter implements JsonConverter<IconData, String> {
  static const IconData baadericon =
      IconData(0xe800, fontFamily: "Baader", fontPackage: "tfc");

  const IconDataConverter();

  @override
  IconData fromJson(String json) {
    // Use a predefined map of constant icons instead of creating new instances
    return _getIconByName(json);
  }

  @override
  String toJson(IconData iconData) {
    // Store icon name instead of full IconData properties
    return _getIconName(iconData);
  }

  // Predefined map of constant icons
  static IconData _getIconByName(String name) {
    switch (name) {
      case 'home':
        return Icons.home;
      case 'settings':
        return Icons.settings;
      case 'dashboard':
        return Icons.dashboard;
      case 'person':
        return Icons.person;
      case 'menu':
        return Icons.menu;
      case 'close':
        return Icons.close;
      case 'arrow_back':
        return Icons.arrow_back;
      case 'arrow_forward':
        return Icons.arrow_forward;
      case 'add':
        return Icons.add;
      case 'edit':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      case 'search':
        return Icons.search;
      case 'notifications':
        return Icons.notifications;
      case 'favorite':
        return Icons.favorite;
      case 'star':
        return Icons.star;
      case 'info':
        return Icons.info;
      case 'warning':
        return Icons.warning;
      case 'error':
        return Icons.error;
      case 'check':
        return Icons.check;
      case 'cancel':
        return Icons.cancel;
      case 'refresh':
        return Icons.refresh;
      case 'download':
        return Icons.download;
      case 'upload':
        return Icons.upload;
      case 'print':
        return Icons.print;
      case 'share':
        return Icons.share;
      case 'help':
        return Icons.help;
      case 'visibility':
        return Icons.visibility;
      case 'visibility_off':
        return Icons.visibility_off;
      case 'lock':
        return Icons.lock;
      case 'unlock':
        return Icons.lock_open;
      case 'key':
        return Icons.key;
      case 'security':
        return Icons.security;
      case 'account_circle':
        return Icons.account_circle;
      case 'admin_panel_settings':
        return Icons.admin_panel_settings;
      case 'analytics':
        return Icons.analytics;
      case 'assessment':
        return Icons.assessment;
      case 'bar_chart':
        return Icons.bar_chart;
      case 'pie_chart':
        return Icons.pie_chart;
      case 'timeline':
        return Icons.timeline;
      case 'trending_up':
        return Icons.trending_up;
      case 'trending_down':
        return Icons.trending_down;
      case 'speed':
        return Icons.speed;
      case 'timer':
        return Icons.timer;
      case 'schedule':
        return Icons.schedule;
      case 'event':
        return Icons.event;
      case 'calendar_today':
        return Icons.calendar_today;
      case 'today':
        return Icons.today;
      case 'date_range':
        return Icons.date_range;
      case 'access_time':
        return Icons.access_time;
      case 'update':
        return Icons.update;
      case 'sync':
        return Icons.sync;
      case 'sync_problem':
        return Icons.sync_problem;
      case 'cloud':
        return Icons.cloud;
      case 'cloud_upload':
        return Icons.cloud_upload;
      case 'cloud_download':
        return Icons.cloud_download;
      case 'storage':
        return Icons.storage;
      case 'folder':
        return Icons.folder;
      case 'folder_open':
        return Icons.folder_open;
      case 'description':
        return Icons.description;
      case 'article':
        return Icons.article;
      case 'note':
        return Icons.note;
      case 'text_snippet':
        return Icons.text_snippet;
      case 'code':
        return Icons.code;
      case 'bug_report':
        return Icons.bug_report;
      case 'build':
        return Icons.build;
      case 'construction':
        return Icons.construction;
      case 'engineering':
        return Icons.engineering;
      case 'science':
        return Icons.science;
      case 'biotech':
        return Icons.biotech;
      case 'precision_manufacturing':
        return Icons.precision_manufacturing;
      case 'factory':
        return Icons.factory;
      case 'business':
        return Icons.business;
      case 'domain':
        return Icons.domain;
      case 'apartment':
        return Icons.apartment;
      case 'location_on':
        return Icons.location_on;
      case 'place':
        return Icons.place;
      case 'navigation':
        return Icons.navigation;
      case 'directions':
        return Icons.directions;
      case 'map':
        return Icons.map;
      case 'satellite':
        return Icons.satellite;
      case 'terrain':
        return Icons.terrain;
      case 'layers':
        return Icons.layers;
      case 'filter_list':
        return Icons.filter_list;
      case 'sort':
        return Icons.sort;
      case 'filter':
        return Icons.filter;
      case 'tune':
        return Icons.tune;
      case 'view_list':
        return Icons.view_list;
      case 'view_module':
        return Icons.view_module;
      case 'view_quilt':
        return Icons.view_quilt;
      case 'view_agenda':
        return Icons.view_agenda;
      case 'view_week':
        return Icons.view_week;
      case 'view_day':
        return Icons.view_day;
      case 'view_headline':
        return Icons.view_headline;
      case 'view_carousel':
        return Icons.view_carousel;
      case 'view_column':
        return Icons.view_column;
      case 'view_stream':
        return Icons.view_stream;
      case 'view_comfy':
        return Icons.view_comfy;
      case 'view_compact':
        return Icons.view_compact;
      case 'view_sidebar':
        return Icons.view_sidebar;
      case 'view_array':
        return Icons.view_array;
      case 'view_timeline':
        return Icons.view_timeline;
      case 'view_kanban':
        return Icons.view_kanban;
      case 'view_cozy':
        return Icons.view_cozy;
      case 'view_comfortable':
        return Icons.view_comfortable;
      case 'view_in_ar':
        return Icons.view_in_ar;
      case 'view_agenda_outlined':
        return Icons.view_agenda_outlined;
      case 'view_agenda_rounded':
        return Icons.view_agenda_rounded;
      case 'view_agenda_sharp':
        return Icons.view_agenda_sharp;
      case 'baader':
        return baadericon;
      default:
        return Icons.help; // fallback icon
    }
  }

  // Helper method to get icon name from IconData
  static String _getIconName(IconData iconData) {
    // This is a simplified mapping - you might need to expand this
    // based on your actual icon usage
    if (iconData == Icons.home) return 'home';
    if (iconData == Icons.settings) return 'settings';
    if (iconData == Icons.dashboard) return 'dashboard';
    if (iconData == Icons.person) return 'person';
    if (iconData == Icons.menu) return 'menu';
    if (iconData == Icons.close) return 'close';
    if (iconData == Icons.arrow_back) return 'arrow_back';
    if (iconData == Icons.arrow_forward) return 'arrow_forward';
    if (iconData == Icons.add) return 'add';
    if (iconData == Icons.edit) return 'edit';
    if (iconData == Icons.delete) return 'delete';
    if (iconData == Icons.search) return 'search';
    if (iconData == Icons.notifications) return 'notifications';
    if (iconData == Icons.favorite) return 'favorite';
    if (iconData == Icons.star) return 'star';
    if (iconData == Icons.info) return 'info';
    if (iconData == Icons.warning) return 'warning';
    if (iconData == Icons.error) return 'error';
    if (iconData == Icons.check) return 'check';
    if (iconData == Icons.cancel) return 'cancel';
    if (iconData == Icons.refresh) return 'refresh';
    if (iconData == Icons.download) return 'download';
    if (iconData == Icons.upload) return 'upload';
    if (iconData == Icons.print) return 'print';
    if (iconData == Icons.share) return 'share';
    if (iconData == Icons.help) return 'help';
    if (iconData == Icons.visibility) return 'visibility';
    if (iconData == Icons.visibility_off) return 'visibility_off';
    if (iconData == Icons.lock) return 'lock';
    if (iconData == Icons.lock_open) return 'unlock';
    if (iconData == Icons.key) return 'key';
    if (iconData == Icons.security) return 'security';
    if (iconData == Icons.account_circle) return 'account_circle';
    if (iconData == Icons.admin_panel_settings) return 'admin_panel_settings';
    if (iconData == Icons.analytics) return 'analytics';
    if (iconData == Icons.assessment) return 'assessment';
    if (iconData == Icons.bar_chart) return 'bar_chart';
    if (iconData == Icons.pie_chart) return 'pie_chart';
    if (iconData == Icons.timeline) return 'timeline';
    if (iconData == Icons.trending_up) return 'trending_up';
    if (iconData == Icons.trending_down) return 'trending_down';
    if (iconData == Icons.speed) return 'speed';
    if (iconData == Icons.timer) return 'timer';
    if (iconData == Icons.schedule) return 'schedule';
    if (iconData == Icons.event) return 'event';
    if (iconData == Icons.calendar_today) return 'calendar_today';
    if (iconData == Icons.today) return 'today';
    if (iconData == Icons.date_range) return 'date_range';
    if (iconData == Icons.access_time) return 'access_time';
    if (iconData == Icons.update) return 'update';
    if (iconData == Icons.sync) return 'sync';
    if (iconData == Icons.sync_problem) return 'sync_problem';
    if (iconData == Icons.cloud) return 'cloud';
    if (iconData == Icons.cloud_upload) return 'cloud_upload';
    if (iconData == Icons.cloud_download) return 'cloud_download';
    if (iconData == Icons.storage) return 'storage';
    if (iconData == Icons.folder) return 'folder';
    if (iconData == Icons.folder_open) return 'folder_open';
    if (iconData == Icons.description) return 'description';
    if (iconData == Icons.article) return 'article';
    if (iconData == Icons.note) return 'note';
    if (iconData == Icons.text_snippet) return 'text_snippet';
    if (iconData == Icons.code) return 'code';
    if (iconData == Icons.bug_report) return 'bug_report';
    if (iconData == Icons.build) return 'build';
    if (iconData == Icons.construction) return 'construction';
    if (iconData == Icons.engineering) return 'engineering';
    if (iconData == Icons.science) return 'science';
    if (iconData == Icons.biotech) return 'biotech';
    if (iconData == Icons.precision_manufacturing)
      return 'precision_manufacturing';
    if (iconData == Icons.factory) return 'factory';
    if (iconData == Icons.business) return 'business';
    if (iconData == Icons.domain) return 'domain';
    if (iconData == Icons.apartment) return 'apartment';
    if (iconData == Icons.location_on) return 'location_on';
    if (iconData == Icons.place) return 'place';
    if (iconData == Icons.navigation) return 'navigation';
    if (iconData == Icons.directions) return 'directions';
    if (iconData == Icons.map) return 'map';
    if (iconData == Icons.satellite) return 'satellite';
    if (iconData == Icons.terrain) return 'terrain';
    if (iconData == Icons.layers) return 'layers';
    if (iconData == Icons.filter_list) return 'filter_list';
    if (iconData == Icons.sort) return 'sort';
    if (iconData == Icons.filter) return 'filter';
    if (iconData == Icons.tune) return 'tune';
    if (iconData == Icons.view_list) return 'view_list';
    if (iconData == Icons.view_module) return 'view_module';
    if (iconData == Icons.view_quilt) return 'view_quilt';
    if (iconData == Icons.view_agenda) return 'view_agenda';
    if (iconData == Icons.view_week) return 'view_week';
    if (iconData == Icons.view_day) return 'view_day';
    if (iconData == Icons.view_headline) return 'view_headline';
    if (iconData == Icons.view_carousel) return 'view_carousel';
    if (iconData == Icons.view_column) return 'view_column';
    if (iconData == Icons.view_stream) return 'view_stream';
    if (iconData == Icons.view_comfy) return 'view_comfy';
    if (iconData == Icons.view_compact) return 'view_compact';
    if (iconData == Icons.view_sidebar) return 'view_sidebar';
    if (iconData == Icons.view_array) return 'view_array';
    if (iconData == Icons.view_timeline) return 'view_timeline';
    if (iconData == Icons.view_kanban) return 'view_kanban';
    if (iconData == Icons.view_cozy) return 'view_cozy';
    if (iconData == Icons.view_comfortable) return 'view_comfortable';
    if (iconData == Icons.view_in_ar) return 'view_in_ar';
    if (iconData == Icons.view_agenda_outlined) return 'view_agenda_outlined';
    if (iconData == Icons.view_agenda_rounded) return 'view_agenda_rounded';
    if (iconData == Icons.view_agenda_sharp) return 'view_agenda_sharp';
    if (iconData == baadericon) return 'baader';
    return 'help'; // fallback
  }
}
