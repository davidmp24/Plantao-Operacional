import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;

  DBHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'commitments.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE commitments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            notes TEXT,
            color INTEGER
          )
        ''');
      },
    );
  }

  Future<int> insertCommitment(Map<String, dynamic> data) async {
    final db = await database;
    return await db.insert('commitments', data);
  }

  Future<List<Map<String, dynamic>>> getAllCommitments() async {
    final db = await database;
    return await db.query('commitments');
  }

  Future<int> deleteCommitment(int id) async {
    final db = await database;
    return await db.delete('commitments', where: 'id = ?', whereArgs: [id]);
  }
}
