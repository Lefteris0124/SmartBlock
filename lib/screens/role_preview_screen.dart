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
    required List<String> sampleItems,
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
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showModule(title, icon, sampleItems),
      ),
    );
  }

  Future<void> _showModule(
    String title,
    IconData icon,
    List<String> sampleItems,
  ) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Icon(icon),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(title,
                            style: Theme.of(context).textTheme.titleLarge),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    _greek
                        ? 'Ενδεικτικά στοιχεία προεπισκόπησης · δεν αποθηκεύονται'
                        : 'Sample preview data · nothing is saved',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const Divider(height: 24),
                Expanded(
                  child: ListView(
                    children: sampleItems
                        .map((item) => ListTile(
                              leading: const Icon(Icons.info_outline),
                              title: Text(item),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

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
              sampleItems: _greek
                  ? ['Boyoma Court · 12 διαμερίσματα', 'Διαμέρισμα 12 · 84 τ.μ. · 100% συμμετοχή']
                  : ['Boyoma Court · 12 apartments', 'Apartment 12 · 84 m² · 100% share'],
            ),
            _moduleCard(
              icon: Icons.how_to_vote_outlined,
              title: _greek ? 'Ψηφοφορίες και συνελεύσεις' : 'Votes and meetings',
              detail: _greek
                  ? 'Θέματα προς ψήφιση, αποτελέσματα και ενημερώσεις.'
                  : 'Items to vote on, results and updates.',
              sampleItems: _greek
                  ? ['Επισκευή ανελκυστήρα · Ανοιχτή έως 28/11', 'Επιλογή συνεργείου καθαρισμού · 8 από 12 ψήφισαν']
                  : ['Lift repair · Open until 28 Nov', 'Choose cleaning contractor · 8 of 12 voted'],
            ),
            _moduleCard(
              icon: Icons.account_balance_wallet_outlined,
              title: _greek ? 'Οικονομικά' : 'Finances',
              detail: _greek
                  ? 'Κοινόχρηστα, οφειλές, πληρωμές και οικονομική εικόνα.'
                  : 'Shared expenses, balances, payments and account overview.',
              sampleItems: _greek
                  ? ['Κοινόχρηστα Νοεμβρίου · €1.240 συνολικά', 'Πληρωμένα 8/12 διαμερίσματα · 4 εκκρεμούν']
                  : ['November shared expenses · €1,240 total', '8/12 apartments paid · 4 outstanding'],
            ),
            _moduleCard(
              icon: Icons.build_outlined,
              title: _greek ? 'Βλάβες και υπηρεσίες' : 'Repairs and services',
              detail: _greek
                  ? 'Αναφορές στο κτίριο ή σε ιδιοκτησία και εξέλιξη εργασιών.'
                  : 'Building or unit reports and service progress.',
              sampleItems: _greek
                  ? ['Ανελκυστήρας · Σε εξέλιξη', 'Διαμέρισμα 12 · Έλεγχος διαρροής προγραμματισμένος']
                  : ['Lift · In progress', 'Apartment 12 · Leak inspection scheduled'],
            ),
            _moduleCard(
              icon: Icons.campaign_outlined,
              title: _greek ? 'Ανακοινώσεις' : 'Announcements',
              detail: _greek
                  ? 'Ενημερώσεις της πολυκατοικίας και της διαχείρισης.'
                  : 'Building and management updates.',
              sampleItems: _greek
                  ? ['Καθαρισμός δεξαμενής νερού · 25/11', 'Γενική συνέλευση · 30/11, 18:00']
                  : ['Water tank cleaning · 25 Nov', 'General meeting · 30 Nov, 18:00'],
            ),
          ]
        : <Widget>[
            _moduleCard(
              icon: Icons.home_outlined,
              title: _greek ? 'Το διαμέρισμά μου' : 'My apartment',
              detail: _greek
                  ? 'Στοιχεία και ανακοινώσεις για το συνδεδεμένο διαμέρισμα.'
                  : 'Details and announcements for the assigned apartment.',
              sampleItems: _greek
                  ? ['Boyoma Court · Διαμέρισμα 12', '84 τ.μ. · Ιδιοκτήτης συνδεδεμένος']
                  : ['Boyoma Court · Apartment 12', '84 m² · Owner linked'],
            ),
            _moduleCard(
              icon: Icons.receipt_long_outlined,
              title: _greek ? 'Ενοίκιο και κοινόχρηστα' : 'Rent and shared expenses',
              detail: _greek
                  ? 'Οφειλές, ημερομηνίες πληρωμής και ιστορικό.'
                  : 'Balances, due dates and payment history.',
              sampleItems: _greek
                  ? ['Ενοίκιο Δεκεμβρίου · €1.200 · Πληρωμή έως 01/12', 'Κοινόχρηστα Νοεμβρίου · €85 · Εκκρεμούν']
                  : ['December rent · €1,200 · Due 1 Dec', 'November shared expenses · €85 · Due'],
            ),
            _moduleCard(
              icon: Icons.build_outlined,
              title: _greek ? 'Αναφορά βλάβης' : 'Report a problem',
              detail: _greek
                  ? 'Καταχώριση βλάβης στο διαμέρισμα ή στο κτίριο.'
                  : 'Report an issue in the apartment or building.',
              sampleItems: _greek
                  ? ['Διαμέρισμα · Διαρροή κάτω από τον νεροχύτη', 'Κτίριο · Ανελκυστήρας εκτός λειτουργίας']
                  : ['Apartment · Leak under the kitchen sink', 'Building · Lift out of service'],
            ),
            _moduleCard(
              icon: Icons.campaign_outlined,
              title: _greek ? 'Ανακοινώσεις' : 'Announcements',
              detail: _greek
                  ? 'Χρήσιμες ενημερώσεις για την πολυκατοικία.'
                  : 'Useful updates about the building.',
              sampleItems: _greek
                  ? ['Η είσοδος θα καθαριστεί την Τρίτη', 'Παρακαλούμε μην αφήνετε αντικείμενα στον διάδρομο']
                  : ['The entrance will be cleaned on Tuesday', 'Please keep the hallway clear'],
            ),
            _moduleCard(
              icon: Icons.support_agent_outlined,
              title: _greek ? 'Βοήθεια και chat' : 'Help and chat',
              detail: _greek
                  ? 'Επικοινωνία με τη διαχείριση ή την ομάδα υποστήριξης.'
                  : 'Contact management or the support team.',
              sampleItems: _greek
                  ? ['Η ομάδα SmartBlock είναι διαθέσιμη για βοήθεια', 'Τελευταία απάντηση · σήμερα, 10:42']
                  : ['SmartBlock support is available to help', 'Last reply · today, 10:42'],
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
                            ? 'Διαδραστική προεπισκόπηση με ενδεικτικά στοιχεία. Δεν αλλάζει ο λογαριασμός σου και δεν αποθηκεύονται αλλαγές.'
                            : 'Interactive preview with sample data. Your account is not switched and no changes are saved.',
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

