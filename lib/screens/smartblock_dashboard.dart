import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_review_screen.dart';
import 'properties_screen.dart';

class SmartBlockDashboard extends StatefulWidget {
  const SmartBlockDashboard({super.key});

  @override
  State<SmartBlockDashboard> createState() => _SmartBlockDashboardState();
}

class _SmartBlockDashboardState extends State<SmartBlockDashboard> {
  final _client = Supabase.instance.client;
  late Future<_RoleAccess> _access = _loadAccess();
  bool _greek = true;

  Future<_RoleAccess> _loadAccess() async {
    final results = await Future.wait<dynamic>([
      _client.rpc('is_smartblock_staff'),
      _client.rpc('list_my_resident_properties'),
      _client.from('properties').select('id').limit(1),
    ]);
    return _RoleAccess(
      isStaff: results[0] == true,
      residentCount: (results[1] as List).length,
      ownerHasProperties: (results[2] as List).isNotEmpty,
    );
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) setState(() => _access = _loadAccess());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('SmartBlock'),
      actions: [
        IconButton(
          tooltip: _greek ? 'English' : 'Ελληνικά',
          onPressed: () => setState(() => _greek = !_greek),
          icon: const Icon(Icons.language),
        ),
        IconButton(
          tooltip: _greek ? 'Αποσύνδεση' : 'Sign out',
          onPressed: () => _client.auth.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: FutureBuilder<_RoleAccess>(
      future: _access,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 42),
                  const SizedBox(height: 12),
                  Text(_greek
                      ? 'Δεν φορτώθηκαν οι προσβάσεις. Έλεγξε τη σύνδεση.'
                      : 'Could not load your access. Check your connection.'),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => setState(() => _access = _loadAccess()),
                    child: Text(_greek ? 'Δοκιμή ξανά' : 'Try again'),
                  ),
                ],
              ),
            ),
          );
        }

        final access = snapshot.data!;
        final isResident = access.residentCount > 0;
        final showOwner = access.ownerHasProperties || !isResident;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              _greek ? 'Πού θέλεις να πας;' : 'Where would you like to go?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(_greek
                ? 'Οι λειτουργίες εμφανίζονται ανάλογα με τον ρόλο και την πρόσβασή σου.'
                : 'Features are separated by your role and assigned access.'),
            const SizedBox(height: 20),
            if (access.isStaff)
              _RoleCard(
                icon: Icons.admin_panel_settings_outlined,
                title: _greek ? 'Διαχείριση SmartBlock' : 'SmartBlock admin',
                detail: _greek
                    ? 'Εγκρίσεις, ακίνητα, οργανισμοί και προσβάσεις.'
                    : 'Reviews, properties, organizations and access.',
                onTap: () => _open(AdminReviewScreen(isGreek: _greek)),
              ),
            if (showOwner)
              _RoleCard(
                icon: Icons.apartment_outlined,
                title: _greek ? 'Ιδιοκτήτης / διαχειριστής' : 'Owner / manager',
                detail: _greek
                    ? 'Ακίνητα, ιδιοκτήτες, ψηφοφορίες, ανακοινώσεις και οικονομικά.'
                    : 'Properties, owners, votes, notices and finances.',
                onTap: () => _open(PropertiesScreen(
                  isGreek: _greek,
                  viewMode: PropertiesViewMode.owner,
                )),
              ),
            if (isResident)
              _RoleCard(
                icon: Icons.home_outlined,
                title: _greek ? 'Ένοικος' : 'Resident',
                detail: _greek
                    ? 'Το διαμέρισμά σου, αναφορές βλαβών και αιτήματα υπηρεσιών.'
                    : 'Your apartment, problem reports and service requests.',
                onTap: () => _open(PropertiesScreen(
                  isGreek: _greek,
                  viewMode: PropertiesViewMode.resident,
                )),
              ),
            if (!isResident)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(_greek ? 'Πρόσβαση ενοίκου' : 'Resident access'),
                  subtitle: Text(_greek
                      ? 'Ο διαχειριστής της πολυκατοικίας πρέπει να συνδέσει το email του λογαριασμού σου με το διαμέρισμά σου.'
                      : 'Your building manager needs to assign your account email to your apartment.'),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _RoleAccess {
  const _RoleAccess({
    required this.isStaff,
    required this.residentCount,
    required this.ownerHasProperties,
  });

  final bool isStaff;
  final int residentCount;
  final bool ownerHasProperties;
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(detail),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}
