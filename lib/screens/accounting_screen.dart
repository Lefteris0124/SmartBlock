import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_language.dart';
import '../smartblock_text.dart';

class AccountingScreen extends StatefulWidget {
  const AccountingScreen({super.key});
  @override
  State<AccountingScreen> createState()=>_AccountingScreenState();
}
class _AccountingScreenState extends State<AccountingScreen>{
  final db=Supabase.instance.client;
  bool greek=true,loading=true,busy=false,admin=false;
  String? error;
  Map<String,dynamic> summary={};
  Map<String,dynamic> tenantFinancialSummary={};
  List<Map<String,dynamic>> statements=[];
  List<Map<String,dynamic>> customerStatements=[];
  List<Map<String,dynamic>> receipts=[];
  List<Map<String,dynamic>> journals=[];
  List<Map<String,dynamic>> ownerFinancialRows=[];
  String ownerPropertyFilter='all';
  String ownerPeriodFilter='current';
  int year=DateTime.now().year;
  @override
  void initState(){super.initState();greek=SmartBlockLanguageController.instance.selected.value.isGreek;refresh();}
  Future<void> refresh() async{
    setState(()=>loading=true);
    try{
      admin=await db.rpc('is_smartblock_admin')==true;
      if(admin){
        summary=Map<String,dynamic>.from(await db.rpc('admin_accounting_dashboard') as Map);
        receipts=List<Map<String,dynamic>>.from(await db.from('accounting_receipts').select('receipt_number,description,amount,currency,payment_method,issued_at,payment_reference,details').order('issued_at',ascending:false).limit(25));
        journals=List<Map<String,dynamic>>.from(await db.from('accounting_journal_entries').select('posting_date,source_type,description,accounting_journal_lines(account_code,debit,credit,description)').order('posting_date',ascending:false).limit(25));
        final previous=DateTime(DateTime.now().year,DateTime.now().month-1,1);
        customerStatements=List<Map<String,dynamic>>.from(await db.rpc('admin_list_accounting_customer_statements',params:{'p_month':date(previous)}) as List);
      }
      else {
        tenantFinancialSummary=Map<String,dynamic>.from(await db.rpc('my_tenant_financial_summary') as Map);
        statements=List<Map<String,dynamic>>.from(await db.rpc('my_accounting_customer_statements') as List);
        final selectedYear = ownerPeriodFilter == 'all'
            ? null
            : (ownerPeriodFilter == 'current'
                ? DateTime.now().year
                : int.tryParse(ownerPeriodFilter));
        ownerFinancialRows=List<Map<String,dynamic>>.from(
          await db.rpc('my_owner_property_financial_summary',params:{
            'p_property_id':null,
            'p_from':selectedYear==null?null:date(DateTime(selectedYear,1,1)),
            'p_to':selectedYear==null?null:date(DateTime(selectedYear,12,31)),
          }) as List,
        );
        if(ownerPropertyFilter!='all' &&
            !ownerFinancialRows.any((r)=>r['property_id'].toString()==ownerPropertyFilter)){
          ownerPropertyFilter='all';
        }
      }
      error=null;
    }catch(e){error=e.toString();}
    finally{if(mounted)setState(()=>loading=false);}
  }
  String money(dynamic v)=>'€'+((v is num?v.toDouble():double.tryParse('$v')??0).toStringAsFixed(2));
  String date(DateTime d)=>d.year.toString().padLeft(4,'0')+'-'+d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');
  String csv(List rows){
    final items=rows.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
    if(items.isEmpty)return 'No records\\n';
    final keys=<String>[];for(final m in items){for(final k in m.keys){if(!keys.contains(k))keys.add(k);}}
    String c(dynamic v){final s=v is Map||v is List?jsonEncode(v):(v?.toString()??'');return '"'+s.replaceAll('"','""')+'"';}
    return keys.map(c).join(',')+'\\n'+items.map((m)=>keys.map((k)=>c(m[k])).join(',')).join('\\n')+'\\n';
  }
  void message(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Future<void> export() async{
    setState(()=>busy=true);
    try{
      final data=Map<String,dynamic>.from(await db.rpc('admin_accounting_export',params:{'p_from':date(DateTime(year,1,1)),'p_to':date(DateTime(year,12,31))}) as Map);
      final archive=Archive();
      void add(String name,String text){final b=utf8.encode(text);archive.addFile(ArchiveFile(name,b.length,b));}
      add('manifest.json',const JsonEncoder.withIndent('  ').convert(data));
      for(final e in data.entries){if(e.value is List)add(e.key+'.csv',csv(e.value as List));}
      final bytes=ZipEncoder().encode(archive);if(bytes==null)throw StateError('ZIP failed.');
      await FileSaver.instance.saveFile(name:'SmartBlock-audit-'+year.toString(),bytes:Uint8List.fromList(bytes),fileExtension:'zip',mimeType:MimeType.other);
      message(greek?'Το αρχείο ελέγχου κατέβηκε.':'Audit archive downloaded.');
    }catch(e){message(e.toString());}finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> makeStatements()async{
    setState(()=>busy=true);
    try{
      final d=DateTime(DateTime.now().year,DateTime.now().month-1,1);
      final n=await db.rpc('admin_generate_monthly_accounting_statements',params:{'p_month':date(d)});
      await refresh();message(greek?'Δημιουργήθηκαν/ενημερώθηκαν '+n.toString()+' καταστάσεις.':'Generated/refreshed '+n.toString()+' statements.');
    }catch(e){message(e.toString());}finally{if(mounted)setState(()=>busy=false);}
  }
  Widget metric(String title,dynamic val,IconData icon)=>Card(child:ListTile(leading:CircleAvatar(child:Icon(icon)),title:Text(title),subtitle:Text(money(val),style:Theme.of(context).textTheme.titleLarge)));
  Widget adminView(){
    final rows=List<Map<String,dynamic>>.from((summary['payout_queue'] as List?)??const []);
    return ListView(padding:const EdgeInsets.all(16),children:[
      Text(greek?'Λογιστική SmartBlock':'SmartBlock accounting',style:Theme.of(context).textTheme.headlineSmall),
      Text(greek?'Οι αποδείξεις και οι εγγραφές δημιουργούνται από επιβεβαιωμένες εισπράξεις Stripe.':'Receipts and entries come from confirmed Stripe payments.'),
      metric(greek?'Επιβεβαιωμένες εισπράξεις':'Confirmed collections',summary['collected'],Icons.payments_outlined),
      metric(greek?'Προμήθειες SmartBlock':'SmartBlock fees',summary['smartblock_fees'],Icons.account_balance_wallet_outlined),
      metric(greek?'Προς απόδοση':'Due to owners',summary['owner_payout_due'],Icons.outbox_outlined),
      metric(greek?'Αναμονή σύνδεσης Stripe':'Awaiting Stripe connection',summary['awaiting_connect'],Icons.link_off_outlined),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(greek?'Πρόσφατες αποδείξεις':'Recent receipts',style:Theme.of(context).textTheme.titleMedium),
        if(receipts.isEmpty)Text(greek?'Δεν έχουν εκδοθεί ακόμη αποδείξεις.':'No receipts have been issued yet.'),
        ...receipts.map((r)=>ListTile(leading:const Icon(Icons.receipt_long_outlined),title:Text((r['receipt_number']??'').toString()),subtitle:Text((r['description']??'').toString()+' · '+(r['issued_at']??'').toString()),trailing:Text(money(r['amount'])))),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(greek?'Πρόσφατες λογιστικές εγγραφές':'Recent journal entries',style:Theme.of(context).textTheme.titleMedium),
        if(journals.isEmpty)Text(greek?'Δεν έχουν καταχωριστεί ακόμη εγγραφές.':'No journal entries yet.'),
        ...journals.map((j)=>ExpansionTile(title:Text((j['description']??'').toString()),subtitle:Text((j['posting_date']??'').toString()+' · '+(j['source_type']??'').toString()),children:[for(final l in (j['accounting_journal_lines'] as List? ?? const []))ListTile(title:Text((l['account_code']??'').toString()),subtitle:Text((l['description']??'').toString()),trailing:Text((greek?'Χρέωση ':'Debit ')+money(l['debit'])+' · '+(greek?'Πίστωση ':'Credit ')+money(l['credit'])))])),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        Text(greek?'Ουρά αποδόσεων ιδιοκτητών':'Owner payout queue',style:Theme.of(context).textTheme.titleMedium),
        if(rows.isEmpty)Text(greek?'Δεν υπάρχουν ακόμη εισπράξεις προς απόδοση.':'No owner payouts yet.'),
        ...rows.map((r)=>ListTile(leading:const Icon(Icons.home_work_outlined),title:Text((r['owner_name']??'').toString()),subtitle:Text((r['property_name']??'').toString()+' · '+(greek?'Αναμονή Stripe Connect':'Awaiting Stripe Connect')),trailing:Text(money(r['amount_due'])))),
        Text(greek?'Οι πραγματικές μεταφορές απαιτούν συνδεδεμένους λογαριασμούς Stripe Connect.':'Transfers require owners to connect Stripe accounts.'),
      ]))),
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(greek?'Μηνιαίες καταστάσεις ανά πελάτη':'Monthly statements by customer',style:Theme.of(context).textTheme.titleMedium),
        if(customerStatements.isEmpty) Text(greek?'Δεν υπάρχουν ακόμη καταστάσεις για τον προηγούμενο μήνα.':'No statements have been generated for the previous month yet.'),
        ...customerStatements.map(customerStatementRow),
      ]))),
      DropdownButtonFormField<int>(value:year,decoration:InputDecoration(labelText:greek?'Έτος αρχείου ελέγχου':'Audit year'),items:List.generate(8,(i)=>DateTime.now().year-i).map((y)=>DropdownMenuItem(value:y,child:Text(y.toString()))).toList(),onChanged:busy?null:(v){if(v!=null)setState(()=>year=v);}),
      FilledButton.icon(onPressed:busy?null:export,icon:const Icon(Icons.archive_outlined),label:Text(greek?'Λήψη αρχείου ελέγχου ZIP':'Download audit ZIP')),
      OutlinedButton.icon(onPressed:busy?null:makeStatements,icon:const Icon(Icons.mark_email_read_outlined),label:Text(greek?'Δημιουργία μηνιαίων καταστάσεων':'Generate monthly statements')),
      Text(greek?'Οι καταστάσεις δημιουργούνται αυτόματα την 1η κάθε μήνα και εμφανίζονται στους λογαριασμούς. Email απαιτεί ρυθμισμένο πάροχο.':'Statements are generated automatically on the 1st and appear in accounts. Email requires an email provider.'),
    ]);
  }
  List<Widget> statementDetails(Map<String,dynamic> data){
    final properties=(data['properties'] as List? ?? const []).whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList();
    final buildings=(data['buildings'] as List? ?? const []).whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList();
    return [
      for(final p in properties)
        Builder(builder:(context){
          final debts=(p['debts'] as List? ?? const []).whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList();
          final receipts=(p['receipts'] as List? ?? const []).whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList();
          final payouts=(p['owner_payouts'] as List? ?? const []).whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList();
          return Card(child:ExpansionTile(
            leading:const Icon(Icons.home_work_outlined),
            title:Text((p['name']??(greek?'Ακίνητο':'Property')).toString()+' · #'+(p['reference']??'').toString()),
            subtitle:Text((p['address']??'').toString()),
            children:[
              if(debts.isEmpty) ListTile(title:Text(greek?'Δεν υπάρχουν οφειλές καταχωρισμένες για αυτό το ακίνητο.':'No recorded debts for this property.')),
              for(final d in debts) ListTile(
                leading:Icon(d['direction']=='owed_to_owner'?Icons.call_received_outlined:Icons.call_made_outlined),
                title:Text((d['source']??'').toString()+(d['unit_number']==null?'':' · '+(greek?'Μονάδα ':'Unit ')+d['unit_number'].toString())),
                subtitle:Text((d['description']??'').toString()+' · '+(greek?'Περίοδος ':'Period ')+(d['period']??'').toString()+' · '+(greek?'Λήξη ':'Due ')+(d['due_date']??'').toString()+' · '+(d['direction']=='owed_to_owner'?(greek?'Οφείλεται σε εσένα':'Due to you'):(greek?'Οφείλεις':'You owe'))+(d['source_type']=='property_charge' && (d['area_sqm']!=null || d['owner_apartment_count']!=null)?' · '+(greek?'Ιδιοκτησία: ':'Ownership: ')+(d['owner_apartment_count']==null?'':(greek?'διαμερίσματα ':'apartments ')+d['owner_apartment_count'].toString())+(d['owner_apartment_count']!=null && d['area_sqm']!=null?' · ':'')+(d['area_sqm']==null?'':d['area_sqm'].toString()+' m²'):'') ),
                trailing:Text(money(d['balance'])),
              ),
              for(final r in receipts) ListTile(leading:const Icon(Icons.receipt_outlined),title:Text((r['receipt_number']??r['description']??'').toString()),subtitle:Text((r['date']??'').toString()),trailing:Text(money(r['amount']))),
              if((p['smartblock_fee_withheld'] as num? ?? 0)>0) ListTile(leading:const Icon(Icons.percent),title:Text(greek?'Προμήθεια SmartBlock που παρακρατήθηκε':'SmartBlock fee withheld'),trailing:Text(money(p['smartblock_fee_withheld']))),
              for(final q in payouts) ListTile(leading:const Icon(Icons.outbox_outlined),title:Text(greek?'Προς απόδοση ιδιοκτήτη':'Owner payout due'),subtitle:Text((q['status']??'').toString()),trailing:Text(money(q['amount_due']))),
            ],
          ));
        }),
      for(final b in buildings)
        Builder(builder:(context){
          final debts=(b['debts'] as List? ?? const []).whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList();
          final receipts=(b['receipts'] as List? ?? const []).whereType<Map>().map((v)=>Map<String,dynamic>.from(v)).toList();
          return Card(child:ExpansionTile(
            leading:const Icon(Icons.apartment_outlined),
            title:Text((b['building_name']??'').toString()+' · '+(greek?'Διαμέρισμα ':'Unit ')+(b['apartment_number']??'').toString()),
            subtitle:Text((b['address']??'').toString()),
            children:[
              if(debts.isEmpty) ListTile(title:Text(greek?'Δεν υπάρχουν οφειλές καταχωρισμένες.':'No recorded debts.')),
              for(final d in debts) ListTile(
                leading:const Icon(Icons.receipt_long_outlined),
                title:Text((d['source']??'').toString()+' · '+(d['description']??'').toString()),
                subtitle:Text((greek?'Περίοδος ':'Period ')+(d['period']??'').toString()+' · '+(greek?'Λήξη ':'Due ')+(d['due_date']??'').toString()+' · '+(greek?'Οφείλεις':'You owe')),
                trailing:Text(money(d['balance'])),
              ),
              for(final r in receipts) ListTile(leading:const Icon(Icons.receipt_outlined),title:Text((r['receipt_number']??r['description']??'').toString()),subtitle:Text((r['date']??'').toString()),trailing:Text(money(r['amount']))),
            ],
          ));
        }),
    ];
  }
  Widget customerStatementRow(Map<String,dynamic> s){
    final data=Map<String,dynamic>.from((s['statement_data'] as Map?)??const {});
    return Card(child:ExpansionTile(
      leading:const Icon(Icons.person_outline),
      title:Text((s['full_name']??'').toString().isEmpty?(s['email']??'').toString():(s['full_name']??'').toString()),
      subtitle:Text((s['email']??'').toString()+' · '+(s['statement_month']??'').toString()+' · '+(greek?'Οφειλή: ':'Owes: ')+money(s['total_you_owe'])),
      children:[
        ListTile(title:Text(greek?'Οφειλές πελάτη':'Customer amount due'),trailing:Text(money(s['total_you_owe']))),
        ListTile(title:Text(greek?'Ενοίκια προς είσπραξη':'Rent receivable'),trailing:Text(money(s['rent_owed_to_you']))),
        ListTile(title:Text(greek?'Προς απόδοση':'Owner payouts due'),trailing:Text(money(s['owner_payout_due']))),
        ...statementDetails(data),
      ],
    ));
  }
  Widget _ownerFinanceMetric(String label,dynamic value,IconData icon)=>SizedBox(
    width:150,
    child:Card(
      color:Theme.of(context).colorScheme.surfaceContainerHighest,
      child:Padding(
        padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Icon(icon,color:Theme.of(context).colorScheme.primary),
          const SizedBox(height:8),
          Text(label,style:Theme.of(context).textTheme.bodySmall),
          const SizedBox(height:4),
          Text(money(value),style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700)),
        ]),
      ),
    ),
  );

  Widget ownerFinancialOverview(){
    if(ownerFinancialRows.isEmpty){
      return Card(child:Padding(
        padding:const EdgeInsets.all(16),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(greek?'Οικονομική εικόνα ιδιοκτητών':'Owner financial overview',
            style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:8),
          Text(greek
            ?'Δεν υπάρχουν ακόμη οικονομικά στοιχεία για ακίνητα συνδεδεμένα με τον λογαριασμό σου.'
            :'There are no financial records yet for properties linked to your owner account.'),
        ]),
      ));
    }
    final visible=ownerPropertyFilter=='all'
        ? ownerFinancialRows
        : ownerFinancialRows.where((r)=>r['property_id'].toString()==ownerPropertyFilter).toList();
    double total(String key)=>visible.fold<double>(0,(sum,row)=>sum+((row[key] as num?)?.toDouble()??0));
    final propertyItems=<DropdownMenuItem<String>>[
      DropdownMenuItem(value:'all',child:Text(greek?'Όλα τα ακίνητα':'All properties')),
      ...ownerFinancialRows.map((row)=>DropdownMenuItem(
        value:row['property_id'].toString(),
        child:Text((row['property_name']??(greek?'Ακίνητο':'Property')).toString(),
          overflow:TextOverflow.ellipsis),
      )),
    ];
    final periodItems=<DropdownMenuItem<String>>[
      DropdownMenuItem(value:'current',child:Text(greek?'Τρέχον έτος':'Current year')),
      DropdownMenuItem(value:'all',child:Text(greek?'Όλη η περίοδος':'All time')),
      for(var y=DateTime.now().year-1;y>=DateTime.now().year-5;y--)
        DropdownMenuItem(value:'$y',child:Text('$y')),
    ];
    return Card(
      child:Padding(
        padding:const EdgeInsets.all(16),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(greek?'Αναλυτικά οικονομικά ακινήτων':'Property financial breakdown',
            style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:6),
          Text(greek
            ?'Τα ποσά υπολογίζονται με βάση το ποσοστό ιδιοκτησίας σου. Τα έξοδα δείχνουν εγκεκριμένες και πληρωμένες καταχωρίσεις.'
            :'Amounts are allocated using your ownership share. Expenses reflect approved and paid records.'),
          const SizedBox(height:12),
          Wrap(spacing:12,runSpacing:8,children:[
            SizedBox(width:260,child:DropdownButtonFormField<String>(
              value:ownerPropertyFilter,
              decoration:InputDecoration(
                labelText:greek?'Φίλτρο ακινήτου':'Property filter',
                prefixIcon:const Icon(Icons.home_work_outlined),
              ),
              items:propertyItems,
              onChanged:(value){
                if(value==null)return;
                setState(()=>ownerPropertyFilter=value);
              },
            )),
            SizedBox(width:220,child:DropdownButtonFormField<String>(
              value:ownerPeriodFilter,
              decoration:InputDecoration(
                labelText:greek?'Περίοδος':'Period',
                prefixIcon:const Icon(Icons.calendar_month_outlined),
              ),
              items:periodItems,
              onChanged:(value){
                if(value==null)return;
                setState(()=>ownerPeriodFilter=value);
                refresh();
              },
            )),
          ]),
          const SizedBox(height:12),
          if(visible.isNotEmpty) Wrap(spacing:4,runSpacing:4,children:[
            _ownerFinanceMetric(greek?'Ενοίκια εισπραχθέντα':'Rent collected',total('rent_collected_gross'),Icons.payments_outlined),
            _ownerFinanceMetric(greek?'Προμήθεια SmartBlock':'SmartBlock fees',total('smartblock_fee'),Icons.percent),
            _ownerFinanceMetric(greek?'Καθαρά ενοίκια':'Net rent',total('rent_net_to_property'),Icons.account_balance_wallet_outlined),
            _ownerFinanceMetric(greek?'Βλάβες / επισκευές':'Repairs',total('repairs_paid'),Icons.build_outlined),
            _ownerFinanceMetric(greek?'Συντηρήσεις':'Maintenance',total('maintenance_paid'),Icons.handyman_outlined),
            _ownerFinanceMetric(greek?'Άλλα έξοδα':'Other expenses',total('other_expenses_paid'),Icons.receipt_long_outlined),
            _ownerFinanceMetric(greek?'Σύνολο πληρωμένων εξόδων':'Total paid expenses',total('total_expenses_paid'),Icons.money_off_outlined),
            _ownerFinanceMetric(greek?'Καθαρό μετά τα έξοδα':'Net after expenses',total('rent_net_to_property')-total('total_expenses_paid'),Icons.savings_outlined),
            _ownerFinanceMetric(greek?'Έξοδα εγκεκριμένα σε αναμονή':'Approved expenses pending',total('approved_expenses_pending'),Icons.pending_actions_outlined),
            _ownerFinanceMetric(greek?'Αποδόσεις ολοκληρωμένες':'Payouts paid',total('owner_payout_paid'),Icons.check_circle_outline),
            _ownerFinanceMetric(greek?'Αποδόσεις σε αναμονή':'Payouts pending',total('owner_payout_pending'),Icons.outbox_outlined),
          ]),
          const SizedBox(height:8),
          ...visible.map((row){
            final property=(row['property_name']??(greek?'Ακίνητο':'Property')).toString();
            final address=(row['property_address']??'').toString();
            return ExpansionTile(
              leading:const Icon(Icons.apartment_outlined),
              title:Text(property),
              subtitle:Text([
                if(address.isNotEmpty)address,
                '${greek?'Μερίδιο':'Share'}: ${((row['ownership_percent'] as num?)?.toDouble()??0).toStringAsFixed(2)}%',
                '${greek?'Ενοίκια':'Rent'}: ${money(row['rent_collected_gross'])}',
              ].join(' · ')),
              children:[
                for(final item in <(String,String)>[
                  (greek?'Ενοίκια που εισπράχθηκαν':'Gross rent collected','rent_collected_gross'),
                  (greek?'Προμήθεια SmartBlock':'SmartBlock fee','smartblock_fee'),
                  (greek?'Καθαρό μερίδιο ενοικίων':'Net rent share','rent_net_to_property'),
                  (greek?'Βλάβες και επισκευές που πληρώθηκαν':'Repairs paid','repairs_paid'),
                  (greek?'Συντηρήσεις που πληρώθηκαν':'Maintenance paid','maintenance_paid'),
                  (greek?'Άλλα έξοδα που πληρώθηκαν':'Other expenses paid','other_expenses_paid'),
                  (greek?'Σύνολο πληρωμένων εξόδων':'Total paid expenses','total_expenses_paid'),
                  (greek?'Εγκεκριμένα έξοδα σε αναμονή πληρωμής':'Approved expenses pending','approved_expenses_pending'),
                  (greek?'Ποσά που αποδόθηκαν':'Payouts paid','owner_payout_paid'),
                  (greek?'Ποσά προς απόδοση':'Payouts pending','owner_payout_pending'),
                ])
                  ListTile(title:Text(item.$1),trailing:Text(money(row[item.$2]))),
              ],
            );
          }),
        ]),
      ),
    );
  }

  Widget tenantFinancialOverview(){
    dynamic value(String key)=>tenantFinancialSummary[key]??0;
    return Card(
      child:Padding(
        padding:const EdgeInsets.all(16),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(greek?'Οικονομική εικόνα ενοικιαστή':'Tenant financial overview',
            style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:8),
          Wrap(spacing:4,runSpacing:4,children:[
            _ownerFinanceMetric(greek?'Ενοίκια που καταβλήθηκαν':'Rent paid',value('rent_paid'),Icons.payments_outlined),
            _ownerFinanceMetric(greek?'Οφειλόμενα ενοίκια':'Rent outstanding',value('rent_due'),Icons.pending_actions_outlined),
            _ownerFinanceMetric(greek?'Κοινόχρηστα που καταβλήθηκαν':'Common charges paid',value('common_charges_paid'),Icons.receipt_long_outlined),
            _ownerFinanceMetric(greek?'Οφειλόμενα κοινόχρηστα':'Common charges outstanding',value('common_charges_due'),Icons.request_quote_outlined),
            _ownerFinanceMetric(greek?'Εγγύηση συμφωνημένη':'Agreed deposit',value('deposit_agreed'),Icons.lock_outline),
            _ownerFinanceMetric(greek?'Πληρωμές ζημιών καταχωρισμένες':'Recorded damage payments',value('damage_paid_recorded'),Icons.build_outlined),
            _ownerFinanceMetric(greek?'Οφειλές ζημιών καταχωρισμένες':'Recorded damage charges due',value('damage_due_recorded'),Icons.warning_amber_outlined),
          ]),
          const SizedBox(height:8),
          Text(greek
            ?'Η εγγύηση δείχνει το συμφωνημένο ποσό του συμβολαίου. Οι πληρωμές ζημιών εμφανίζονται όταν καταχωριστούν ως χρέωση στο σύστημα.'
            :'The deposit is the amount agreed in the contract. Damage payments appear when they are recorded as a charge in the system.',
            style:Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }

  Widget accountView()=>ListView(padding:const EdgeInsets.all(16),children:[
    Text(greek?'Λογιστικές καταστάσεις':'Account statements',style:Theme.of(context).textTheme.headlineSmall),
    Text(greek?'Μία κατάσταση ανά μήνα, συγκεντρωμένη για όλα τα ακίνητα και τις μονάδες του λογαριασμού σου.':'One statement per month, consolidated across all properties and units linked to your account.'),
    tenantFinancialOverview(),
    if(ownerFinancialRows.isNotEmpty) ownerFinancialOverview(),
    if(statements.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(20),child:Text(greek?'Δεν υπάρχει ακόμη διαθέσιμη κατάσταση.':'No statement available yet.'))),
    ...statements.map((s){
      final data=Map<String,dynamic>.from((s['statement_data'] as Map?)??const {});
      return Card(child:ExpansionTile(
        leading:const Icon(Icons.receipt_long_outlined),
        title:Text((s['statement_month']??'').toString()),
        subtitle:Text((greek?'Οφειλές: ':'You owe: ')+money(s['total_you_owe'])+' · '+(greek?'Προς είσπραξη: ':'Rent due to you: ')+money(s['rent_owed_to_you'])+' · '+(greek?'Προς απόδοση: ':'Payout due: ')+money(s['owner_payout_due'])),
        children:[
          ListTile(title:Text(greek?'Εισπράξεις περιόδου':'Collections this period'),trailing:Text(money(s['total_collected']))),
          ...statementDetails(data),
        ],
      ));
    }),
  ]);
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(greek?'Λογιστικές καταστάσεις':'Account statements'),actions:[IconButton(onPressed:loading||busy?null:refresh,icon:const Icon(Icons.refresh))]),body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Padding(padding:const EdgeInsets.all(20),child:Text(error!))):Stack(children:[admin?adminView():accountView(),if(busy)const Positioned.fill(child:ColoredBox(color:Color(0x55FFFFFF),child:Center(child:CircularProgressIndicator())))]));
}