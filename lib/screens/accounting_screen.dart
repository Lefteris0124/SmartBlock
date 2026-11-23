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
  List<Map<String,dynamic>> statements=[];
  int year=DateTime.now().year;
  @override
  void initState(){super.initState();greek=SmartBlockLanguageController.instance.selected.value.isGreek;refresh();}
  Future<void> refresh() async{
    setState(()=>loading=true);
    try{
      admin=await db.rpc('is_smartblock_admin')==true;
      if(admin)summary=Map<String,dynamic>.from(await db.rpc('admin_accounting_dashboard') as Map);
      else statements=List<Map<String,dynamic>>.from(await db.rpc('my_accounting_statements') as List);
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
      Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
        Text(greek?'Ουρά αποδόσεων ιδιοκτητών':'Owner payout queue',style:Theme.of(context).textTheme.titleMedium),
        if(rows.isEmpty)Text(greek?'Δεν υπάρχουν ακόμη εισπράξεις προς απόδοση.':'No owner payouts yet.'),
        ...rows.map((r)=>ListTile(leading:const Icon(Icons.home_work_outlined),title:Text((r['owner_name']??'').toString()),subtitle:Text((r['property_name']??'').toString()+' · '+(greek?'Αναμονή Stripe Connect':'Awaiting Stripe Connect')),trailing:Text(money(r['amount_due'])))),
        Text(greek?'Οι πραγματικές μεταφορές απαιτούν συνδεδεμένους λογαριασμούς Stripe Connect.':'Transfers require owners to connect Stripe accounts.'),
      ]))),
      DropdownButtonFormField<int>(value:year,decoration:InputDecoration(labelText:greek?'Έτος αρχείου ελέγχου':'Audit year'),items:List.generate(8,(i)=>DateTime.now().year-i).map((y)=>DropdownMenuItem(value:y,child:Text(y.toString()))).toList(),onChanged:busy?null:(v){if(v!=null)setState(()=>year=v);}),
      FilledButton.icon(onPressed:busy?null:export,icon:const Icon(Icons.archive_outlined),label:Text(greek?'Λήψη αρχείου ελέγχου ZIP':'Download audit ZIP')),
      OutlinedButton.icon(onPressed:busy?null:makeStatements,icon:const Icon(Icons.mark_email_read_outlined),label:Text(greek?'Δημιουργία μηνιαίων καταστάσεων':'Generate monthly statements')),
      Text(greek?'Οι καταστάσεις δημιουργούνται αυτόματα την 1η κάθε μήνα και εμφανίζονται στους λογαριασμούς. Email απαιτεί ρυθμισμένο πάροχο.':'Statements are generated automatically on the 1st and appear in accounts. Email requires an email provider.'),
    ]);
  }
  Widget accountView()=>ListView(padding:const EdgeInsets.all(16),children:[
    Text(greek?'Οι οικονομικές μου καταστάσεις':'My financial statements',style:Theme.of(context).textTheme.headlineSmall),
    if(statements.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(20),child:Text(greek?'Δεν υπάρχει ακόμη διαθέσιμη κατάσταση.':'No statement available yet.'))),
    ...statements.map((s){final data=Map<String,dynamic>.from((s['statement_data'] as Map?)??const {});final receipts=data['receipts'] as List? ?? const [];return Card(child:ExpansionTile(leading:const Icon(Icons.receipt_long_outlined),title:Text((s['statement_month']??'').toString()),subtitle:Text((greek?'Εισπράξεις: ':'Collections: ')+money(s['total_collected'])+' · '+(greek?'Προς απόδοση: ':'Owner due: ')+money(s['owner_payout_due'])),children:[for(final r in receipts)ListTile(title:Text((r['description']??'').toString()),subtitle:Text((r['issued_at']??'').toString()),trailing:Text(money(r['amount'])))]));}),
  ]);
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(greek?'Οικονομικά':'Accounting'),actions:[IconButton(onPressed:loading||busy?null:refresh,icon:const Icon(Icons.refresh))]),body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Padding(padding:const EdgeInsets.all(20),child:Text(error!))):Stack(children:[admin?adminView():accountView(),if(busy)const Positioned.fill(child:ColoredBox(color:Color(0x55FFFFFF),child:Center(child:CircularProgressIndicator())))]));
}