import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'services/settings_service.dart';
import 'ui/home_shell.dart';

class AnnApp extends StatelessWidget {
  const AnnApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<SettingsService, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'ANN',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      home: const HomeShell(),
    );
  }
}
