import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/data_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/editor_dashboard.dart';
import 'screens/viewer_dashboard.dart';
import 'config/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Suppress the known Flutter Windows bug where Alt/modifier key events fire
  // with incorrect modifier flags, causing a harmless but noisy assertion:
  // "Attempted to send a key down event when no keys are in keysPressed"
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exceptionAsString();
    if (msg.contains(
            'Attempted to send a key down event when no keys are in keysPressed') ||
        msg.contains('keysPressed.isNotEmpty')) {
      return; // known Flutter Windows keyboard bug – safe to ignore
    }
    if (msg.contains('A disposed RenderObject was mutated') &&
        msg.contains('RenderChartFadeTransition')) {
      return; // known Syncfusion dispose race in debug mode – safe to ignore
    }
    // All other errors: log normally
    if (kDebugMode) {
      FlutterError.presentError(details);
    } else {
      debugPrint('Flutter error: $msg');
    }
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Global key to help with hot restart
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProxyProvider<AuthProvider, DataProvider>(
          create: (_) => DataProvider(),
          update: (_, auth, data) {
            if (auth.token != null && data != null) {
              data.setAuth(auth.token!, auth.user?.id.toString() ?? '');
            }
            return data ?? DataProvider();
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          navigatorKey: navigatorKey,
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          scrollBehavior:
              const MaterialScrollBehavior().copyWith(scrollbars: false),
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();

            final media = MediaQuery.of(context);
            final width = media.size.width;
            final height = media.size.height;

            // Keep app filling the full window, and only scale text slightly
            // on smaller sizes to improve responsiveness without shrinking canvas.
            const desktopBaseWidth = 1366.0;
            const desktopBaseHeight = 768.0;
            final widthScale = (width / desktopBaseWidth).clamp(0.88, 1.0);
            final heightScale = (height / desktopBaseHeight).clamp(0.88, 1.0);
            final textScale =
                widthScale < heightScale ? widthScale : heightScale;

            final app = MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: child,
            );

            final showOverlay = themeProvider.isSwitchingTheme;
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Stack(
              children: [
                app,
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !showOverlay,
                    child: AnimatedOpacity(
                      opacity: showOverlay ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Container(
                        color: (isDark ? const Color(0xFF0B1220) : Colors.white)
                            .withValues(alpha: 0.55),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          themeMode: themeProvider.themeMode,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          home: const AuthWrapper(),
        ),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryBlue,
        primary: AppColors.primaryBlue,
        secondary: AppColors.primaryRed,
        brightness: Brightness.light,
      ),
      primaryColor: AppColors.primaryBlue,
      useMaterial3: true,
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.darkText,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 13,
          height: 1.3,
          color: AppColors.grayText,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryBlue,
      primary: AppColors.primaryBlue,
      secondary: AppColors.primaryRed,
      brightness: Brightness.dark,
    );

    return ThemeData(
      colorScheme: darkScheme,
      primaryColor: AppColors.primaryBlue,
      scaffoldBackgroundColor: const Color(0xFF111827),
      useMaterial3: true,
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF1F2937),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF374151)),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFFF9FAFB),
        ),
        contentTextStyle: const TextStyle(
          fontSize: 13,
          height: 1.3,
          color: Color(0xFFD1D5DB),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1F2937),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: Color(0xFF374151)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

/// Wrapper that checks authentication state and shows appropriate screen
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to avoid calling setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAuth();
    });
  }

  Future<void> _initAuth() async {
    await context.read<AuthProvider>().initialize();
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading...'),
            ],
          ),
        ),
      );
    }

    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isAuthenticated) {
          // Role-based dashboard routing
          final userRole = auth.user?.role ?? '';

          switch (userRole) {
            case 'admin':
              return const DashboardScreen(); // Full admin dashboard
            case 'editor':
              return const EditorDashboard(); // Editor module - can edit sheets
            case 'viewer':
              return const ViewerDashboard(); // Viewer module - read-only
            case 'user':
              return const EditorDashboard(); // User also gets editor access
            default:
              return const LoginScreen(); // Unknown role, logout
          }
        }
        return const LoginScreen();
      },
    );
  }
}
