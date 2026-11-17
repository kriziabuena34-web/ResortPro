import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/admin_dashboard_page.dart';
import '../screens/admin_login_page.dart';

/// Kasalukuyang page sa URL (hal. "/bookings"). Dahil dito gumagana ang
/// reload, at ang back (←) at forward (→) ng browser.
final ValueNotifier<String> adminPath = ValueNotifier('/');

/// null = tinitingnan pa; true = naka-login na admin; false = login page.
final ValueNotifier<bool?> adminSignedIn = ValueNotifier(null);

class AdminRouteParser extends RouteInformationParser<String> {
  const AdminRouteParser();

  @override
  Future<String> parseRouteInformation(RouteInformation routeInformation) async {
    final p = routeInformation.uri.path;
    return p.isEmpty ? '/' : p;
  }

  @override
  RouteInformation? restoreRouteInformation(String configuration) =>
      RouteInformation(uri: Uri(path: configuration));
}

class AdminRouterDelegate extends RouterDelegate<String>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<String> {
  AdminRouterDelegate() {
    adminPath.addListener(notifyListeners);
  }

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  String get currentConfiguration => adminPath.value;

  @override
  Future<void> setNewRoutePath(String configuration) async {
    if (adminPath.value != configuration) adminPath.value = configuration;
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      pages: const [MaterialPage(key: ValueKey('root'), child: AuthGate())],
      onDidRemovePage: (_) {},
    );
  }
}

/// Ipinapakita ang login o ang dashboard. Kapag ni-reload ang browser at
/// naka-login pa, diretso na sa dashboard (hindi na kailangang mag-login ulit).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    adminSignedIn.addListener(_changed);
    _restore();
  }

  @override
  void dispose() {
    adminSignedIn.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _restore() async {
    final db = Supabase.instance.client;
    final user = db.auth.currentUser;
    if (user == null) {
      adminSignedIn.value = false;
      return;
    }
    try {
      final profile = await db.from('profiles').select('role').eq('id', user.id).single();
      adminSignedIn.value = profile['role'] == 'admin';
    } catch (_) {
      adminSignedIn.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (adminSignedIn.value) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      true => const AdminDashboardPage(),
      false => const AdminLoginPage(),
    };
  }
}
