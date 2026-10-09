import 'package:sqflite/sqflite.dart';
import 'database.dart';

class SalesService {
  final AppDb _appDb = AppDb.instance;

  String _now() => DateTime.now().toIso8601String();

  Future<List<Map<String, Object?>>> searchProducts(String query) async {
    final db = await _appDb.database;
    final q = query.trim();
    return db.query(
      'products',
      where: q.isEmpty ? 'active=1' : 'active=1 AND (name LIKE ? OR barcode LIKE ?)',
      whereArgs: q.isEmpty ? null : ['%$q%', '%$q%'],
      orderBy: 'name',
      limit: 100,
    );
  }

  Future<int> addProduct({
    required String name,
    String? barcode,
    String unit = 'قطعة',
    double buyPrice = 0,
    double sellPrice = 0,
    double openingQty = 0,
    double minQty = 0,
  }) async {
    if (name.trim().isEmpty || buyPrice < 0 || sellPrice < 0 ||
        openingQty < 0 || minQty < 0) {
      throw ArgumentError('تحقق من اسم الصنف والأسعار والكميات');
    }
    final db = await _appDb.database;
    return db.transaction((txn) async {
      final id = await txn.insert('products', {
        'name': name.trim(),
        'barcode': (barcode == null || barcode.trim().isEmpty) ? null : barcode.trim(),
        'unit': unit,
        'buy_price': buyPrice,
        'sell_price': sellPrice,
        'qty': openingQty,
        'min_qty': minQty,
      });
      if (openingQty > 0) {
        await txn.insert('stock_movements', {
          'product_id': id, 'movement': 'opening', 'qty_delta': openingQty,
          'created_at': _now(), 'note': 'رصيد افتتاحي',
        });
      }
      return id;
    });
  }

  Future<int> addContact({
    required String kind,
    required String name,
    String? phone,
    double openingBalance = 0,
  }) async {
    if (!['customer', 'supplier'].contains(kind) || name.trim().isEmpty) {
      throw ArgumentError('نوع الحساب أو الاسم غير صحيح');
    }
    final db = await _appDb.database;
    return db.insert('contacts', {
      'kind': kind, 'name': name.trim(), 'phone': phone,
      'opening_balance': openingBalance,
    });
  }

  /// lines: [{'product_id': 1, 'qty': 2.0, 'price': 10.0}]
  /// kind: sale, purchase, sale_return, purchase_return
  Future<Map<String, Object?>> createInvoice({
    required String kind,
    required List<Map<String, num>> lines,
    int? contactId,
    double discount = 0,
    double paid = 0,
    String? note,
  }) async {
    const allowed = ['sale', 'purchase', 'sale_return', 'purchase_return'];
    if (!allowed.contains(kind)) throw ArgumentError('نوع الفاتورة غير صحيح');
    if (lines.isEmpty || discount < 0 || paid < 0) {
      throw ArgumentError('الفاتورة فارغة أو توجد قيمة سالبة');
    }

    final db = await _appDb.database;
    return db.transaction((txn) async {
      final settings = await txn.query('app_settings',
          where: 'key=?', whereArgs: ['next_invoice'], limit: 1);
      final next = int.tryParse('${settings.first['value']}') ?? 1;
      final number = '${DateTime.now().year}-${next.toString().padLeft(6, '0')}';

      double subtotal = 0;
      final prepared = <Map<String, Object?>>[];
      for (final line in lines) {
        final productId = line['product_id']!.toInt();
        final qty = line['qty']!.toDouble();
        if (qty <= 0) throw ArgumentError('الكمية يجب أن تكون أكبر من صفر');
        final rows = await txn.query('products',
            where: 'id=? AND active=1', whereArgs: [productId], limit: 1);
        if (rows.isEmpty) throw StateError('الصنف غير موجود');
        final p = rows.first;
        final price = (line['price'] ?? (kind.contains('purchase')
            ? p['buy_price'] as num : p['sell_price'] as num)).toDouble();
        if (price < 0) throw ArgumentError('السعر غير صحيح');
        final currentQty = (p['qty'] as num).toDouble();
        final stockDelta = switch (kind) {
          'sale' || 'purchase_return' => -qty,
          _ => qty,
        };
        if (stockDelta < 0 && currentQty + stockDelta < -0.000001) {
          throw StateError('المخزون غير كافٍ للصنف: ${p['name']}');
        }
        final cost = (p['buy_price'] as num).toDouble();
        final lineTotal = qty * price;
        subtotal += lineTotal;
        prepared.add({
          'product_id': productId, 'qty': qty, 'price': price,
          'cost': cost, 'line_total': lineTotal, 'delta': stockDelta,
        });
      }
      if (discount > subtotal) throw ArgumentError('الخصم أكبر من إجمالي الفاتورة');
      final total = subtotal - discount;
      if (paid > total && !kind.endsWith('return')) {
        throw ArgumentError('المبلغ المدفوع أكبر من إجمالي الفاتورة');
      }

      final invoiceId = await txn.insert('invoices', {
        'number': number, 'kind': kind, 'contact_id': contactId,
        'created_at': _now(), 'subtotal': subtotal, 'discount': discount,
        'total': total, 'paid': paid, 'note': note,
      });

      for (final line in prepared) {
        await txn.insert('invoice_items', {
          'invoice_id': invoiceId, 'product_id': line['product_id'],
          'qty': line['qty'], 'price': line['price'],
          'unit_cost': line['cost'], 'line_total': line['line_total'],
        });
        await txn.rawUpdate('UPDATE products SET qty = qty + ? WHERE id = ?',
            [line['delta'], line['product_id']]);
        await txn.insert('stock_movements', {
          'product_id': line['product_id'], 'invoice_id': invoiceId,
          'movement': kind, 'qty_delta': line['delta'],
          'created_at': _now(), 'note': number,
        });
      }
      await txn.update('app_settings', {'value': '${next + 1}'},
          where: 'key=?', whereArgs: ['next_invoice']);
      return {'id': invoiceId, 'number': number, 'subtotal': subtotal, 'total': total};
    });
  }

  Future<List<Map<String, Object?>>> invoices({
    DateTime? from, DateTime? to, String? kind,
  }) async {
    final db = await _appDb.database;
    final clauses = <String>[];
    final args = <Object?>[];
    if (from != null) { clauses.add('created_at >= ?'); args.add(from.toIso8601String()); }
    if (to != null) { clauses.add('created_at <= ?'); args.add(to.toIso8601String()); }
    if (kind != null) { clauses.add('kind = ?'); args.add(kind); }
    return db.query('invoices',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC');
  }

  Future<Map<String, double>> salesSummary(DateTime from, DateTime to) async {
    final db = await _appDb.database;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN kind='sale' THEN total ELSE 0 END),0) sales,
        COALESCE(SUM(CASE WHEN kind='purchase' THEN total ELSE 0 END),0) purchases,
        COALESCE(SUM(CASE WHEN kind='sale_return' THEN total ELSE 0 END),0) sale_returns,
        COALESCE(SUM(CASE WHEN kind='purchase_return' THEN total ELSE 0 END),0) purchase_returns
      FROM invoices WHERE created_at >= ? AND created_at <= ?
    ''', [from.toIso8601String(), to.toIso8601String()]);
    final r = rows.first;
    return {
      'sales': (r['sales'] as num).toDouble(),
      'purchases': (r['purchases'] as num).toDouble(),
      'sale_returns': (r['sale_returns'] as num).toDouble(),
      'purchase_returns': (r['purchase_returns'] as num).toDouble(),
    };
  }

  Future<void> adjustStock({
    required int productId,
    required double actualQty,
    required String note,
  }) async {
    if (actualQty < 0) throw ArgumentError('الجرد لا يقبل كمية سالبة');
    final db = await _appDb.database;
    await db.transaction((txn) async {
      final rows = await txn.query('products', where: 'id=?', whereArgs: [productId]);
      if (rows.isEmpty) throw StateError('الصنف غير موجود');
      final oldQty = (rows.first['qty'] as num).toDouble();
      final delta = actualQty - oldQty;
      await txn.update('products', {'qty': actualQty},
          where: 'id=?', whereArgs: [productId]);
      await txn.insert('stock_movements', {
        'product_id': productId, 'movement': 'stocktake',
        'qty_delta': delta, 'created_at': _now(), 'note': note,
      });
    });
  }
}
