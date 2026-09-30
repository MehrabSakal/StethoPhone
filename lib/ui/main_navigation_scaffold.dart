import 'package:flutter/material.dart';
import 'screens/record_screen.dart';
import 'screens/recordings_list_screen.dart';

class MainNavigationScaffold extends StatefulWidget {
  const MainNavigationScaffold({super.key});

  @override
  State<MainNavigationScaffold> createState() => _MainNavigationScaffoldState();
}

class _MainNavigationScaffoldState extends State<MainNavigationScaffold> {
  int _currentIndex = 0;

  void _onTabSelected(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          RecordScreen(
            onGoToRecordingsTab: () => _onTabSelected(1),
          ),
          RecordingsListScreen(
            onGoToRecordTab: () => _onTabSelected(0),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withOpacity(0.35),
              width: 0.8,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabSelected,
          elevation: 0,
          backgroundColor: theme.scaffoldBackgroundColor,
          indicatorColor: colorScheme.primaryContainer,
          height: 65,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.mic_none_rounded),
              selectedIcon: Icon(Icons.mic_rounded, color: Color(0xFFEF4444)),
              label: 'Record',
            ),
            NavigationDestination(
              icon: Icon(Icons.graphic_eq_rounded),
              selectedIcon: Icon(Icons.graphic_eq_rounded, color: Color(0xFF00897B)),
              label: 'Recordings',
            ),
          ],
        ),
      ),
    );
  }
}
