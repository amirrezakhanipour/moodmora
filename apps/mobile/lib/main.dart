import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/improve_screen.dart';
import 'screens/reply_screen.dart';
import 'screens/voice_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoodMora',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/improve': (_) => const ImproveScreen(),
        '/reply': (_) => const ReplyScreen(),
        '/voice': (_) => const VoiceScreen(),
      },
    );
  }
}
