import 'package:flutter/material.dart';

class SampleLeasePreviewScreen extends StatelessWidget {
  const SampleLeasePreviewScreen({required this.isGreek, super.key});
  final bool isGreek;
  String t(String el, String en) => isGreek ? el : en;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('Δείγμα μισθωτηρίου', 'Lease agreement sample'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(color: theme.colorScheme.tertiaryContainer, child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(t('Ενδεικτικό - όχι πραγματικό συμβόλαιο', 'Sample - not a real contract')),
          subtitle: Text(t('Όλα τα στοιχεία είναι φανταστικά. Οι υπογραφές στο δείγμα εκκρεμούν.', 'All details are fictional. Sample signatures are pending.')),
        )),
        _section(context, t('Ακίνητο και διαμέρισμα', 'Property and apartment'), Icons.apartment_outlined, [
          _detail(t('Πολυκατοικία', 'Building'), t('Πολυκατοικία Ακτή 12 (δείγμα)', 'Akti 12 Building (sample)')),
          _detail(t('Διεύθυνση', 'Address'), t('Οδός Δείγματος 12, 8010 Πάφος, Κύπρος', '12 Sample Street, 8010 Paphos, Cyprus')),
          _detail(t('Αριθμός διαμερίσματος', 'Apartment number'), '12'),
          _detail(t('Χαρακτηριστικά', 'Details'), t('2 υπνοδωμάτια · 84 m² · επιπλωμένο', '2 bedrooms · 84 m² · furnished')),
        ]),
        _section(context, t('Συμβαλλόμενοι', 'Parties'), Icons.people_outline, [
          _detail(t('Ιδιοκτήτης', 'Owner'), t('Νίκος Δοκιμαστικός', 'Alex Sample')),
          _detail(t('Έγγραφο ιδιοκτήτη', 'Owner document'), 'DEMO-ID-OWNER-001 · ' + t('Κύπρος · λήξη 30/04/2031', 'Cyprus · expires 30/04/2031')),
          _detail('Email / ' + t('τηλέφωνο', 'phone'), 'owner@example.invalid · +357 00 000 001'),
          const Divider(),
          _detail(t('Ενοικιάστρια', 'Tenant'), t('Ελένη Δοκιμαστική', 'Maria Sample')),
          _detail(t('Έγγραφο ενοικιάστριας', 'Tenant document'), 'DEMO-ID-TENANT-001 · ' + t('Κύπρος · λήξη 30/09/2030', 'Cyprus · expires 30/09/2030')),
          _detail('Email / ' + t('τηλέφωνο', 'phone'), 'tenant@example.invalid · +357 00 000 002'),
        ]),
        _section(context, t('Διάρκεια και οικονομικοί όροι', 'Term and financial terms'), Icons.payments_outlined, [
          _detail(t('Διάρκεια', 'Term'), '01/12/2026 – 30/11/2027'),
          _detail(t('Μηνιαίο ενοίκιο', 'Monthly rent'), '€850,00 · ' + t('πληρωτέο την 1η κάθε μήνα', 'due on the 1st of each month')),
          _detail(t('Εγγύηση', 'Deposit'), '€850,00'),
          _detail(t('Κοινόχρηστα', 'Common charges'), '€60,00 / ' + t('μήνα', 'month')),
          _detail(t('Λογαριασμοί', 'Utilities'), t('Με βάση τις πραγματικές χρεώσεις.', 'Based on actual bills.')),
        ]),
        _section(context, t('Έπιπλα και απογραφή', 'Furniture and inventory'), Icons.chair_outlined, [
          _detail(t('Καθιστικό', 'Living room'), t('Καναπές, τραπεζάκι, σύνθετο τηλεόρασης, φωτιστικό.', 'Sofa, coffee table, TV stand, floor lamp.')),
          _detail(t('Κουζίνα', 'Kitchen'), t('Ψυγείο, φούρνος, εστίες, απορροφητήρας, τραπέζι και 4 καρέκλες.', 'Fridge, oven, hob, extractor, table and 4 chairs.')),
          _detail(t('Υπνοδωμάτιο 1', 'Bedroom 1'), t('Διπλό κρεβάτι, στρώμα, ντουλάπα και κομοδίνα.', 'Double bed, mattress, wardrobe and bedside tables.')),
          _detail(t('Υπνοδωμάτιο 2', 'Bedroom 2'), t('Μονό κρεβάτι, γραφείο, καρέκλα και ντουλάπα.', 'Single bed, desk, chair and wardrobe.')),
          _detail(t('Λοιπά', 'Other'), t('Πλυντήριο, κουρτίνες και φωτιστικά.', 'Washer, curtains and lights.')),
        ]),
        _section(context, t('Όροι συμφωνίας', 'Agreement terms'), Icons.gavel_outlined, [
          _clause('1', t('Χρήση κατοικίας', 'Residential use'), t('Το διαμέρισμα χρησιμοποιείται ως κατοικία. Υπεκμίσθωση ή αλλαγή χρήσης απαιτεί προηγούμενη γραπτή συναίνεση.', 'The apartment is for residential use. Subletting or a change of use requires prior written consent.')),
          _clause('2', t('Συντήρηση και βλάβες', 'Maintenance and defects'), t('Η ενοικιάστρια αναφέρει έγκαιρα βλάβες στο SmartBlock. Οι ζημιές τεκμηριώνονται με περιγραφή και, όπου χρειάζεται, φωτογραφίες.', 'The tenant reports defects promptly in SmartBlock. Damage is documented with descriptions and, where appropriate, photos.')),
          _clause('3', t('Πρόσβαση', 'Access'), t('Για επιθεώρηση ή επισκευή γίνεται εύλογη προηγούμενη συνεννόηση, εκτός επείγουσας περίπτωσης.', 'Reasonable advance notice is arranged for inspection or repairs, except in emergencies.')),
          _clause('4', t('Κανονισμός πολυκατοικίας', 'Building rules'), t('Η ενοικιάστρια τηρεί τον κανονισμό και σέβεται τους κοινόχρηστους χώρους.', 'The tenant follows building rules and respects shared areas.')),
          _clause('5', t('Επιστροφή εγγύησης', 'Deposit return'), t('Κατά την αποχώρηση ελέγχονται η κατάσταση του διαμερίσματος και οι οφειλές. Κάθε κράτηση αιτιολογείται αναλυτικά.', 'At move-out, the apartment condition and outstanding amounts are reviewed. Any deduction is itemized.')),
          _clause('6', t('Ανανέωση ή πρόωρη λήξη', 'Renewal or early termination'), t('Το αίτημα καταχωρίζεται στο SmartBlock. Η υποβολή δεν αποτελεί αποδοχή· χρειάζεται συμφωνία και των δύο μερών.', 'The request is recorded in SmartBlock. Submission is not acceptance; both parties must agree.')),
        ]),
        _section(context, t('Ψηφιακή διαχείριση SmartBlock', 'SmartBlock digital management'), Icons.account_balance_wallet_outlined, [
          Text(t('Τα μέρη χρησιμοποιούν το SmartBlock για κοινοποιήσεις και καταχώριση πληρωμών της μίσθωσης. Το SmartBlock δεν γίνεται συμβαλλόμενο μέρος και δεν αντικαθιστά τις υποχρεώσεις των μερών.', 'The parties use SmartBlock for notices and recording lease payments. SmartBlock is not a party and does not replace their obligations.')),
          const SizedBox(height: 10),
          Text(t('Η εφαρμογή καταγράφει λογαριασμό, ημερομηνία και ώρα αποδοχής και την έκδοση των όρων. Η τρέχουσα αποδοχή δεν αποτελεί πιστοποιημένη ηλεκτρονική υπογραφή.', 'The app records the account, acceptance date and time, and terms version. Current acceptance is not a certified electronic signature.')),
        ]),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          Expanded(child: _signature(t('Ιδιοκτήτης', 'Owner'), t('Νίκος Δοκιμαστικός', 'Alex Sample'))),
          const SizedBox(width: 12),
          Expanded(child: _signature(t('Ενοικιάστρια', 'Tenant'), t('Ελένη Δοκιμαστική', 'Maria Sample'))),
        ]))),
        Padding(padding: const EdgeInsets.all(8), child: Text(
          t('Δείγμα προβολής. Πριν από πραγματική χρήση, συμπληρώνονται και ελέγχονται τα στοιχεία και οι όροι της συγκεκριμένης μίσθωσης.',
            'Viewing sample. Before real use, complete and review the details and terms for the specific lease.'),
          textAlign: TextAlign.center, style: theme.textTheme.bodySmall,
        )),
      ]),
    );
  }

  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 10), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium))]),
        const Divider(height: 22),
        ...children,
      ]),
    ),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 150, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      const SizedBox(width: 8),
      Expanded(child: SelectableText(value)),
    ]),
  );

  Widget _clause(String number, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(number + '. ' + title, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(body),
    ]),
  );

  Widget _signature(String role, String name) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Text(role, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 14),
      Text(name, textAlign: TextAlign.center),
      const SizedBox(height: 10),
      Text(t('Υπογραφή: εκκρεμεί', 'Signature: pending'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
      Text(t('Ημερομηνία: —', 'Date: —'), style: const TextStyle(fontSize: 12)),
    ]),
  );
}
