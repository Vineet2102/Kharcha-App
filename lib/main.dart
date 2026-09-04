import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';

/// Bootstrap sequence per spec §11.1. Steps 5 (open Drift DB) happens
/// lazily the first time `appDatabaseProvider` is read. Steps 6 (notification
/// init) and 8 (kick off first sync) land in Phase 13 and Phase 4
/// respectively — nothing to do here yet.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.assertValid();

  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation(AppConstants.timeZoneName));

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: KharchaApp()));
}
