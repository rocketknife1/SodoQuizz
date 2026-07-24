import 'package:flutter/material.dart';
import 'core/sfx.dart';
import 'screens/home_screen.dart';
import 'screens/loading_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Sfx.preload();
  runApp(const GuessItApp());
}

class GuessItApp extends StatelessWidget {
  const GuessItApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Guess It!',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF534AB7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
        ),
      ),
      home: const LoadingScreen(nextBuilder: _homeBuilder, duration: Duration(milliseconds: 1400)),
    );
  }

  static Widget _homeBuilder(BuildContext _) => const HomeScreen();
}
