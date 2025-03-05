import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dbus/dbus.dart';

part 'dbus.g.dart';

@Riverpod(keepAlive: true)
DBusClient? dbus(Ref ref) => null; // Will be overridden after login
