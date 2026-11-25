import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_language.dart';
import 'screens/smartblock_dashboard.dart';
import 'screens/lease_contract_offer_screen.dart';
import 'smartblock_trial_session.dart';
import 'smartblock_text.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  runApp(const SmartBlockApp());
}

class SmartBlockApp extends StatefulWidget {
  const SmartBlockApp({super.key});

  @override
  State<SmartBlockApp> createState() => _SmartBlockAppState();
}

class _SmartBlockAppState extends State<SmartBlockApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    _initializeLanguage();
  }

  Future<void> _initializeLanguage() async {
    await SmartBlockLanguageController.instance.initialize();
    await SmartBlockLanguageController.instance.syncAfterSignIn();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SmartBlockLanguage>(
      valueListenable: SmartBlockLanguageController.instance.selected,
      builder: (context, language, _) => MaterialApp(
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'SmartBlock',
        locale: language.locale,
        supportedLocales: SmartBlockLanguages.supported
            .map((item) => item.locale)
            .toList(growable: false),
        localizationsDelegates: const [
          CountryLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF245B73),
            brightness: Brightness.light,
          ).copyWith(
            primary: const Color(0xFF245B73),
            secondary: const Color(0xFF438F83),
            surface: const Color(0xFFFFFEFC),
            surfaceContainerHighest: const Color(0xFFEAF1F2),
          ),
          scaffoldBackgroundColor: const Color(0xFFF4F7F7),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF4F7F7),
            foregroundColor: Color(0xFF17364A),
            elevation: 0,
            scrolledUnderElevation: 1,
            centerTitle: false,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF8FAFA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD9E3E5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD9E3E5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFF245B73),
                width: 1.7,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFFFFFEFC),
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0xFFE4EBEC)),
            ),
          ),
          fontFamily: 'Roboto',
        ),
        home: const CheckoutReturnNotice(child: AuthGate()),
        builder: (context, child) => Directionality(
          textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: ValueListenableBuilder<bool>(
            valueListenable: SmartBlockTrialSession.activeListenable,
            builder: (context, trialActive, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (trialActive || SmartBlockTrialSession.shouldShowReturnControls)
                  _TrialReturnBar(
                    isGreek: language.isGreek,
                    role: SmartBlockTrialSession.role,
                    onReturn: _returnToAdmin,
                  ),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Future<void> _returnToAdmin() async {
    await SmartBlockTrialSession.stop();
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }
}

class _TrialReturnBar extends StatelessWidget {
  const _TrialReturnBar({
    required this.isGreek,
    required this.role,
    required this.onReturn,
  });

  final bool isGreek;
  final String? role;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 430;
            final roleName = role == 'tenant'
                ? (isGreek ? 'Ενοικιαστής' : 'Tenant')
                : (isGreek ? 'Ιδιοκτήτης' : 'Owner');
            return Row(
              children: [
                Icon(Icons.science_outlined,
                    color: Theme.of(context).colorScheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isGreek
                        ? 'Λειτουργία δοκιμής · $roleName'
                        : 'Trial mode · $roleName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: isGreek ? 'Επιστροφή στον Admin' : 'Return to Admin',
                  child: FilledButton.tonalIcon(
                    onPressed: onReturn,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: Text(
                      compact
                          ? (isGreek ? 'Επιστροφή' : 'Return')
                          : (isGreek ? 'Επιστροφή στον Admin' : 'Return to Admin'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
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
    final inviteToken = Uri.base.queryParameters['lease_invite'];
    return StreamBuilder(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
          return const PasswordRecoveryScreen();
        }

        final session = Supabase.instance.client.auth.currentSession;

        if (session != null) {
          return _BiometricGate(
            userId: session.user.id,
            child: inviteToken != null && inviteToken.isNotEmpty
                ? LeaseContractOfferScreen(token: inviteToken)
                : const SmartBlockDashboard(),
          );
        }

        return LoginScreen(leaseInviteToken: inviteToken);
      },
    );
  }
}

class _BiometricGate extends StatefulWidget {
  const _BiometricGate({required this.userId, required this.child});
  final String userId;
  final Widget child;

  @override
  State<_BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<_BiometricGate> {
  final _auth = LocalAuthentication();
  bool _loading = true;
  bool _locked = false;
  bool _busy = false;

  String get _preferenceKey => 'smartblock_biometric_${widget.userId}';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (kIsWeb) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final enabled = preferences.getBool(_preferenceKey) ?? false;
    if (!mounted) return;
    setState(() {
      _locked = enabled;
      _loading = false;
    });
    if (enabled) await _unlock();
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final available = await _auth.getAvailableBiometrics();
      final authenticated = available.isNotEmpty && await _auth.authenticate(
        localizedReason: 'Unlock your SmartBlock account',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (mounted && authenticated) setState(() => _locked = false);
    } catch (_) {
      // The account stays protected and the user can retry or sign out.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_locked) return widget.child;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.fingerprint, size: 64, color: Color(0xFF245B73)),
            const SizedBox(height: 16),
            const Text('Unlock SmartBlock with biometrics'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _unlock,
              icon: const Icon(Icons.face),
              label: Text(_busy ? 'Waiting for device…' : 'Use Face ID / fingerprint'),
            ),
            TextButton(
              onPressed: () async {
                await SharedPreferences.getInstance().then((p) => p.remove(_preferenceKey));
                await Supabase.instance.client.auth.signOut();
              },
              child: const Text('Sign out and use password'),
            ),
          ]),
        ),
      ),
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
  late final VoidCallback _languageListener;

  @override
  void initState() {
    super.initState();
    final language = SmartBlockLanguageController.instance;
    _isGreek = language.selected.value.isGreek;
    _languageListener = () {
      if (mounted) setState(() => _isGreek = language.selected.value.isGreek);
    };
    language.selected.addListener(_languageListener);
  }

  @override
  void dispose() {
    SmartBlockLanguageController.instance.selected.removeListener(
      _languageListener,
    );
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
                      child: const SmartBlockLanguageMenu(iconOnly: false),
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
  const LoginScreen({this.leaseInviteToken, super.key});
  final String? leaseInviteToken;

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
  late final VoidCallback _languageListener;
  String get _authRedirectUrl {
    if (!kIsWeb) return 'io.supabase.smartblock://login-callback';
    final token = widget.leaseInviteToken;
    if (token == null || token.isEmpty) return Uri.base.origin + Uri.base.path;
    return Uri.base.replace(
      queryParameters: {...Uri.base.queryParameters, 'lease_invite': token},
    ).toString();
  }

  @override
  void initState() {
    super.initState();
    final language = SmartBlockLanguageController.instance;
    isGreek = language.selected.value.isGreek;
    if (widget.leaseInviteToken != null) requestedRoles.add('tenant');
    _languageListener = () {
      if (mounted) setState(() => isGreek = language.selected.value.isGreek);
    };
    language.selected.addListener(_languageListener);
  }

  @override
  void dispose() {
    SmartBlockLanguageController.instance.selected.removeListener(
      _languageListener,
    );
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
          data: {
            'requested_roles': {...requestedRoles, if (widget.leaseInviteToken != null) 'tenant'}.toList(),
            'preferred_language':
                SmartBlockLanguageController.instance.selected.value.code,
          },
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
        await SmartBlockLanguageController.instance.syncAfterSignIn();
        if (!mounted) return;
        _showMessage(isGreek ? 'Επιτυχής σύνδεση!' : 'Signed in successfully.');
      }
    } on AuthException catch (error) {
      if (!mounted) return;
      // Supabase intentionally returns the same auth error for an unknown email
      // and a bad password. Keep the UI clear without exposing account existence.
      final message = error.code == 'email_not_confirmed'
          ? (isGreek
                ? 'Επιβεβαίωσε πρώτα το email σου από το μήνυμα που έλαβες.'
                : 'Confirm your email first using the message we sent you.')
          : (isGreek
                ? 'Τα στοιχεία σύνδεσης δεν είναι σωστά. Έλεγξε email και κωδικό ή κάνε εγγραφή.'
                : 'Your sign-in details are incorrect. Check your email and password, or create an account.');
      _showMessage(message);
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
                    child: const SmartBlockLanguageMenu(iconOnly: false),
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
                  if (widget.leaseInviteToken != null) ...[
                    const SizedBox(height: 14),
                    Card(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined),
                        title: Text(isGreek ? 'Έχεις πρόσκληση μίσθωσης' : 'You have a rental invitation'),
                        subtitle: Text(isGreek
                            ? 'Συνδέσου ή δημιούργησε λογαριασμό με το email στο οποίο στάλθηκε ο σύνδεσμος.'
                            : 'Sign in or create an account using the email that received the link.'),
                      ),
                    ),
                  ],
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
                          label: Text(
                            isGreek ? 'Ιδιοκτήτης' : 'Property owner',
                          ),
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

