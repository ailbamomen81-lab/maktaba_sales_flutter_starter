import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = join(await getDatabasesPath(), 'maktaba_sales.db');
    _database = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT UNIQUE,
            name TEXT NOT NULL,
            unit TEXT NOT NULL DEFAULT 'قطعة',
            buy_price REAL NOT NULL DEFAULT 0 CHECK(buy_price >= 0),
            sell_price REAL NOT NULL DEFAULT 0 CHECK(sell_price >= 0),
            qty REAL NOT NULL DEFAULT 0 CHECK(qty >= 0),
            min_qty REAL NOT NULL DEFAULT 0,
            active INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE contacts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL CHECK(kind IN ('customer','supplier')),
            name TEXT NOT NULL,
            phone TEXT,
            opening_balance REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE invoices(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            number TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL CHECK(kind IN ('sale','purchase','sale_return','purchase_return')),
            contact_id INTEGER,
            created_at TEXT NOT NULL,
            subtotal REAL NOT NULL DEFAULT 0,
            discount REAL NOT NULL DEFAULT 0,
            total REAL NOT NULL DEFAULT 0,
            paid REAL NOT NULL DEFAULT 0,
            note TEXT,
            FOREIGN KEY(contact_id) REFERENCES contacts(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE invoice_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoice_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            qty REAL NOT NULL CHECK(qty > 0),
            price REAL NOT NULL CHECK(price >= 0),
            unit_cost REAL NOT NULL DEFAULT 0,
            line_total REAL NOT NULL,
            FOREIGN KEY(invoice_id) REFERENCES invoices(id),
            FOREIGN KEY(product_id) REFERENCES products(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE stock_movements(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL,
            invoice_id INTEGER,
            movement TEXT NOT NULL,
            qty_delta REAL NOT NULL,
            created_at TEXT NOT NULL,
            note TEXT,
            FOREIGN KEY(product_id) REFERENCES products(id),
            FOREIGN KEY(invoice_id) REFERENCES invoices(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE payments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            contact_id INTEGER NOT NULL,
            amount REAL NOT NULL CHECK(amount > 0),
            direction TEXT NOT NULL CHECK(direction IN ('received','paid')),
            created_at TEXT NOT NULL,
            note TEXT,
            FOREIGN KEY(contact_id) REFERENCES contacts(id)
          )
        ''');
        await db.execute('''
          CREATE TABLE app_settings(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.insert('app_settings', {'key':'store_name','value':'مكتبة القرطاسية'});
        await db.insert('app_settings', {'key':'currency','value':'ر.ي'});
        await db.insert('app_settings', {'key':'next_invoice','value':'1'});
      },
    );
    return _database!;
  }
}
