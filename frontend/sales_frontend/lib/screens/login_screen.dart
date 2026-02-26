import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../config/constants.dart';
import '../main.dart'; // For AuthWrapper

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (success && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBlue,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Consumer<AuthProvider>(
            builder: (context, auth, _) {
              return SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Brand title above card
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.diamond,
                              size: 32,
                              color: AppColors.primaryRed,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Synergy Graphics',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryBlue,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Management System',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.grayText,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Main card
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        // Red card body
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 40),
                          padding: const EdgeInsets.only(
                            top: 60,
                            left: 40,
                            right: 40,
                            bottom: 40,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryRed,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 20),

                                // Error message
                                if (auth.error != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.red[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline,
                                            color: Colors.red[900], size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            auth.error!,
                                            style: TextStyle(
                                              color: Colors.red[900],
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: auth.clearError,
                                          child: Icon(Icons.close,
                                              size: 16, color: Colors.red[900]),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                // Username field
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: TextFormField(
                                    controller: _usernameController,
                                    decoration: const InputDecoration(
                                      hintText: 'Username',
                                      hintStyle: TextStyle(
                                        color: Color(0xFF999999),
                                        fontSize: 14,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.person,
                                        color: Color(0xFF555555),
                                        size: 20,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                    ),
                                    textInputAction: TextInputAction.next,
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Please enter your username';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Password field
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: TextFormField(
                                    controller: _passwordController,
                                    decoration: const InputDecoration(
                                      hintText: 'Password',
                                      hintStyle: TextStyle(
                                        color: Color(0xFF999999),
                                        fontSize: 14,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.lock,
                                        color: Color(0xFF555555),
                                        size: 20,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                    ),
                                    obscureText: true,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _handleLogin(),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your password';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 28),

                                // Login button
                                SizedBox(
                                  width: 140,
                                  height: 42,
                                  child: ElevatedButton(
                                    onPressed:
                                        auth.isLoading ? null : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryBlue,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      elevation: 2,
                                    ),
                                    child: auth.isLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation(
                                                      Colors.white),
                                            ),
                                          )
                                        : const Text(
                                            'LOGIN',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Logo circle on top
                        Positioned(
                          top: 0,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    // Fallback icon if logo not found
                                    return const Icon(
                                      Icons.diamond,
                                      size: 40,
                                      color: AppColors.primaryRed,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
