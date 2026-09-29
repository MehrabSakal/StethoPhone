import 'package:flutter/material.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LungSoundApp());
}

class LungSoundApp extends StatelessWidget {
  const LungSoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PulmoDSP - Lung Sound Analyzer',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B), // Medical Teal
          brightness: Brightness.light,
          primary: const Color(0xFF00897B),
          secondary: const Color(0xFF3F51B5), // Indigo DSP Accent
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF26A69A),
          brightness: Brightness.dark,
          primary: const Color(0xFF26A69A),
          secondary: const Color(0xFF7986CB),
          surface: const Color(0xFF131E32),
          background: const Color(0xFF0B1120),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1120),
      ),
      home: const HomePage(),
    );
  }
}
