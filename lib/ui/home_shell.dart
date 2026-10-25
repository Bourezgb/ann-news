import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/share_inbox.dart';
import 'compose/compose_screen.dart';
import 'designer/designer_screen.dart';
import 'history/history_screen.dart';
import 'settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final ShareInbox _inbox = context.read<ShareInbox>();
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _inbox.addListener(_onShare);
  }

  @override
  void dispose() {
    _inbox.removeListener(_onShare);
    super.dispose();
  }

  /// عند وصول مشاركة: العودة إلى شاشة الصياغة (حتى لو كانت شاشة أخرى مفتوحة).
  void _onShare() {
    if (_inbox.received == _seen) return;
    _seen = _inbox.received;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _index = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [ComposeScreen(), DesignerScreen(), HistoryScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: 'صياغة',
          ),
          NavigationDestination(
            icon: Icon(Icons.palette_outlined),
            selectedIcon: Icon(Icons.palette),
            label: 'التصميم',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'السجل'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}
