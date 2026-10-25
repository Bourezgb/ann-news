import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/history_repository.dart';
import 'services/settings_service.dart';
import 'services/share_inbox.dart';
import 'services/speaker_repository.dart';
import 'services/template_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsService.load();
  final history = await HistoryRepository.load();
  final speakers = await SpeakerRepository.load();
  final templates = await TemplateRepository.load();
  final inbox = ShareInbox();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider.value(value: speakers),
        ChangeNotifierProvider.value(value: templates),
        ChangeNotifierProvider.value(value: inbox),
      ],
      child: const AnnApp(),
    ),
  );
  // بعد تشغيل الواجهة حتى تكون شاشة الصياغة جاهزة لاستقبال المشاركات.
  await inbox.start();
}
