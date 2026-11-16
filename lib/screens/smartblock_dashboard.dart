import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'properties_screen.dart';

class SmartBlockDashboard extends StatefulWidget {
  const SmartBlockDashboard({super.key});

  @override
  State<SmartBlockDashboard> createState() => _SmartBlockDashboardState();
}

class _SmartBlockDashboardState extends State<SmartBlockDashboard> {
  final SupabaseClient _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _organizationsFuture;
  late Future<int> _propertyCountFuture;
  bool _isGreek = true;

  @override
  void initState() {
    super.initState();
    _organizationsFuture = _loadOrganizations();
    _propertyCountFuture = _loadPropertyCount();
  }

  Future<List<Map<String, dynamic>>> _loadOrganizations() async {
    final rows = await _client
        .from('organizations')
        .select('id, display_name, organization_type, approval_status')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<int> _loadPropertyCount() async {
    final rows = await _client.from('properties').select('id');
    return rows.length;
  }

  Future<void> _refreshOrganizations() async {
    final organizationsFuture = _loadOrganizations();
    final propertyCountFuture = _loadPropertyCount();
    setState(() {
      _organizationsFuture = organizationsFuture;
      _propertyCountFuture = propertyCountFuture;
    });
    try {
      await Future.wait([organizationsFuture, propertyCountFuture]);
    } catch (_) {
      // The FutureBuilder presents the query error in the page.
    }
  }

  Future<void> _createOrganization() async {
    final nameController = TextEditingController();
    final legalNameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var organizationType = 'individual';
    var isSaving = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_isGreek ? 'Νέος οργανισμός' : 'New organization'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: organizationType,
                    decoration: InputDecoration(
                      labelText: _isGreek ? 'Τύπος' : 'Type',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'individual',
                        child: Text(_isGreek ? 'Ιδιώτης' : 'Individual'),
                      ),
                      DropdownMenuItem(
                        value: 'company',
                        child: Text(_isGreek ? 'Εταιρεία' : 'Company'),
                      ),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(() => organizationType = value);
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: _isGreek ? 'Ονομασία' : 'Display name',
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? (_isGreek ? 'Συμπλήρωσε ονομασία.' : 'Enter a name.')
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: legalNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: _isGreek
                          ? 'Νομική επωνυμία (προαιρετικά)'
                          : 'Legal name (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isGreek
                        ? 'Ο οργανισμός θα σταλεί για έγκριση.'
                        : 'The organization will be submitted for review.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: Text(_isGreek ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final user = _client.auth.currentUser;
                      if (user == null) {
                        Navigator.pop(dialogContext, false);
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      try {
                        await _client.from('organizations').insert({
                          'organization_type': organizationType,
                          'display_name': nameController.text.trim(),
                          'legal_name': legalNameController.text.trim().isEmpty
                              ? null
                              : legalNameController.text.trim(),
                          'approval_status': 'pending_review',
                          'created_by': user.id,
                        });
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } on PostgrestException catch (error) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() => isSaving = false);
                        ScaffoldMessenger.of(
                          dialogContext,
                        ).showSnackBar(SnackBar(content: Text(error.message)));
                      } catch (_) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() => isSaving = false);
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              _isGreek
                                  ? 'Δεν ήταν δυνατή η αποθήκευση.'
                                  : 'Could not save the organization.',
                            ),
                          ),
                        );
                      }
                    },
              child: isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isGreek ? 'Υποβολή' : 'Submit'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    legalNameController.dispose();

    if (created == true && mounted) {
      await _refreshOrganizations();
      _showMessage(
        _isGreek
            ? 'Ο οργανισμός υποβλήθηκε για έγκριση.'
            : 'Organization submitted for review.',
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _organizationTypeLabel(String? type) {
    if (type == 'company') return _isGreek ? 'Εταιρεία' : 'Company';
    return _isGreek ? 'Ιδιώτης' : 'Individual';
  }

  String _approvalStatusLabel(String? status) {
    if (_isGreek) {
      switch (status) {
        case 'draft':
          return 'Πρόχειρο';
        case 'pending_review':
          return 'Σε αναμονή έγκρισης';
        case 'under_review':
          return 'Υπό εξέταση';
        case 'changes_required':
          return 'Απαιτούνται αλλαγές';
        case 'approved':
          return 'Εγκεκριμένος';
        case 'rejected':
          return 'Απορρίφθηκε';
        case 'suspended':
          return 'Σε αναστολή';
      }
    }
    return (status ?? 'unknown').replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = _client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartBlock'),
        actions: [
          IconButton(
            tooltip: _isGreek ? 'Switch to English' : 'Αλλαγή στα Ελληνικά',
            onPressed: () => setState(() => _isGreek = !_isGreek),
            icon: const Icon(Icons.language),
          ),
          IconButton(
            tooltip: _isGreek ? 'Αποσύνδεση' : 'Sign out',
            onPressed: () async => _client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshOrganizations,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _organizationsFuture,
          builder: (context, snapshot) {
            final organizations = snapshot.data ?? const [];
            final body = <Widget>[
              Text(
                _isGreek ? 'Οι οργανισμοί μου' : 'My organizations',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF17324D),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                user?.email ?? '',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      icon: Icons.apartment_rounded,
                      label: _isGreek ? 'Οργανισμοί' : 'Organizations',
                      value: snapshot.hasData ? '${organizations.length}' : '—',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FutureBuilder<int>(
                      future: _propertyCountFuture,
                      builder: (context, propertySnapshot) => _SummaryCard(
                        icon: Icons.home_work_outlined,
                        label: _isGreek ? 'Ακίνητα' : 'Properties',
                        value: propertySnapshot.hasData
                            ? '${propertySnapshot.data}'
                            : '—',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isGreek
                          ? 'Προσβάσιμοι οργανισμοί'
                          : 'Organizations you can access',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _createOrganization,
                    icon: const Icon(Icons.add),
                    label: Text(_isGreek ? 'Νέος' : 'New'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                _ErrorCard(
                  message: snapshot.error.toString(),
                  isGreek: _isGreek,
                  onRetry: _refreshOrganizations,
                )
              else if (organizations.isEmpty)
                _EmptyOrganizations(isGreek: _isGreek)
              else
                ...organizations.map(
                  (organization) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _OrganizationCard(
                      organizationId: organization['id'] as String,
                      name: organization['display_name'] as String? ?? '',
                      approvalStatus:
                          organization['approval_status'] as String? ??
                          'unknown',
                      type: _organizationTypeLabel(
                        organization['organization_type'] as String?,
                      ),
                      status: _approvalStatusLabel(
                        organization['approval_status'] as String?,
                      ),
                      isApproved: organization['approval_status'] == 'approved',
                      isGreek: _isGreek,
                    ),
                  ),
                ),
            ];

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
              children: body,
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF176B87)),
            const SizedBox(height: 16),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrganizationCard extends StatelessWidget {
  const _OrganizationCard({
    required this.organizationId,
    required this.name,
    required this.approvalStatus,
    required this.type,
    required this.status,
    required this.isApproved,
    required this.isGreek,
  });

  final String organizationId;
  final String name;
  final String approvalStatus;
  final String type;
  final String status;
  final bool isApproved;
  final bool isGreek;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PropertiesScreen(
              organizationId: organizationId,
              organizationName: name,
              organizationApprovalStatus: approvalStatus,
              isGreek: isGreek,
            ),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF176B87).withValues(alpha: 0.12),
          foregroundColor: const Color(0xFF176B87),
          child: const Icon(Icons.apartment_rounded),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('$type · $status'),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isApproved
                  ? Icons.verified_outlined
                  : Icons.hourglass_top_rounded,
              color: isApproved ? colorScheme.primary : colorScheme.tertiary,
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _EmptyOrganizations extends StatelessWidget {
  const _EmptyOrganizations({required this.isGreek});

  final bool isGreek;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(
              Icons.apartment_rounded,
              size: 48,
              color: Color(0xFF176B87),
            ),
            const SizedBox(height: 12),
            Text(
              isGreek ? 'Δεν έχεις οργανισμούς ακόμη' : 'No organizations yet',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isGreek
                  ? 'Δημιούργησε οργανισμό για να ξεκινήσεις την καταχώριση ακινήτων.'
                  : 'Create an organization to start registering properties.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.isGreek,
    required this.onRetry,
  });

  final String message;
  final bool isGreek;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isGreek ? 'Δεν φορτώθηκαν τα δεδομένα' : 'Could not load data',
            ),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(isGreek ? 'Δοκίμασε ξανά' : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
