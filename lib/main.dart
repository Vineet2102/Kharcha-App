import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/constants/app_constants.dart';
import 'core/notifications/notification_service.dart';

/// Bootstrap sequence per spec §11.1. Steps 5 (open Drift DB) happens
/// lazily the first time `appDatabaseProvider` is read. Step 8 (kick off
/// first sync) lands in `KharchaApp.initState`. Step 6 (notification init)
/// was brought forward from Phase 13 in Phase 8 — T-8.5's budget alerts are
/// the first feature that needs to fire a local notification; Phase 13
/// layers scheduled notifications (daily reminder, monthly summary, etc.)
/// on top of this same initialized plugin.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.assertValid();

  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation(AppConstants.timeZoneName));

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  await NotificationService.instance.init();

  runApp(const ProviderScope(child: KharchaApp()));
}
