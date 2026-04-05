import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/blocking_loader_overlay.dart';

// cspell:ignore SGCO

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const double _kDesktopFormMaxWidth = 430;
  static const double _kMobileFormMaxWidth = 460;
  static const double _kDesktopHorizontalPadding = 40;
  static const double _kMobileHorizontalPadding = 24;
  static const double _kFormVerticalPadding = 24;

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _usernameFocusNode.addListener(_onFocusChanged);
    _passwordFocusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    _passwordFocusNode
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    await authProvider.login(
      _usernameController.text.trim(),
      _passwordController.text,
    );
  }

  bool _isDesktop(double width) => width >= 900;

  InputDecoration _fieldDecoration(
    String hint,
    String label, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: const Color(0xFF6B7280),
      ),
      hintStyle: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF9CA3AF),
      ),
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: suffixIcon,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      border: InputBorder.none,
    );
  }

  Widget _buildBorderedField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required String label,
    required FormFieldValidator<String> validator,
    Widget? suffixIcon,
    bool obscureText = false,
    TextInputAction? textInputAction,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    const gradient = LinearGradient(
      colors: [Color(0xFFE44408), Color(0xFF1C2172)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );

    final isFocused = focusNode.hasFocus;
    final outerRadius = BorderRadius.circular(10);
    final innerRadius = BorderRadius.circular(8.8);

    return ClipRRect(
      borderRadius: outerRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: outerRadius,
          gradient: isFocused ? gradient : null,
          border: isFocused
              ? null
              : Border.all(color: const Color(0xFFD1D5DB), width: 1),
          color: Colors.white,
        ),
        child: Padding(
          padding: const EdgeInsets.all(1.2),
          child: ClipRRect(
            borderRadius: innerRadius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: innerRadius,
              ),
              child: TextFormField(
                controller: controller,
                focusNode: focusNode,
                style: GoogleFonts.inter(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF111827),
                ),
                decoration: _fieldDecoration(
                  hint,
                  label,
                  suffixIcon: suffixIcon,
                ),
                obscureText: obscureText,
                textInputAction: textInputAction,
                onFieldSubmitted: onFieldSubmitted,
                validator: validator,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(AuthProvider auth, {required bool desktop}) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal:
              desktop ? _kDesktopHorizontalPadding : _kMobileHorizontalPadding,
          vertical: _kFormVerticalPadding,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: desktop ? _kDesktopFormMaxWidth : _kMobileFormMaxWidth,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 28,
                  child: Image.asset(
                    'assets/images/word_logo.png',
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    errorBuilder: (_, __, ___) => Text(
                      'SGCO System',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF7F1D1D),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Welcome Back!',
                  style: GoogleFonts.inter(
                    fontSize: 27,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Log in to continue',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF6B7280),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (auth.error != null) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDA4AF)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Color(0xFFBE123C), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            auth.error!,
                            style: GoogleFonts.inter(
                              color: const Color(0xFF9F1239),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: auth.clearError,
                          borderRadius: BorderRadius.circular(99),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.close,
                                size: 16, color: Color(0xFF9F1239)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _buildBorderedField(
                  controller: _usernameController,
                  focusNode: _usernameFocusNode,
                  hint: 'Enter your username',
                  label: 'USERNAME',
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                _buildBorderedField(
                  controller: _passwordController,
                  focusNode: _passwordFocusNode,
                  hint: 'Enter your password',
                  label: 'PASSWORD',
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                    splashRadius: 18,
                    tooltip:
                        _obscurePassword ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleLogin(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : _handleLogin,
                    style: ButtonStyle(
                      elevation: WidgetStateProperty.all(0),
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      foregroundColor:
                          WidgetStateProperty.all<Color>(Colors.white),
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.disabled)) {
                          return const Color(0xFFF59E72);
                        }
                        if (states.contains(WidgetState.pressed)) {
                          return const Color(0xFFC43906);
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return const Color(0xFFD14007);
                        }
                        return const Color(0xFFE44408);
                      }),
                    ),
                    child: auth.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Login',
                            style: GoogleFonts.inter(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final desktop = _isDesktop(screenWidth);

    return Scaffold(
      backgroundColor: const Color(0xFFE5E7EB),
      body: SafeArea(
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final frameWidth = desktop
                  ? (constraints.maxWidth * 0.92).clamp(980.0, 1280.0)
                  : constraints.maxWidth;
              final frameHeight = desktop
                  ? (constraints.maxHeight * 0.86).clamp(560.0, 760.0)
                  : constraints.maxHeight;

              return SizedBox(
                width: frameWidth,
                height: frameHeight,
                child: Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    final showLoader = auth.isLoading;

                    if (!desktop) {
                      return BlockingLoaderOverlay(
                        show: showLoader,
                        message: 'Logging in…',
                        child: Container(
                          color: Colors.white,
                          child: _buildLoginForm(auth, desktop: false),
                        ),
                      );
                    }

                    return BlockingLoaderOverlay(
                      show: showLoader,
                      message: 'Logging in…',
                      child: Row(
                        children: [
                          const Expanded(
                            flex: 11,
                            child: RepaintBoundary(child: _DesktopLoginImage()),
                          ),
                          Expanded(
                            flex: 10,
                            child: Container(
                              color: Colors.white,
                              child: _buildLoginForm(auth, desktop: true),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DesktopLoginImage extends StatelessWidget {
  const _DesktopLoginImage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      alignment: Alignment.centerLeft,
      child: Image.asset(
        'assets/images/background_login.png',
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              size: 42,
              color: Color(0xFF9CA3AF),
            ),
          );
        },
      ),
    );
  }
}
