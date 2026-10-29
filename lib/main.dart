
import 'package:flutter/material.dart';

void main() {
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B87),
        ),
        fontFamily: 'Roboto',
      ),
      home: const LoginScreen(),
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

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = isGreek ? 'Καλώς ήρθες!' : 'Welcome!';
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
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isGreek
                                  ? 'Η σύνδεση θα ενεργοποιηθεί στο επόμενο βήμα.'
                                  : 'Login will be enabled in the next step.',
                            ),
                          ),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF176B87),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        isGreek ? 'Σύνδεση' : 'Sign in',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
