import 'package:flutter/material.dart';
import 'database.dart';
import 'sales_service.dart';

void main() => runApp(const MaktabaApp());

class MaktabaApp extends StatelessWidget {
  const MaktabaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'مبيعات المكتبة',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final service = SalesService();
  List<Map<String, Object?>> products = [];
  final search = TextEditingController();
  final name = TextEditingController();
  final barcode = TextEditingController();
  final buy = TextEditingController(text: '0');
  final sell = TextEditingController(text: '0');
  final qty = TextEditingController(text: '0');

  @override
  void initState() { super.initState(); refresh(); }

  Future<void> refresh() async {
    final rows = await service.searchProducts(search.text);
    if (mounted) setState(() => products = rows);
  }

  Future<void> addProduct() async {
    name.clear(); barcode.clear(); buy.text='0'; sell.text='0'; qty.text='0';
    final ok = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(
        title: const Text('إضافة صنف'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          field(name, 'اسم الصنف'),
          field(barcode, 'الباركود (اختياري)'),
          field(buy, 'سعر الشراء'),
          field(sell, 'سعر البيع'),
          field(qty, 'الرصيد الافتتاحي'),
        ])),
        actions: [
          TextButton(onPressed:()=>Navigator.pop(ctx,false), child: const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true), child: const Text('حفظ')),
        ],
      ));
    if (ok != true) return;
    try {
      await service.addProduct(
        name: name.text, barcode: barcode.text,
        buyPrice: double.parse(buy.text), sellPrice: double.parse(sell.text),
        openingQty: double.parse(qty.text),
      );
      await refresh();
      if (mounted) message('تم حفظ الصنف');
    } catch (e) { if (mounted) message('تعذر الحفظ: $e'); }
  }

  Widget field(TextEditingController c, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: TextField(controller:c, decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())),
  );

  void message(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('نظام مبيعات المكتبة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed:addProduct, icon:const Icon(Icons.add), label:const Text('إضافة صنف')),
      body: Column(children:[
        Padding(padding:const EdgeInsets.all(12), child:TextField(
          controller:search, onChanged:(_)=>refresh(),
          decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'البحث بالاسم أو الباركود',border:OutlineInputBorder()))),
        Expanded(child: products.isEmpty
          ? const Center(child:Text('لا توجد أصناف. اضغط إضافة صنف للبدء.'))
          : ListView.builder(itemCount:products.length,itemBuilder:(ctx,i){
            final p=products[i];
            return Card(child:ListTile(
              leading:const Icon(Icons.menu_book),
              title:Text('${p['name']}'),
              subtitle:Text('باركود: ${p['barcode'] ?? '-'}\\nشراء: ${p['buy_price']} | بيع: ${p['sell_price']}'),
              isThreeLine:true,
              trailing:Text('الكمية\\n${p['qty']}'),
            ));
          })),
        const Padding(padding:EdgeInsets.all(12), child:Text('نسخة تأسيسية: البيع والطباعة والديون والنسخ الاحتياطي تستكمل في الخطوات التالية.', textAlign:TextAlign.center)),
      ]),
    ),
  );
}