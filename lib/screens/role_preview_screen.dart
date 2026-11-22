import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_language.dart';
import '../smartblock_text.dart';
import '../smartblock_trial_session.dart';
import 'smartblock_dashboard.dart';

class RolePreviewScreen extends StatefulWidget {
  const RolePreviewScreen({super.key});

  @override
  State<RolePreviewScreen> createState() => _RolePreviewScreenState();
}

class _RolePreviewScreenState extends State<RolePreviewScreen> {
  late bool _greek;
  late final VoidCallback _languageListener;
  String _role = 'owner';
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    final language = SmartBlockLanguageController.instance;
    _greek = language.selected.value.isGreek;
    _languageListener = () {
      if (mounted) setState(() => _greek = language.selected.value.isGreek);
    };
    language.selected.addListener(_languageListener);
  }

  @override
  void dispose() {
    SmartBlockLanguageController.instance.selected.removeListener(
      _languageListener,
    );
    super.dispose();
  }

  Future<void> _startTrial() async {
    if (_starting) return;
    setState(() => _starting = true);
    SupabaseClient? trialClient;
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'smartblock-admin-trial',
        body: {'role': _role},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      if (accessToken == null || refreshToken == null) {
        throw StateError('Trial session was not returned.');
      }

      trialClient = SupabaseClient(
        const String.fromEnvironment('SUPABASE_URL'),
        const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
      );
      await trialClient.auth.setSession(refreshToken, accessToken: accessToken);
      await SmartBlockTrialSession.start(client: trialClient, role: _role);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(builder: (_) => const SmartBlockDashboard()),
      );
    } catch (error) {
      await trialClient?.auth.signOut();
      if (!mounted) return;
      final details = error is FunctionException
          ? error.details.toString()
          : error.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _greek
                ? 'Δεν ξεκίνησε η δοκιμή. $details'
                : 'The trial could not start. $details',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_greek ? 'Λειτουργική δοκιμή' : 'Functional trial'),
      actions: const [SmartBlockLanguageMenu()],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      children: [
        Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 27),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _greek
                        ? 'Θα συνδεθείς σε ξεχωριστό δοκιμαστικό λογαριασμό με πραγματικά δικαιώματα και δεδομένα. Η συνεδρία admin παραμένει ανοιχτή και επιστρέφεις σε αυτήν όταν τελειώσεις.'
                        : 'You will enter a separate test account with real permissions and data. Your admin session stays open, and you can return to it when finished.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          _greek ? 'Δοκιμή ως' : 'Try the app as',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        RadioListTile<String>(
          value: 'owner',
          groupValue: _role,
          onChanged: _starting
              ? null
              : (value) => setState(() => _role = value!),
          title: Text(_greek ? 'Ιδιοκτήτης' : 'Property owner'),
          subtitle: Text(
            _greek
                ? 'Ακίνητα, ιδιοκτήτες, ψηφοφορίες, οικονομικά και διαχείριση.'
                : 'Properties, owners, votes, finances and management.',
          ),
          secondary: const Icon(Icons.apartment_outlined),
        ),
        RadioListTile<String>(
          value: 'tenant',
          groupValue: _role,
          onChanged: _starting
              ? null
              : (value) => setState(() => _role = value!),
          title: Text(_greek ? 'Ενοικιαστής' : 'Tenant'),
          subtitle: Text(
            _greek
                ? 'Διαμέρισμα, ενοίκιο, κοινόχρηστα, βλάβες και βοήθεια.'
                : 'Apartment, rent, common charges, service requests and help.',
          ),
          secondary: const Icon(Icons.home_outlined),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _starting ? null : _startTrial,
          icon: _starting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: Text(
            _starting
                ? (_greek ? 'Ετοιμάζεται…' : 'Preparing…')
                : (_greek ? 'Έναρξη δοκιμής' : 'Start trial'),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _greek
              ? 'Χρησιμοποιούνται μόνο δοκιμαστικά στοιχεία. Οι πληρωμές δεν χρεώνουν κάρτα και οι δοκιμαστικές ειδοποιήσεις δεν αποστέλλονται στο προσωπικό.'
              : 'Only test data is used. Payments do not charge a card, and trial notifications are not sent to staff.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}