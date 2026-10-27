import 'package:flutter/material.dart';

import 'app_shell.dart';

ThemeData _theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F4C5C),
        brightness: brightness,
      ),
    );

class MyMarketLabApp extends StatelessWidget {
  const MyMarketLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MY MARKET LAB',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}

/// Shown only if the local database cannot be opened or migrated.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      home: Scaffold(
        appBar: AppBar(title: const Text('MY MARKET LAB')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The local database could not be opened.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Nothing has been deleted. Close the app and open it again. '
                  'If this keeps happening, keep this message:',
                ),
                const SizedBox(height: 12),
                SelectableText(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
