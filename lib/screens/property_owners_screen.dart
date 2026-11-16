import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PropertyOwnersScreen extends StatefulWidget {
  const PropertyOwnersScreen({
    required this.propertyId,
    required this.propertyName,
    required this.organizationId,
    required this.isGreek,
    super.key,
  });

  final String propertyId;
  final String propertyName;
  final String organizationId;
  final bool isGreek;

  @override
  State<PropertyOwnersScreen> createState() => _PropertyOwnersScreenState();
}

class _PropertyOwnersScreenState extends State<PropertyOwnersScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _ownersFuture;
  late bool _isGreek;

  @override
  void initState() {
    super.initState();
    _isGreek = widget.isGreek;
    _ownersFuture = _loadOwners();
  }

  Future<List<Map<String, dynamic>>> _loadOwners() async {
    final rows = await _client
        .from('property_owners')
        .select(
          'id, organization_id, ownership_percentage, is_primary_representative, ownership_status, organizations(display_name)',
        )
        .eq('property_id', widget.propertyId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> _loadOrganizations() async {
    final rows = await _client
        .from('organizations')
        .select('id, display_name, approval_status')
        .order('display_name');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _refresh() async {
    final future = _loadOwners();
    setState(() => _ownersFuture = future);
    try {
      await future;
    } catch (_) {
      // The page offers a retry action for load errors.
    }
  }

  Future<void> _addOwner() async {
    List<Map<String, dynamic>> owners;
    List<Map<String, dynamic>> organizations;
    try {
      owners = await _loadOwners();
      organizations = await _loadOrganizations();
    } on PostgrestException catch (error) {
      if (!context.mounted) return;
      _showMessage(error.message);
      return;
    }
    if (!mounted) return;

    final activeOwners = owners
        .where((owner) => owner['ownership_status'] == 'active')
        .toList();
    final total = activeOwners.fold<double>(
      0,
      (sum, owner) => sum + _asDouble(owner['ownership_percentage']),
    );
    final remaining = (100 - total).clamp(0, 100).toDouble();
    final hasPrimary = activeOwners.any(
      (owner) => owner['is_primary_representative'] == true,
    );
    final activeOrganizationIds = activeOwners
        .map((owner) => owner['organization_id'] as String)
        .toSet();
    final availableOrganizations = organizations
        .where(
          (organization) => !activeOrganizationIds.contains(organization['id']),
        )
        .toList();

    if (remaining <= 0) {
      _showMessage(
        _isGreek
            ? 'Δεν απομένει ποσοστό ιδιοκτησίας για νέο συνιδιοκτήτη.'
            : 'There is no ownership share left for another co-owner.',
      );
      return;
    }
    if (availableOrganizations.isEmpty) {
      _showMessage(
        _isGreek
            ? 'Δεν υπάρχει διαθέσιμος οργανισμός για προσθήκη.'
            : 'There is no available organization to add.',
      );
      return;
    }

    final percentageController = TextEditingController(
      text: remaining.toStringAsFixed(2),
    );
    final formKey = GlobalKey<FormState>();
    String? selectedOrganizationId =
        availableOrganizations.any(
          (organization) => organization['id'] == widget.organizationId,
        )
        ? widget.organizationId
        : availableOrganizations.first['id'] as String;
    var isPrimaryRepresentative = !hasPrimary;
    var isSaving = false;

    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_isGreek ? 'Προσθήκη συνιδιοκτήτη' : 'Add co-owner'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedOrganizationId,
                    decoration: InputDecoration(
                      labelText: _isGreek
                          ? 'Οργανισμός ιδιοκτήτη'
                          : 'Owner organization',
                    ),
                    items: availableOrganizations.map((organization) {
                      final name =
                          organization['display_name'] as String? ?? '';
                      final status = organization['approval_status'] as String?;
                      return DropdownMenuItem<String>(
                        value: organization['id'] as String,
                        child: Text(
                          status == 'approved'
                              ? name
                              : '$name (${_isGreek ? 'εκκρεμεί έγκριση' : 'pending approval'})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: isSaving
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(
                                () => selectedOrganizationId = value,
                              );
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: percentageController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _isGreek
                          ? 'Ποσοστό ιδιοκτησίας'
                          : 'Ownership percentage',
                      suffixText: '%',
                      helperText: _isGreek
                          ? 'Διαθέσιμο ποσοστό: ${remaining.toStringAsFixed(2)}%'
                          : 'Available share: ${remaining.toStringAsFixed(2)}%',
                    ),
                    validator: (value) {
                      final percentage = double.tryParse(
                        (value ?? '').trim().replaceAll(',', '.'),
                      );
                      if (percentage == null || percentage <= 0) {
                        return _isGreek
                            ? 'Βάλε ποσοστό μεγαλύτερο από 0.'
                            : 'Enter a percentage above 0.';
                      }
                      if (percentage > remaining) {
                        return _isGreek
                            ? 'Το ποσοστό υπερβαίνει το διαθέσιμο υπόλοιπο.'
                            : 'The percentage exceeds the available share.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isPrimaryRepresentative,
                    onChanged: isSaving || hasPrimary
                        ? null
                        : (value) => setDialogState(
                            () => isPrimaryRepresentative = value ?? false,
                          ),
                    title: Text(
                      _isGreek
                          ? 'Κύριος εκπρόσωπος ακινήτου'
                          : 'Primary property representative',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  Text(
                    _isGreek
                        ? 'Η προσθήκη γίνεται μόνο αν ο συνδεδεμένος χρήστης έχει δικαίωμα διαχείρισης στον οργανισμό.'
                        : 'The insert succeeds only if the signed-in user can manage the selected organization.',
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
                      if (user == null || selectedOrganizationId == null) {
                        Navigator.pop(dialogContext, false);
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      final percentage = double.parse(
                        percentageController.text.trim().replaceAll(',', '.'),
                      );
                      try {
                        await _client.from('property_owners').insert({
                          'property_id': widget.propertyId,
                          'organization_id': selectedOrganizationId,
                          'ownership_percentage': percentage.toStringAsFixed(2),
                          'is_primary_representative': isPrimaryRepresentative,
                          'ownership_status': 'active',
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
                                  ? 'Δεν ήταν δυνατή η προσθήκη.'
                                  : 'Could not add the co-owner.',
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
                  : Text(_isGreek ? 'Προσθήκη' : 'Add'),
            ),
          ],
        ),
      ),
    );

    percentageController.dispose();
    if (added == true && mounted) await _refresh();
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _statusLabel(String? status) {
    if (!_isGreek) return (status ?? '').replaceAll('_', ' ');
    switch (status) {
      case 'active':
        return 'Ενεργός';
      case 'transferred':
        return 'Μεταβιβάστηκε';
      case 'inactive':
        return 'Ανενεργός';
      default:
        return status ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isGreek ? 'Ιδιοκτησία' : 'Ownership'),
        actions: [
          IconButton(
            tooltip: _isGreek ? 'English' : 'Ελληνικά',
            onPressed: () => setState(() => _isGreek = !_isGreek),
            icon: const Icon(Icons.language),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addOwner,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(_isGreek ? 'Συνιδιοκτήτης' : 'Co-owner'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _ownersFuture,
          builder: (context, snapshot) {
            final owners = snapshot.data ?? const [];
            final activeOwners = owners
                .where((owner) => owner['ownership_status'] == 'active')
                .toList();
            final total = activeOwners.fold<double>(
              0,
              (sum, owner) => sum + _asDouble(owner['ownership_percentage']),
            );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
              children: [
                Text(
                  widget.propertyName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF17324D),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isGreek
                      ? 'Συνιδιοκτήτες και ποσοστά'
                      : 'Co-owners and shares',
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ListTile(
                    leading: const Icon(Icons.pie_chart_outline),
                    title: Text(
                      _isGreek
                          ? 'Σύνολο ενεργών ποσοστών'
                          : 'Total active ownership',
                    ),
                    trailing: Text(
                      '${total.toStringAsFixed(2)}%',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    subtitle: total < 100
                        ? Text(
                            _isGreek
                                ? 'Διαθέσιμο: ${(100 - total).toStringAsFixed(2)}%'
                                : 'Available: ${(100 - total).toStringAsFixed(2)}%',
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isGreek
                                ? 'Δεν φορτώθηκαν οι ιδιοκτήτες'
                                : 'Could not load owners',
                          ),
                          const SizedBox(height: 8),
                          Text(snapshot.error.toString()),
                          TextButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: Text(
                              _isGreek ? 'Δοκίμασε ξανά' : 'Try again',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (owners.isEmpty)
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _isGreek
                            ? 'Δεν έχουν καταχωριστεί ιδιοκτήτες. Πρόσθεσε τον οργανισμό ιδιοκτησίας και τα ποσοστά του.'
                            : 'No owners have been added. Add the ownership organization and share percentages.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ...owners.map((owner) {
                    final organization = owner['organizations'];
                    final organizationName =
                        organization is Map<String, dynamic>
                        ? organization['display_name'] as String? ?? ''
                        : '';
                    final active = owner['ownership_status'] == 'active';
                    final isPrimary =
                        owner['is_primary_representative'] == true;
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0x1F176B87),
                          foregroundColor: const Color(0xFF176B87),
                          child: Icon(
                            isPrimary
                                ? Icons.star_outline
                                : Icons.person_outline,
                          ),
                        ),
                        title: Text(
                          organizationName.isEmpty
                              ? (_isGreek
                                    ? 'Οργανισμός ιδιοκτήτη'
                                    : 'Owner organization')
                              : organizationName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            if (isPrimary)
                              _isGreek
                                  ? 'Κύριος εκπρόσωπος'
                                  : 'Primary representative',
                            _statusLabel(owner['ownership_status'] as String?),
                          ].join(' · '),
                        ),
                        trailing: Text(
                          '${_asDouble(owner['ownership_percentage']).toStringAsFixed(2)}%',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: active ? const Color(0xFF176B87) : null,
                              ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                Text(
                  _isGreek
                      ? 'Τα συνολικά ενεργά ποσοστά ελέγχονται από τη βάση και δεν μπορούν να ξεπεράσουν το 100%.'
                      : 'The database checks active shares and prevents the total from exceeding 100%.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
