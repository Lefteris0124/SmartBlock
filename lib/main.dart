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
      home: const AuthGate(),
    );
  }
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
  String get _authRedirectUrl =>
      kIsWeb
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

    setState(() => isBusy = true);
    try {
      if (isCreatingAccount) {
        final response = await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: _authRedirectUrl,
        );
        if (!mounted) return;
        if (response.session == null) {
          _showMessage(
            isGreek
                ? 'Ο λογαριασμός δημιουργήθηκε. Έλεγξε το email σου για επιβεβαίωση.'
                : 'Account created. Check your email to confirm it.',
          );
        } else {
          _showMessage(
            isGreek ? 'Ο λογαριασμός δημιουργήθηκε.' : 'Account created.',
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
                          : () => setState(
                              () => isCreatingAccount = !isCreatingAccount,
                            ),
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
