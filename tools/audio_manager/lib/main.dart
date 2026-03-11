import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set window title on desktop
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    // Window size will be set after first frame
  }

  runApp(const AudioManagerApp());
}
