import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'providers/app_state.dart';
import 'screens/splash/splash_screen.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://eeedchsnxqyibprjkpdu.supabase.co',
  );
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_avuVBs179vNLs8mNUpSNXQ_M0odGJuv',
  );
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    throw StateError(
      'Missing Supabase configuration. Provide SUPABASE_URL and '
      'SUPABASE_PUBLISHABLE_KEY using --dart-define.',
    );
  }

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  // Initialize Firebase for Cloud Firestore
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
