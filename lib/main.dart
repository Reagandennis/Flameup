import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/forgot_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'services/appwrite_client.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

// ─── Riverpod providers ───────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((_) => AuthService());

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (_) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString('theme_mode') ?? 'system';
    state = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }
}

// ─── GoRouter ─────────────────────────────────────────────────────────────────

final GoRouter _router = GoRouter(
  initialLocation: '/splash',
  routes: <RouteBase>[
    GoRoute(
      path: '/splash',
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (_, __) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      builder: (_, __) => const SignupScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (_, __) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const SettingsScreen(),
    ),
  ],
);

// ─── Entry point ──────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Appwrite (synchronous — just sets up the SDK client)
  AppwriteClient.instance.initialize();

  // Hydrate auth session from Appwrite before rendering
  await AuthService().initialize();

  // Local notifications
  await NotificationService().initialize();
  await NotificationService().scheduleDailyReminder();

  runApp(const ProviderScope(child: FlameupApp()));
}

// ─── Root widget ──────────────────────────────────────────────────────────────

class FlameupApp extends ConsumerWidget {
  const FlameupApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider);

    const Color primaryColor = Color(0xFFF6511D);
    const Color secondaryColor = Color(0xFF04151F);

    final ColorScheme lightScheme = ColorScheme.light(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: const Color(0xFFF6F2EB),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: const Color(0xFF201A17),
    );
    final ColorScheme darkScheme = ColorScheme.dark(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: secondaryColor,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Flameup',
      routerConfig: _router,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
        scaffoldBackgroundColor: lightScheme.surface,
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: darkScheme.surface,
      ),
      themeMode: themeMode,
    );
  }
}
