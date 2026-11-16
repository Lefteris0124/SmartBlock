import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PropertyOwnersScreen extends StatefulWidget {
  const PropertyOwnersScreen({
    required this.propertyId,
    required this.propertyName,
    this.organizationId,
    required this.isGreek,
    super.key,
  });
  final String propertyId;
  final String propertyName;
  final String? organizationId;
  final bool isGreek;
  @override
  State<PropertyOwnersScreen> createState() => _PropertyOwnersScreenState();
}

class _PropertyOwnersScreenState extends State<PropertyOwnersScreen> {
  final _db = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _future;
  late bool _greek;
  @override
  void initState() {
    super.initState();
    _greek = widget.isGreek;
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async =>
      List<Map<String, dynamic>>.from(
        await _db
            .from('property_owners')
            .select(
              'id, organization_id, ownership_percentage, is_primary_representative, ownership_status, organizations(display_name, phone_e164, approval_status)',
            )
            .eq('property_id', widget.propertyId)
            .order('created_at'),
      );
  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  Future<void> _addOwner() async {
    final existing = await _load();
    final active = existing.where((row) => row['ownership_status'] == 'active');
    final used = active.fold<double>(
      0,
      (sum, row) =>
          sum + ((row['ownership_percentage'] as num?)?.toDouble() ?? 0),
    );
    final remaining = (100 - used).clamp(0, 100).toDouble();
    if (remaining <= 0) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _greek
                  ? 'Τα ποσοστά έχουν ήδη συμπληρώσει το 100%.'
                  : 'Ownership shares already total 100%.',
            ),
          ),
        );
      return;
    }
    final phone = TextEditingController();
    final name = TextEditingController();
    final share = TextEditingController(text: remaining.toStringAsFixed(2));
    final form = GlobalKey<FormState>();
    var orgType = 'individual';
    var primary = !active.any(
      (row) => row['is_primary_representative'] == true,
    );
    var saving = false;
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(_greek ? 'Σύνδεση ιδιοκτήτη' : 'Add property owner'),
          content: SizedBox(
            width: 430,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: _greek
                            ? 'Τηλέφωνο (διεθνής μορφή)'
                            : 'Phone (international format)',
                        hintText: '+35799123456',
                      ),
                      validator: (v) =>
                          v == null ||
                              !RegExp(r'^\+[1-9][0-9]{6,14}$')
                                  .hasMatch(v.trim())
                          ? (_greek
                                ? 'Χρησιμοποίησε μορφή +357...'
                                : 'Use international format, e.g. +357...')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: _greek
                            ? 'Όνομα ιδιοκτήτη (αν είναι νέος)'
                            : 'Owner name (if not registered)',
                      ),
                      validator: (v) =>
                          phone.text.trim().isNotEmpty &&
                              (v ?? '').trim().isEmpty
                          ? null
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: orgType,
                      decoration: InputDecoration(
                        labelText: _greek ? 'Τύπος' : 'Owner type',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'individual',
                          child: Text(_greek ? 'Ιδιώτης' : 'Individual'),
                        ),
                        DropdownMenuItem(
                          value: 'company',
                          child: Text(
                            _greek
                                ? 'Εταιρεία/οργανισμός'
                                : 'Company/organization',
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialog(() => orgType = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: share,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _greek
                            ? 'Ποσοστό ιδιοκτησίας'
                            : 'Ownership share',
                        suffixText: '%',
                      ),
                      validator: (v) {
                        final n = double.tryParse(
                          (v ?? '').replaceAll(',', '.'),
                        );
                        return n == null || n <= 0 || n > 100
                            ? (_greek
                                  ? 'Βάλε ποσοστό 0,01–100.'
                                  : 'Enter a share from 0.01 to 100.')
                            : null;
                      },
                    ),
                    CheckboxListTile(
                      value: primary,
                      onChanged: (v) => setDialog(() => primary = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        _greek ? 'Κύριος εκπρόσωπος' : 'Primary representative',
                      ),
                    ),
                    Text(
                      _greek
                          ? 'Αν το τηλέφωνο υπάρχει ήδη, επαναχρησιμοποιείται ο καταχωρημένος ιδιοκτήτης.'
                          : 'An existing owner record is reused when the phone number matches.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: Text(_greek ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      if (double.parse(share.text.replaceAll(',', '.')) >
                          remaining) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              _greek
                                  ? 'Το ποσοστό υπερβαίνει το υπόλοιπο ${remaining.toStringAsFixed(2)}%.'
                                  : 'Share exceeds the remaining ${remaining.toStringAsFixed(2)}%.',
                            ),
                          ),
                        );
                        return;
                      }
                      setDialog(() => saving = true);
                      try {
                        await _db.rpc(
                          'add_property_owner_by_phone',
                          params: {
                            'p_property_id': widget.propertyId,
                            'p_phone_e164': phone.text.trim(),
                            'p_display_name': name.text.trim(),
                            'p_organization_type': orgType,
                            'p_ownership_percentage': double.parse(
                              share.text.replaceAll(',', '.'),
                            ),
                            'p_is_primary_representative': primary,
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on PostgrestException catch (e) {
                        if (ctx.mounted) {
                          setDialog(() => saving = false);
                          ScaffoldMessenger.of(ctx)
                              .showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_greek ? 'Σύνδεση' : 'Link owner'),
            ),
          ],
        ),
      ),
    );
    phone.dispose();
    name.dispose();
    share.dispose();
    if (added == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_greek ? 'Ιδιοκτήτες' : 'Owners'),
      actions: [
        IconButton(
          onPressed: () => setState(() => _greek = !_greek),
          icon: const Icon(Icons.language),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addOwner,
      icon: const Icon(Icons.person_add_alt_1),
      label: Text(_greek ? 'Προσθήκη ιδιοκτήτη' : 'Add owner'),
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (ctx, snap) {
          final owners = snap.data ?? [];
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snap.hasError)
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(snap.error.toString()),
                ),
              ],
            );
          if (owners.isEmpty)
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _greek
                        ? 'Δεν έχει συνδεθεί ιδιοκτήτης. Πρόσθεσέ τον με το τηλέφωνό του.'
                        : 'No owner linked yet. Add one using their phone number.',
                  ),
                ),
              ],
            );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.propertyName,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ...owners.map((o) {
                final org = o['organizations'] as Map<String, dynamic>? ?? {};
                return Card(
                  child: ListTile(
                    leading: Icon(
                      o['is_primary_representative'] == true
                          ? Icons.verified_user_outlined
                          : Icons.person_outline,
                    ),
                    title: Text(org['display_name'] as String? ?? ''),
                    subtitle: Text(
                      '${org['phone_e164'] ?? ''} · ${o['ownership_percentage']}% · ${o['ownership_status']}',
                    ),
                    trailing: org['approval_status'] == 'approved'
                        ? const Icon(Icons.verified_outlined)
                        : const Icon(Icons.hourglass_top),
                  ),
                );
              }),
            ],
          );
        },
      ),
    ),
  );
}
