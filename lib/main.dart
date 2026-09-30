import 'package:flutter/material.dart';
import 'ui/main_navigation_scaffold.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LungSoundApp());
}

class LungSoundApp extends StatelessWidget {
  const LungSoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PulmoDSP - Lung Sound Recorder',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B), // Medical Teal
          brightness: Brightness.light,
          primary: const Color(0xFF00897B),
          secondary: const Color(0xFF3F51B5),
        ),
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF26A69A),
          brightness: Brightness.dark,
          primary: const Color(0xFF26A69A),
          secondary: const Color(0xFF7986CB),
          surface: const Color(0xFF111827),
          background: const Color(0xFF0B0F19),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        appBarTheme: const AppBarTheme(
          scrolledUnderElevation: 0,
        ),
      ),
      home: const MainNavigationScaffold(),
    );
  }
}
