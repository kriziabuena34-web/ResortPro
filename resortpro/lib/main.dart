import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Ang loading screen na ang mag-i-initialize ng Supabase at notifications,
  // habang ipinapakita ang progress (alon + life ring).
  runApp(const MyApp());
}

SupabaseClient get supabase => Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ResortPro',
      // Iisang design system kasama ng admin panel.
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
