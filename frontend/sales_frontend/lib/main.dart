import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/data_provider.dart';
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
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primaryBlue,
            primary: AppColors.primaryBlue,
            secondary: AppColors.primaryRed,
            brightness: Brightness.light,
          ),
          primaryColor: AppColors.primaryBlue,
          useMaterial3: true,
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
        ),
        home: const AuthWrapper(),
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
