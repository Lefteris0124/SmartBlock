import 'package:flutter/material.dart' hide Text;

import '../app_language.dart';
import '../smartblock_text.dart';

enum _PreviewRole { owner, tenant, both }

class RolePreviewScreen extends StatefulWidget {
  const RolePreviewScreen({super.key});

  @override
  State<RolePreviewScreen> createState() => _RolePreviewScreenState();
}

class _RolePreviewScreenState extends State<RolePreviewScreen> {
  late bool _greek;
  late final VoidCallback _languageListener;
  _PreviewRole _selectedRole = _PreviewRole.owner;

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
    SmartBlockLanguageController.instance.selected
        .removeListener(_languageListener);
    super.dispose();
  }

  Widget _moduleCard({
    required IconData icon,
    required String title,
    required String detail,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          child: Icon(icon, color: colors.primary),
        ),
        title: Text(title),
        subtitle: Text(detail),
        trailing: const Icon(Icons.visibility_outlined),
      ),
    );
  }

  Widget _roleContent(_PreviewRole role) {
    final isOwner = role == _PreviewRole.owner;
    final color = isOwner ? const Color(0xFF245B73) : const Color(0xFF438F83);
    final title = isOwner
        ? (_greek ? 'Ιδιοκτήτης / διαχειριστής' : 'Owner / manager')
        : (_greek ? 'Ενοικιαστής' : 'Tenant');
    final modules = isOwner
        ? <Widget>[
            _moduleCard(
              icon: Icons.apartment_outlined,
              title: _greek ? 'Τα ακίνητά μου' : 'My properties',
              detail: _greek
                  ? 'Πολυκατοικίες και ιδιοκτησίες που έχουν συνδεθεί με τον λογαριασμό.'
                  : 'Buildings and properties linked to the account.',
            ),
            _moduleCard(
              icon: Icons.how_to_vote_outlined,
              title: _greek ? 'Ψηφοφορίες και συνελεύσεις' : 'Votes and meetings',
              detail: _greek
                  ? 'Θέματα προς ψήφιση, αποτελέσματα και ενημερώσεις.'
                  : 'Items to vote on, results and updates.',
            ),
            _moduleCard(
              icon: Icons.account_balance_wallet_outlined,
              title: _greek ? 'Οικονομικά' : 'Finances',
              detail: _greek
                  ? 'Κοινόχρηστα, οφειλές, πληρωμές και οικονομική εικόνα.'
                  : 'Shared expenses, balances, payments and account overview.',
            ),
            _moduleCard(
              icon: Icons.build_outlined,
              title: _greek ? 'Βλάβες και υπηρεσίες' : 'Repairs and services',
              detail: _greek
                  ? 'Αναφορές στο κτίριο ή σε ιδιοκτησία και εξέλιξη εργασιών.'
                  : 'Building or unit reports and service progress.',
            ),
            _moduleCard(
              icon: Icons.campaign_outlined,
              title: _greek ? 'Ανακοινώσεις' : 'Announcements',
              detail: _greek
                  ? 'Ενημερώσεις της πολυκατοικίας και της διαχείρισης.'
                  : 'Building and management updates.',
            ),
          ]
        : <Widget>[
            _moduleCard(
              icon: Icons.home_outlined,
              title: _greek ? 'Το διαμέρισμά μου' : 'My apartment',
              detail: _greek
                  ? 'Στοιχεία και ανακοινώσεις για το συνδεδεμένο διαμέρισμα.'
                  : 'Details and announcements for the assigned apartment.',
            ),
            _moduleCard(
              icon: Icons.receipt_long_outlined,
              title: _greek ? 'Ενοίκιο και κοινόχρηστα' : 'Rent and shared expenses',
              detail: _greek
                  ? 'Οφειλές, ημερομηνίες πληρωμής και ιστορικό.'
                  : 'Balances, due dates and payment history.',
            ),
            _moduleCard(
              icon: Icons.build_outlined,
              title: _greek ? 'Αναφορά βλάβης' : 'Report a problem',
              detail: _greek
                  ? 'Καταχώριση βλάβης στο διαμέρισμα ή στο κτίριο.'
                  : 'Report an issue in the apartment or building.',
            ),
            _moduleCard(
              icon: Icons.campaign_outlined,
              title: _greek ? 'Ανακοινώσεις' : 'Announcements',
              detail: _greek
                  ? 'Χρήσιμες ενημερώσεις για την πολυκατοικία.'
                  : 'Useful updates about the building.',
            ),
            _moduleCard(
              icon: Icons.support_agent_outlined,
              title: _greek ? 'Βοήθεια και chat' : 'Help and chat',
              detail: _greek
                  ? 'Επικοινωνία με τη διαχείριση ή την ομάδα υποστήριξης.'
                  : 'Contact management or the support team.',
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        ...modules,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_greek ? 'Προβολή ως χρήστης' : 'Preview as user'),
          actions: const [SmartBlockLanguageMenu()],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.visibility_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _greek
                            ? 'Προεπισκόπηση οθονών μόνο. Δεν αλλάζει ο λογαριασμός σου και δεν εκτελούνται ενέργειες ως άλλος χρήστης. Για έλεγχο πραγματικών δεδομένων και δικαιωμάτων, χρειάζεται δοκιμαστικός λογαριασμός με σύνδεση στο αντίστοιχο ακίνητο.'
                            : 'Screen preview only. Your account is not switched and no actions run as another user. To verify real data and permissions, use a test account linked to the relevant property.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _greek ? 'Επίλεξε ιδιότητα' : 'Choose a role',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.apartment_outlined),
                  label: Text(_greek ? 'Ιδιοκτήτης' : 'Owner'),
                  selected: _selectedRole == _PreviewRole.owner,
                  onSelected: (_) =>
                      setState(() => _selectedRole = _PreviewRole.owner),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.home_outlined),
                  label: Text(_greek ? 'Ενοικιαστής' : 'Tenant'),
                  selected: _selectedRole == _PreviewRole.tenant,
                  onSelected: (_) =>
                      setState(() => _selectedRole = _PreviewRole.tenant),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.people_outline),
                  label: Text(_greek ? 'Και οι δύο' : 'Both'),
                  selected: _selectedRole == _PreviewRole.both,
                  onSelected: (_) =>
                      setState(() => _selectedRole = _PreviewRole.both),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_selectedRole == _PreviewRole.owner ||
                _selectedRole == _PreviewRole.both)
              _roleContent(_PreviewRole.owner),
            if (_selectedRole == _PreviewRole.tenant ||
                _selectedRole == _PreviewRole.both)
              _roleContent(_PreviewRole.tenant),
          ],
        ),
      );
}
