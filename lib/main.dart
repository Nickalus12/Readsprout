import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'models/player_profile.dart';
import 'services/profile_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Allow runtime font fetching when online; fonts are also bundled in pubspec.yaml
  // as fallback so the app works fully offline on kid devices.

  // Initialize Hive for local storage (cross-platform path resolution)
  await Hive.initFlutter();

  // Register Hive TypeAdapters
  Hive.registerAdapter(PlayerProfileAdapter());
  Hive.registerAdapter(AvatarConfigAdapter());
  Hive.registerAdapter(StickerRecordAdapter());

  // Open Hive boxes (each is an independent file on disk)
  await Hive.openBox('profile');
  await Hive.openBox<StickerRecord>('stickers');
  await Hive.openBox('dailyRewards');

  // Migrate legacy SharedPreferences data to Hive (one-time, safe to re-call)
  await ProfileService.migrateFromSharedPreferences();

  // Desktop: hide title bar and go fullscreen
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      fullScreen: true,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Lock to portrait for a consistent kid-friendly experience (mobile only)
  if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  // Immersive full-screen experience
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ReadingSproutApp());
}
