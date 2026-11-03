import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'l10n/app_strings.dart';
import 'screens/admin_login_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSavedLanguage();

  await Supabase.initialize(
    url: 'https://dqnsolfjxsdjqmgqigyt.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxbnNvbGZqeHNkanFtZ3FpZ3l0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA2NjA0MDAsImV4cCI6MjEwNjIzNjQwMH0.2OBUfFFpWVl2_60oODrV6XKwAqD90FNHAYREB0N9P0k',
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    appLanguage.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    appLanguage.removeListener(_onLanguageChanged);
    super.dispose();
  }

  /// Kapag nagpalit ng wika, ire-rebuild ang lahat ng screen (pati dialogs)
  /// para lumabas agad ang bagong text, nang hindi nawawala ang state.
  void _onLanguageChanged() {
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResortPro Admin',
      debugShowCheckedModeBanner: false,
      theme: buildAdminTheme(),
      home: const AdminLoginPage(),
    );
  }
}
