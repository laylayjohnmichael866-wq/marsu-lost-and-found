import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'providers/app_state.dart';
import 'screens/splash/splash_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase for Cloud Firestore
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const definedUrl = String.fromEnvironment('SUPABASE_URL');
  const definedKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final config = definedUrl.isNotEmpty && definedKey.isNotEmpty
      ? {'SUPABASE_URL': definedUrl, 'SUPABASE_PUBLISHABLE_KEY': definedKey}
      : Map<String, dynamic>.from(
          jsonDecode(await rootBundle.loadString('supabase_config.json'))
              as Map,
        );

  // Initialize Supabase for authentication and storage.
  await Supabase.initialize(
    url: config['SUPABASE_URL'] as String,
    publishableKey: config['SUPABASE_PUBLISHABLE_KEY'] as String,
  );

  final appState = AppState();
  await appState.initialize();

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider.value(value: appState)],
      child: const MarsuLostAndFoundApp(),
    ),
  );
}

class MarsuLostAndFoundApp extends StatelessWidget {
  const MarsuLostAndFoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MarSU Lost & Found',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
}
