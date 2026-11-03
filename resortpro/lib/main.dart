import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/home_page.dart';
import 'screens/sign_in_page.dart';
import 'services/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // Phone notifications + background check (gumagana kahit sarado ang app)
  try {
    await LocalNotifier.init();
    await BackgroundCheck.initialize();
  } catch (_) {
    // Hindi dapat pigilan ng notification setup ang pagbukas ng app.
  }

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ResortPro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
        ),
        useMaterial3: true,
      ),
      // Kapag naka-login pa, diretso na sa home (hal. galing sa notification).
      home: Supabase.instance.client.auth.currentSession != null
          ? const HomePage()
          : const SignInPage(),
    );
  }
}
