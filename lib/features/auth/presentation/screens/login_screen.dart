import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Entry widget
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -7, end: 7).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    await ref.read(authNotifierProvider.notifier).signIn(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );

    if (!mounted) return;

    final authState = ref.read(authNotifierProvider);
    authState.when(
      data: (profile) {
        if (profile != null) {
          switch (profile.role) {
            case 'super_admin':
              context.go('/super-admin');
              break;
            default:
              context.go('/dashboard');
          }
        } else {
          setState(() {
            _error = 'Login failed. Please try again.';
            _loading = false;
          });
        }
      },
      error: (e, _) => setState(() {
        _error = e.toString();
        _loading = false;
      }),
      loading: () => setState(() {
        _error = 'Login timed out. Please try again.';
        _loading = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isDesktop = w >= 900;
    return isDesktop
        ? _DesktopLogin(state: this)
        : _MobileLogin(state: this);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Desktop layout: Red brand panel | White form panel
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopLogin extends StatelessWidget {
  final _LoginScreenState state;
  const _DesktopLogin({required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // Left brand panel (red)
          Expanded(
            flex: 52,
            child: _BrandPanel(floatAnim: state._floatAnim),
          ),
          // Right form panel (white/light)
          Expanded(
            flex: 48,
            child: Container(
              color: AppColors.surface,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 56, vertical: 48),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: _LoginForm(state: state, compact: false),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mobile layout: Red curved header | White floating card
// ─────────────────────────────────────────────────────────────────────────────
class _MobileLogin extends StatelessWidget {
  final _LoginScreenState state;
  const _MobileLogin({required this.state});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: Stack(
        children: [
          // Red curved header background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size.height * 0.40,
            child: ClipPath(
              clipper: _WaveClipper(),
              child: _BrandPanel(
                floatAnim: state._floatAnim,
                compact: true,
              ),
            ),
          ),

          // Scrollable content
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                top: size.height * 0.27,
                left: 16,
                right: 16,
                bottom: 32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          blurRadius: 48,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 36),
                      child: _LoginForm(state: state, compact: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Red brand panel (shared between desktop left & mobile header)
// ─────────────────────────────────────────────────────────────────────────────
class _BrandPanel extends StatelessWidget {
  final Animation<double> floatAnim;
  final bool compact;
  const _BrandPanel({required this.floatAnim, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFD32F2F),
            Color(0xFFC0392B),
            Color(0xFF8B1A1A),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Subtle grid overlay
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),

          // Soft radial highlight
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.2,
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Decorative blurred circles
          const Positioned(
            top: -50,
            right: -50,
            child: _Orb(size: 220, opacity: 0.12),
          ),
          const Positioned(
            bottom: -60,
            left: -30,
            child: _Orb(size: 200, opacity: 0.10),
          ),

          // Content
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 24 : 48),
              child: compact
                  ? _CompactBrandContent(floatAnim: floatAnim)
                  : _FullBrandContent(floatAnim: floatAnim),
            ),
          ),
        ],
      ),
    );
  }
}

// Full brand content for desktop
class _FullBrandContent extends StatelessWidget {
  final Animation<double> floatAnim;
  const _FullBrandContent({required this.floatAnim});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Floating logo with gold ring
        AnimatedBuilder(
          animation: floatAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, floatAnim.value),
            child: child,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.15),
                      blurRadius: 40,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),
              // Logo
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/katiyastationlogo.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
        ).animate().scale(
              delay: 200.ms,
              duration: 700.ms,
              curve: Curves.elasticOut,
            ),

        const SizedBox(height: 32),

        Text(
          'KATIYA STATION',
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 3.5,
          ),
        ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.25),

        const SizedBox(height: 6),

        Text(
          'Restaurant  &  Bar',
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w300,
            color: Colors.white70,
            letterSpacing: 5,
          ),
        ).animate().fadeIn(delay: 520.ms),

        const SizedBox(height: 10),

        // Thin white divider
        Container(
          width: 50,
          height: 1.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white.withValues(alpha: 0.6),
                Colors.transparent,
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ).animate().fadeIn(delay: 600.ms).scaleX(begin: 0.0),

        const SizedBox(height: 48),

        // Feature pills
        ...[
          (Icons.point_of_sale_rounded, 'POS & Billing'),
          (Icons.kitchen_rounded, 'Kitchen Display'),
          (Icons.inventory_2_rounded, 'Inventory & Bar'),
          (Icons.analytics_rounded, 'Reports & Analytics'),
        ].asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FeaturePill(icon: e.value.$1, label: e.value.$2)
                    .animate()
                    .fadeIn(
                        delay: Duration(milliseconds: 700 + e.key * 90))
                    .slideX(begin: -0.15),
              ),
            ),

        const SizedBox(height: 56),

        // Bottom tagline
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            'Powered by Supabase  ·  Encrypted & Secure',
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: Colors.white54,
              letterSpacing: 0.4,
            ),
          ),
        ).animate().fadeIn(delay: 1100.ms),
      ],
    );
  }
}

// Compact brand for mobile header
class _CompactBrandContent extends StatelessWidget {
  final Animation<double> floatAnim;
  const _CompactBrandContent({required this.floatAnim});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: floatAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, floatAnim.value * 0.5),
            child: child,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.2),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 72,
                height: 72,
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/katiyastationlogo.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
        ).animate().scale(
              delay: 100.ms,
              duration: 600.ms,
              curve: Curves.elasticOut,
            ),
        const SizedBox(height: 14),
        Text(
          'KATIYA STATION',
          style: GoogleFonts.outfit(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 3,
          ),
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 4),
        Text(
          'Restaurant  &  Bar',
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w300,
            color: Colors.white70,
            letterSpacing: 4,
          ),
        ).animate().fadeIn(delay: 300.ms),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Login form (light theme)
// ─────────────────────────────────────────────────────────────────────────────
class _LoginForm extends StatefulWidget {
  final _LoginScreenState state;
  final bool compact;
  const _LoginForm({required this.state, required this.compact});

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final compact = widget.compact;

    return Form(
      key: state._formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Heading
          Text(
            'Welcome Back 👋',
            style: GoogleFonts.outfit(
              fontSize: compact ? 24 : 28,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.15),

          const SizedBox(height: 6),
          Text(
            'Sign in to your management account',
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ).animate().fadeIn(delay: 80.ms),

          const SizedBox(height: 32),

          // Error banner
          if (state._error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state._error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ).animate().shake(),

          // Email field
          _LightTextField(
            controller: state._emailCtrl,
            label: 'Email Address',
            hint: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.08),

          const SizedBox(height: 16),

          // Password field
          _LightTextField(
            controller: state._passwordCtrl,
            label: 'Password',
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscure,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.textHint,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            onFieldSubmitted: (_) => state._login(),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 6) return 'Minimum 6 characters';
              return null;
            },
          ).animate().fadeIn(delay: 240.ms).slideY(begin: 0.08),

          const SizedBox(height: 32),

          // Sign In button
          _SignInButton(
            loading: state._loading,
            onPressed: state._login,
          ).animate().fadeIn(delay: 320.ms).slideY(begin: 0.08),

          const SizedBox(height: 32),

          // Divider
          Row(
            children: [
              Expanded(
                child: Container(
                    height: 1,
                    color: AppColors.divider),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'SECURE LOGIN',
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                    height: 1,
                    color: AppColors.divider),
              ),
            ],
          ).animate().fadeIn(delay: 400.ms),

          const SizedBox(height: 20),

          // Security note
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_rounded,
                      color: AppColors.primary, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Secured by Supabase Auth. Contact your manager to reset your password.',
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 460.ms),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Light-themed text field with red focus accent
// ─────────────────────────────────────────────────────────────────────────────
class _LightTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;

  const _LightTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  State<_LightTextField> createState() => _LightTextFieldState();
}

class _LightTextFieldState extends State<_LightTextField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(
        () => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _focused
            ? Colors.white
            : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _focused
              ? AppColors.primary
              : AppColors.border,
          width: _focused ? 1.5 : 1.0,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : [],
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        onFieldSubmitted: widget.onFieldSubmitted,
        validator: widget.validator,
        style: GoogleFonts.outfit(
          color: AppColors.textPrimary,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          hintStyle: GoogleFonts.outfit(
              color: AppColors.textHint, fontSize: 14),
          labelStyle: GoogleFonts.outfit(
            color: _focused
                ? AppColors.primary
                : AppColors.textSecondary,
            fontSize: 13,
          ),
          prefixIcon: Icon(
            widget.icon,
            color: _focused
                ? AppColors.primary
                : AppColors.textHint,
            size: 20,
          ),
          suffixIcon: widget.suffixIcon,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          errorStyle:
              const TextStyle(color: AppColors.error, fontSize: 12),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sign In button with red gradient
// ─────────────────────────────────────────────────────────────────────────────
class _SignInButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _SignInButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: loading
                  ? const LinearGradient(
                      colors: [Color(0xFFCCCCCC), Color(0xFFBBBBBB)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFE53935),
                        Color(0xFFC0392B),
                        Color(0xFF8B1A1A),
                      ],
                    ),
              boxShadow: loading
                  ? null
                  : [
                      BoxShadow(
                        color:
                            AppColors.primary.withValues(alpha: 0.38),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Sign In',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Feature pill for desktop brand panel
// ─────────────────────────────────────────────────────────────────────────────
class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeaturePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 17),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Blurred decorative orb
// ─────────────────────────────────────────────────────────────────────────────
class _Orb extends StatelessWidget {
  final double size;
  final double opacity;
  const _Orb({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: opacity),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Subtle dot grid background painter
// ─────────────────────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 0.8;

    const step = 44.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.4, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Wave clipper for mobile header
// ─────────────────────────────────────────────────────────────────────────────
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 40);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height - 20,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height - 42,
      size.width,
      size.height - 10,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
