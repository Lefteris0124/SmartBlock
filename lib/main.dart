import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/smartblock_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  runApp(const SmartBlockApp());
}

class SmartBlockApp extends StatelessWidget {
  const SmartBlockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartBlock',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B87)),
        fontFamily: 'Roboto',
      ),
      home: const CheckoutReturnNotice(child: AuthGate()),
    );
  }
}

class CheckoutReturnNotice extends StatefulWidget {
  const CheckoutReturnNotice({required this.child, super.key});
  final Widget child;

  @override
  State<CheckoutReturnNotice> createState() => _CheckoutReturnNoticeState();
}

class _CheckoutReturnNoticeState extends State<CheckoutReturnNotice> {
  @override
  void initState() {
    super.initState();
    final result = Uri.base.queryParameters['checkout'];
    if (result == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final text = switch (result) {
        'success' => 'Η Stripe επέστρεψε στην εφαρμογή. Το υπόλοιπο ενημερώνεται· ανανέωσε σε λίγο.',
        'cancelled' => 'Η πληρωμή ακυρώθηκε. Δεν καταχωρίστηκε χρέωση.',
        _ => null,
      };
      if (text != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text)));
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
          return const PasswordRecoveryScreen();
        }

        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return const SmartBlockDashboard();
        }

        return const LoginScreen();
      },
    );
  }
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isBusy = false;
  bool _showPassword = false;
  bool _isGreek = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isBusy = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password updated.')));
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update the password. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _isGreek = !_isGreek),
                        child: Text(_isGreek ? 'English' : 'Ελληνικά'),
                      ),
                    ),
                    const Icon(
                      Icons.lock_reset_rounded,
                      size: 64,
                      color: Color(0xFF176B87),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isGreek
                          ? 'Νέος κωδικός πρόσβασης'
                          : 'Set a new password',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF17324D),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_isBusy,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText: _isGreek ? 'Νέος κωδικός' : 'New password',
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.length < 8
                          ? (_isGreek
                                ? 'Χρησιμοποίησε τουλάχιστον 8 χαρακτήρες.'
                                : 'Use at least 8 characters.')
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      enabled: !_isBusy,
                      obscureText: !_showPassword,
                      decoration: InputDecoration(
                        labelText: _isGreek
                            ? 'Επιβεβαίωση νέου κωδικού'
                            : 'Confirm new password',
                      ),
                      validator: (value) => value != _passwordController.text
                          ? (_isGreek
                                ? 'Οι κωδικοί δεν ταιριάζουν.'
                                : 'Passwords do not match.')
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isBusy ? null : _updatePassword,
                      child: _isBusy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isGreek ? 'Αλλαγή κωδικού' : 'Update password',
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool showPassword = false;
  bool isGreek = true;
  bool isCreatingAccount = false;
  bool isBusy = false;
  final Set<String> requestedRoles = {};
  String get _authRedirectUrl => kIsWeb
      ? Uri.base.origin + Uri.base.path
      : 'io.supabase.smartblock://login-callback';

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  Future<void> _submitAuth() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (!_isValidEmail(email)) {
      _showMessage(
        isGreek
            ? 'Συμπλήρωσε έγκυρη διεύθυνση email.'
            : 'Enter a valid email address.',
      );
      return;
    }
    if (password.isEmpty || (isCreatingAccount && password.length < 8)) {
      _showMessage(
        isGreek
            ? (isCreatingAccount
                  ? 'Ο κωδικός πρέπει να έχει τουλάχιστον 8 χαρακτήρες.'
                  : 'Συμπλήρωσε τον κωδικό σου.')
            : (isCreatingAccount
                  ? 'Password must be at least 8 characters.'
                  : 'Enter your password.'),
      );
      return;
    }
    if (isCreatingAccount && requestedRoles.isEmpty) {
      _showMessage(
        isGreek
            ? 'Επίλεξε ιδιοκτήτης, ενοικιαστής ή και τα δύο.'
            : 'Choose owner, tenant, or both.',
      );
      return;
    }

    setState(() => isBusy = true);
    try {
      if (isCreatingAccount) {
        final response = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: _authRedirectUrl,
          data: {'requested_roles': requestedRoles.toList()},
        );
        if (!mounted) return;
        if (response.session == null) {
          _showMessage(
            isGreek
                ? 'Ο λογαριασμός δημιουργήθηκε. Επιβεβαίωσε το email σου· η δήλωση ρόλων θα ελεγχθεί από admin.'
                : 'Account created. Confirm your email; an administrator will review your role selection.',
          );
        } else {
          _showMessage(
            isGreek
                ? 'Η δήλωση ρόλων στάλθηκε στον admin για έγκριση.'
                : 'Your role selection was sent for administrator approval.',
          );
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (!mounted) return;
        _showMessage(isGreek ? 'Επιτυχής σύνδεση!' : 'Signed in successfully.');
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        isGreek
            ? 'Παρουσιάστηκε σφάλμα. Δοκίμασε ξανά.'
            : 'Something went wrong. Try again.',
      );
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  Future<void> _signInWithProvider(OAuthProvider provider) async {
    if (isCreatingAccount && requestedRoles.isEmpty) {
      _showMessage(
        isGreek ? 'Επίλεξε πρώτα τον ρόλο σου.' : 'Choose your role first.',
      );
      return;
    }
    setState(() => isBusy = true);
    try {
      final redirect = Uri.parse(_authRedirectUrl);
      final redirectTo = isCreatingAccount
          ? redirect
                .replace(
                  queryParameters: {
                    ...redirect.queryParameters,
                    'sb_requested_roles': requestedRoles.join(','),
                  },
                )
                .toString()
          : _authRedirectUrl;
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: redirectTo,
        scopes: provider == OAuthProvider.azure ? 'email' : null,
        authScreenLaunchMode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showMessage(
          isGreek
              ? 'Δεν άνοιξε η σύνδεση. Δοκίμασε ξανά.'
              : 'Could not open sign-in. Try again.',
        );
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      final message = error.message.toLowerCase();
      _showMessage(
        message.contains('provider') &&
                (message.contains('not enabled') ||
                    message.contains('unsupported'))
            ? (isGreek
                  ? 'Ο πάροχος σύνδεσης δεν έχει ρυθμιστεί ακόμη στο Supabase.'
                  : 'This sign-in provider has not been configured in Supabase yet.')
            : error.message,
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          isGreek
              ? 'Η σύνδεση δεν είναι διαθέσιμη ακόμη. Δοκίμασε ξανά αργότερα.'
              : 'Social sign-in is not available yet. Try again later.',
        );
      }
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  Widget _socialSignInButton({
    required OAuthProvider provider,
    required IconData icon,
    required String label,
  }) => SizedBox(
    height: 52,
    child: OutlinedButton.icon(
      onPressed: isBusy ? null : () => _signInWithProvider(provider),
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF17324D),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFD6E0E7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );

  Future<void> _sendPasswordReset() async {
    final email = emailController.text.trim();
    if (!_isValidEmail(email)) {
      _showMessage(
        isGreek
            ? 'Συμπλήρωσε πρώτα τη διεύθυνση email.'
            : 'Enter your email address first.',
      );
      return;
    }

    setState(() => isBusy = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: _authRedirectUrl,
      );
      if (!mounted) return;
      _showMessage(
        isGreek
            ? 'Αν υπάρχει λογαριασμός με αυτό το email, θα λάβεις σύνδεσμο επαναφοράς.'
            : 'If an account exists for this email, a password reset link will arrive shortly.',
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        isGreek
            ? 'Δεν στάλθηκε ο σύνδεσμος. Δοκίμασε ξανά.'
            : 'Could not send the link. Try again.',
      );
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final title = isCreatingAccount
        ? (isGreek ? 'Δημιούργησε λογαριασμό' : 'Create your account')
        : (isGreek ? 'Καλώς ήρθες!' : 'Welcome!');
    final subtitle = isGreek
        ? 'Η πολυκατοικία σου, οργανωμένη.'
        : 'Your building, organized.';
    final emailLabel = isGreek ? 'Email' : 'Email address';
    final passwordLabel = isGreek ? 'Κωδικός πρόσβασης' : 'Password';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() => isGreek = !isGreek);
                      },
                      icon: const Icon(Icons.language),
                      label: Text(isGreek ? 'English' : 'Ελληνικά'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    height: 86,
                    width: 86,
                    decoration: BoxDecoration(
                      color: const Color(0xFF176B87),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'SmartBlock',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF17324D),
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF17324D),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF637587),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (isCreatingAccount) ...[
                    Text(
                      isGreek ? 'Ο ρόλος σου' : 'Your role',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isGreek
                          ? 'Η επιλογή θα σταλεί στον διαχειριστή για έγκριση.'
                          : 'Your selection will be sent to an administrator for approval.',
                      style: const TextStyle(color: Color(0xFF637587)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        FilterChip(
                          selected: requestedRoles.contains('property_owner'),
                          avatar: const Icon(Icons.apartment_outlined),
                          label: Text(isGreek ? 'Ιδιοκτήτης' : 'Property owner'),
                          onSelected: isBusy
                              ? null
                              : (selected) => setState(() {
                                  if (selected) {
                                    requestedRoles.add('property_owner');
                                  } else {
                                    requestedRoles.remove('property_owner');
                                  }
                                }),
                        ),
                        FilterChip(
                          selected: requestedRoles.contains('tenant'),
                          avatar: const Icon(Icons.home_outlined),
                          label: Text(isGreek ? 'Ενοικιαστής' : 'Tenant'),
                          onSelected: isBusy
                              ? null
                              : (selected) => setState(() {
                                  if (selected) {
                                    requestedRoles.add('tenant');
                                  } else {
                                    requestedRoles.remove('tenant');
                                  }
                                }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text(
                    emailLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailController,
                    enabled: !isBusy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'name@example.com',
                      prefixIcon: const Icon(Icons.email_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    passwordLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    enabled: !isBusy,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => isBusy ? null : _submitAuth(),
                    obscureText: !showPassword,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() => showPassword = !showPassword);
                        },
                        icon: Icon(
                          showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: isBusy ? null : _submitAuth,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF176B87),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: isBusy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isCreatingAccount
                                  ? (isGreek ? 'Εγγραφή' : 'Create account')
                                  : (isGreek ? 'Σύνδεση' : 'Sign in'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          isGreek ? 'ή συνέχισε με' : 'or continue with',
                          style: const TextStyle(color: Color(0xFF637587)),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _socialSignInButton(
                    provider: OAuthProvider.google,
                    icon: Icons.g_mobiledata,
                    label: isGreek
                        ? 'Συνέχεια με Google'
                        : 'Continue with Google',
                  ),
                  const SizedBox(height: 10),
                  _socialSignInButton(
                    provider: OAuthProvider.apple,
                    icon: Icons.phone_iphone_outlined,
                    label: isGreek
                        ? 'Συνέχεια με Apple'
                        : 'Continue with Apple',
                  ),
                  const SizedBox(height: 10),
                  _socialSignInButton(
                    provider: OAuthProvider.azure,
                    icon: Icons.grid_view_rounded,
                    label: isGreek
                        ? 'Συνέχεια με Microsoft'
                        : 'Continue with Microsoft',
                  ),
                  if (!isCreatingAccount)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isBusy ? null : _sendPasswordReset,
                        child: Text(
                          isGreek ? 'Ξέχασες τον κωδικό;' : 'Forgot password?',
                        ),
                      ),
                    ),
                  Center(
                    child: TextButton(
                      onPressed: isBusy
                          ? null
                          : () => setState(() {
                              isCreatingAccount = !isCreatingAccount;
                              if (!isCreatingAccount) requestedRoles.clear();
                            }),
                      child: Text(
                        isCreatingAccount
                            ? (isGreek
                                  ? 'Έχεις ήδη λογαριασμό; Σύνδεση'
                                  : 'Already have an account? Sign in')
                            : (isGreek
                                  ? 'Δεν έχεις λογαριασμό; Εγγραφή'
                                  : 'New to SmartBlock? Create an account'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      isGreek
                          ? 'Διαχείριση πολυκατοικίας, απλά.'
                          : 'Building management, made simple.',
                      style: const TextStyle(
                        color: Color(0xFF637587),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
