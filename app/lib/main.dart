import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'config.dart';
import 'data/app_state.dart';
import 'ui/home_shell.dart';
import 'ui/launch.dart';
import 'ui/splash_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const AlfahamApp());
}

class AlfahamApp extends StatefulWidget {
  const AlfahamApp({super.key});

  @override
  State<AlfahamApp> createState() => _AlfahamAppState();
}

class _AlfahamAppState extends State<AlfahamApp> {
  final AppState _state = AppState();
  bool _showSplash = true; // مرة واحدة عند بدء التطبيق فقط

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      navigatorKey: appNavKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Cairo',
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(primary: Color(0xFFFF6600), surface: Colors.black),
      ),
      home: Stack(
        fit: StackFit.expand,
        children: [
          HomeShell(state: _state),
          if (_showSplash) SplashOverlay(onDone: () => setState(() => _showSplash = false)),
        ],
      ),
    );
  }
}
