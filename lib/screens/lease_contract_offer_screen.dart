import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../smartblock_trial_session.dart';
import 'smartblock_dashboard.dart';

class LeaseContractOfferScreen extends StatefulWidget {
  const LeaseContractOfferScreen({required this.token, super.key});
  final String token;

  @override
  State<LeaseContractOfferScreen> createState() =>
      _LeaseContractOfferScreenState();
}

class _LeaseContractOfferScreenState extends State<LeaseContractOfferScreen> {
  final _db = SmartBlockTrialSession.client;
  late Future<Map<String, dynamic>> _offer = _loadOffer();
  final _name = TextEditingController();
  final _idNumber = TextEditingController();
  final _idCountry = TextEditingController();
  final _idExpiry = TextEditingController();
  String _idTypeValue = 'national_id';
  bool _confirmed = false;
  bool _saving = false;
  bool _accepted = false;
  bool _greek = true;

  @override
  void initState() {
    super.initState();
    final user = _db.auth.currentUser;
    _greek = (user?.userMetadata?['preferred_language'] ?? 'el') == 'el';
    _name.text = user?.userMetadata?['full_name']?.toString() ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _idNumber.dispose();
    _idCountry.dispose();
    _idExpiry.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadOffer() async {
    final value = await _db.rpc(
      'get_lease_contract_offer',
      params: {'p_token': widget.token},
    );
    final offer = Map<String, dynamic>.from(value as Map);
    if (_idNumber.text.isEmpty) {
      final storedType = offer['tenant_id_type']?.toString();
      if (storedType == 'national_id' || storedType == 'passport') _idTypeValue = storedType!;
      _idCountry.text = offer['tenant_id_country']?.toString() ?? '';
      _idNumber.text = offer['tenant_id_number']?.toString() ?? '';
      _idExpiry.text = offer['tenant_id_expiry_date']?.toString() ?? '';
    }
    return offer;
  }

  bool _validFutureDate(String value) {
    final date = DateTime.tryParse(value);
    final now = DateTime.now();
    return date != null && !date.isBefore(DateTime(now.year, now.month, now.day));
  }

  Future<void> _chooseExpiryDate() async {
    final now = DateTime.now();
    final stored = DateTime.tryParse(_idExpiry.text);
    final date = await showDatePicker(
      context: context,
      initialDate: stored == null || stored.isBefore(now) ? now : stored,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 30),
    );
    if (date != null) {
      _idExpiry.text = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '—';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _item(String title, dynamic value, {IconData? icon}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 10)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 2),
              Text((value?.toString().trim().isNotEmpty ?? false) ? value.toString() : '—'),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _accept() async {
    if (_saving || !_confirmed) return;
    if (_name.text.trim().length < 3 ||
        _idCountry.text.trim().isEmpty ||
        _idNumber.text.trim().isEmpty ||
        !_validFutureDate(_idExpiry.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_greek
              ? 'Συμπλήρωσε ονοματεπώνυμο, χώρα έκδοσης, αριθμό και ημερομηνία λήξης εγγράφου.'
              : 'Enter your full name, issuing country, document number, and expiry date.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _db.rpc(
        'accept_apartment_lease_offer',
        params: {
          'p_token': widget.token,
          'p_signer_name': _name.text.trim(),
          'p_tenant_id_type': _idTypeValue,
          'p_tenant_id_country': _idCountry.text.trim(),
          'p_tenant_id_number': _idNumber.text.trim(),
          'p_tenant_id_expiry_date': _idExpiry.text,
          'p_confirm': true,
        },
      );
      if (!mounted) return;
      setState(() {
        _accepted = true;
        _offer = _loadOffer();
      });
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_greek ? 'Πρόταση μίσθωσης' : 'Rental agreement offer'),
      leading: IconButton(
        tooltip: _greek ? 'Πίσω' : 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _offer,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 42),
                      const SizedBox(height: 12),
                      Text(
                        _greek
                            ? 'Δεν είναι δυνατή η προβολή της πρόσκλησης.'
                            : 'This invitation cannot be opened.',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _greek
                            ? 'Συνδέσου με το email στο οποίο στάλθηκε ο σύνδεσμος. Αν δεν έχεις λογαριασμό, δημιούργησε έναν με αυτό το email.'
                            : 'Sign in with the email this invitation was sent to. If you do not have an account, create one using that email.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => _db.auth.signOut(),
                        icon: const Icon(Icons.logout_outlined),
                        label: Text(_greek ? 'Αλλαγή λογαριασμού' : 'Switch account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        final offer = snapshot.data!;
        final alreadyAccepted = offer['status'] == 'accepted' || _accepted;
        final rent = offer['monthly_rent'] ?? '';
        final currency = offer['currency'] ?? 'EUR';
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.description_outlined, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _greek ? 'Στοιχεία συμφωνίας' : 'Agreement details',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _item(_greek ? 'Ακίνητο / διεύθυνση' : 'Property / address',
                            '${offer['property_name'] ?? ''} · ${offer['property_address'] ?? ''}',
                            icon: Icons.home_outlined),
                        _item(_greek ? 'Διαμέρισμα' : 'Apartment', offer['unit_reference']),
                        _item(_greek ? 'Ιδιοκτήτης' : 'Owner',
                            '${offer['owner_name']} · ${offer['owner_email']}'),
                        _item(_greek ? 'Έγγραφο ταυτοποίησης ιδιοκτήτη' : 'Owner identity document',
                            '${offer['owner_id_type']} · ${offer['owner_id_country'] ?? '—'} · ${offer['owner_id_number']} · ${_greek ? 'λήγει' : 'expires'} ${_date(offer['owner_id_expiry_date'])}'),
                        _item(_greek ? 'Ενοικιαστής' : 'Tenant',
                            '${offer['tenant_name']} · ${offer['tenant_email']}'),
                        _item(_greek ? 'Μηνιαίο ενοίκιο' : 'Monthly rent', '$rent $currency',
                            icon: Icons.euro),
                        _item(_greek ? 'Εγγύηση' : 'Deposit',
                            '${offer['deposit_amount']} $currency'),
                        _item(_greek ? 'Κοινόχρηστα' : 'Common charges',
                            '${offer['common_charges']} $currency / ${_greek ? 'μήνα' : 'month'}'),
                        _item(_greek ? 'Διάρκεια' : 'Lease term',
                            '${_date(offer['start_date'])} – ${_date(offer['end_date'])}'),
                        _item(_greek ? 'Ημέρα πληρωμής ενοικίου' : 'Rent due day',
                            offer['rent_due_day']),
                        _item(_greek ? 'Έπιπλα και απογραφή' : 'Furniture and inventory',
                            offer['furniture_and_inventory']),
                        _item(_greek ? 'Περιλαμβανόμενες υπηρεσίες' : 'Included services',
                            offer['included_services']),
                        _item(_greek ? 'Ειδικοί όροι' : 'Special terms',
                            offer['special_terms']),
                        if ((offer['guarantor_name'] ?? '').toString().isNotEmpty) ...[
                          _item(_greek ? 'Εγγυητής' : 'Guarantor', offer['guarantor_name']),
                          _item(_greek ? 'Όροι εγγύησης' : 'Guarantee terms',
                              offer['guarantor_terms']),
                        ],
                        _item(_greek ? 'Πληρωμές' : 'Payments', offer['payment_terms']),
                        const Divider(height: 28),
                        Text(
                          _greek
                              ? 'Η ηλεκτρονική αποδοχή καταγράφει το όνομα, την ώρα και την έκδοση των όρων μέσα στο SmartBlock. Δεν αποτελεί από μόνη της εγκεκριμένη ηλεκτρονική υπογραφή QES.'
                              : 'Electronic acceptance records the name, time, and terms version in SmartBlock. By itself, it is not a qualified electronic signature (QES).',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (alreadyAccepted)
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.verified_outlined),
                      title: Text(_greek ? 'Η αποδοχή καταχωρίστηκε' : 'Acceptance recorded'),
                      subtitle: Text(
                        _greek
                            ? 'Η μίσθωση συνδέθηκε με τον λογαριασμό σου. Η έγκριση του ρόλου ενοικιαστή από τον διαχειριστή μπορεί να εκκρεμεί.'
                            : 'The rental is linked to your account. Administrator approval of your tenant role may still be pending.',
                      ),
                      trailing: TextButton(
                        onPressed: () => Navigator.of(context).pushAndRemoveUntil<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const SmartBlockDashboard(),
                          ),
                          (route) => false,
                        ),
                        child: Text(_greek ? 'Συνέχεια' : 'Continue'),
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greek ? 'Τα στοιχεία σου και αποδοχή' : 'Your details and acceptance',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _name,
                            decoration: InputDecoration(
                              labelText: _greek ? 'Ονοματεπώνυμο όπως στην ταυτότητα' : 'Full legal name',
                              prefixIcon: const Icon(Icons.person_outline),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _idTypeValue,
                            decoration: InputDecoration(labelText: _greek ? 'Ταυτότητα ή διαβατήριο' : 'National ID or passport'),
                            items: [
                              DropdownMenuItem(value: 'national_id', child: Text(_greek ? 'Ταυτότητα' : 'National ID')),
                              DropdownMenuItem(value: 'passport', child: Text(_greek ? 'Διαβατήριο' : 'Passport')),
                            ],
                            onChanged: (value) => setState(() => _idTypeValue = value ?? 'national_id'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _idCountry,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: _greek
                                  ? 'Χώρα έκδοσης ${_idTypeValue == 'passport' ? 'διαβατηρίου' : 'ταυτότητας'} *'
                                  : 'Country that issued the ${_idTypeValue == 'passport' ? 'passport' : 'ID'} *',
                              hintText: _greek ? 'π.χ. Κύπρος' : 'e.g. Cyprus',
                              helperText: _greek
                                  ? 'Η χώρα που εξέδωσε το έγγραφο, όχι η χώρα κατοικίας.'
                                  : 'The issuing country, not your country of residence.',
                              prefixIcon: const Icon(Icons.public_outlined),
                              filled: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _idNumber,
                            decoration: InputDecoration(
                              labelText: _greek ? 'Αριθμός ταυτότητας / διαβατηρίου *' : 'ID or passport number *',
                              prefixIcon: const Icon(Icons.credit_card_outlined),
                              filled: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _idExpiry,
                            readOnly: true,
                            onTap: _chooseExpiryDate,
                            decoration: InputDecoration(
                              labelText: _greek ? 'Ημερομηνία λήξης εγγράφου *' : 'Document expiry date *',
                              hintText: 'YYYY-MM-DD',
                              helperText: _greek ? 'Το έγγραφο πρέπει να ισχύει κατά την ημερομηνία υπογραφής.' : 'The document must be valid on the signing date.',
                              prefixIcon: const Icon(Icons.event_busy_outlined),
                              filled: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _confirmed,
                            onChanged: (value) => setState(() => _confirmed = value == true),
                            title: Text(
                              _greek
                                  ? 'Διάβασα τους όρους και αποδέχομαι ηλεκτρονικά τη συγκεκριμένη έκδοση της πρότασης.'
                                  : 'I have read the terms and electronically accept this version of the offer.',
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _confirmed && !_saving ? _accept : null,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.draw_outlined),
                              label: Text(_greek ? 'Αποδοχή μίσθωσης' : 'Accept rental agreement'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
