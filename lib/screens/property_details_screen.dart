import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'property_owners_screen.dart';

class PropertyDetailsScreen extends StatefulWidget {
  const PropertyDetailsScreen({
    required this.property,
    required this.organizationId,
    required this.organizationName,
    required this.organizationApprovalStatus,
    required this.isGreek,
    super.key,
  });

  final Map<String, dynamic> property;
  final String organizationId;
  final String organizationName;
  final String organizationApprovalStatus;
  final bool isGreek;

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  late Map<String, dynamic> _property;
  late bool _isGreek;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _property = Map<String, dynamic>.from(widget.property);
    _isGreek = widget.isGreek;
  }

  String _statusLabel(String? status) {
    if (!_isGreek) return (status ?? 'unknown').replaceAll('_', ' ');
    const labels = {
      'draft': 'Πρόχειρο',
      'pending_review': 'Σε αναμονή ελέγχου',
      'under_review': 'Υπό εξέταση',
      'changes_required': 'Απαιτούνται αλλαγές',
      'approved': 'Εγκεκριμένο',
      'rejected': 'Απορρίφθηκε',
      'suspended': 'Σε αναστολή',
    };
    return labels[status] ?? (status ?? 'Άγνωστη κατάσταση');
  }

  String _typeLabel(String? type) {
    const greek = {
      'apartment': 'Διαμέρισμα',
      'house': 'Κατοικία',
      'shop': 'Κατάστημα',
      'office': 'Γραφείο',
      'warehouse': 'Αποθήκη',
      'land': 'Οικόπεδο',
      'other': 'Άλλο',
    };
    const english = {
      'apartment': 'Apartment',
      'house': 'House',
      'shop': 'Shop',
      'office': 'Office',
      'warehouse': 'Warehouse',
      'land': 'Land',
      'other': 'Other',
    };
    return (_isGreek ? greek : english)[type] ?? (type ?? '');
  }

  String _modelLabel(String? model) {
    const greek = {
      'managed': 'Πλήρης διαχείριση',
      'assisted': 'Υποβοηθούμενη',
      'self_service': 'Αυτοδιαχείριση',
    };
    const english = {
      'managed': 'Managed',
      'assisted': 'Assisted',
      'self_service': 'Self-service',
    };
    return (_isGreek ? greek : english)[model] ?? (model ?? '');
  }

  Future<void> _submitForReview() async {
    setState(() => _isSubmitting = true);
    try {
      await _client.rpc(
        'submit_property_for_review',
        params: {'p_property_id': _property['id']},
      );
      if (!mounted) return;
      setState(() {
        _property = {..._property, 'approval_status': 'pending_review'};
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isGreek
                ? 'Το ακίνητο υποβλήθηκε για έλεγχο.'
                : 'Property submitted for review.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isGreek
                ? 'Δεν ήταν δυνατή η υποβολή. Δοκίμασε ξανά.'
                : 'Could not submit the property. Try again.',
          ),
        ),
      );
    }
  }

  Future<void> _openOwners() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PropertyOwnersScreen(
          propertyId: _property['id'] as String,
          propertyName: _property['name'] as String? ?? '',
          organizationId: widget.organizationId,
          isGreek: _isGreek,
        ),
      ),
    );
  }

  Widget _detailTile(IconData icon, String label, String value) => Card(
    elevation: 0,
    child: ListTile(
      leading: Icon(icon, color: const Color(0xFF176B87)),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(value, style: Theme.of(context).textTheme.titleSmall),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final address = [
      _property['address'],
      _property['city'],
      _property['country'],
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(', ');
    final status = _property['approval_status'] as String?;
    final canSubmit =
        widget.organizationApprovalStatus == 'approved' &&
        (status == 'draft' || status == 'changes_required');

    return Scaffold(
      appBar: AppBar(
        title: Text(_isGreek ? 'Στοιχεία ακινήτου' : 'Property details'),
        actions: [
          IconButton(
            tooltip: _isGreek ? 'English' : 'Ελληνικά',
            onPressed: () => setState(() => _isGreek = !_isGreek),
            icon: const Icon(Icons.language),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Text(
            _property['name'] as String? ?? '',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF17324D),
            ),
          ),
          const SizedBox(height: 8),
          Chip(
            avatar: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text(_statusLabel(status)),
          ),
          const SizedBox(height: 12),
          _detailTile(
            Icons.home_work_outlined,
            _isGreek ? 'Τύπος ακινήτου' : 'Property type',
            _typeLabel(_property['property_type'] as String?),
          ),
          _detailTile(
            Icons.location_on_outlined,
            _isGreek ? 'Τοποθεσία' : 'Location',
            address.isEmpty
                ? (_isGreek ? 'Δεν έχει οριστεί' : 'Not set')
                : address,
          ),
          _detailTile(
            Icons.settings_outlined,
            _isGreek ? 'Μοντέλο διαχείρισης' : 'Management model',
            _modelLabel(_property['management_model'] as String?),
          ),
          _detailTile(
            Icons.apartment_outlined,
            _isGreek ? 'Οργανισμός' : 'Organization',
            widget.organizationName,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _openOwners,
            icon: const Icon(Icons.people_outline),
            label: Text(
              _isGreek ? 'Συνιδιοκτήτες και ποσοστά' : 'Co-owners and shares',
            ),
          ),
          if (canSubmit) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitForReview,
              icon: _isSubmitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _isGreek ? 'Υποβολή για έλεγχο' : 'Submit for review',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isGreek
                  ? 'Πριν την υποβολή, τα ενεργά ποσοστά συνιδιοκτησίας πρέπει να αθροίζουν 100%.'
                  : 'Active ownership shares must total 100% before submission.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else if (status == 'draft' || status == 'changes_required') ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.hourglass_top_rounded),
                title: Text(
                  _isGreek
                      ? 'Η υποβολή θα ενεργοποιηθεί μετά την έγκριση του οργανισμού.'
                      : 'Review submission will be available after organization approval.',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
