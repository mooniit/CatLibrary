import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CatLibraryApp(initialThemeMode: await loadAppTheme()));
}
