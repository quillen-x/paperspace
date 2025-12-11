import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/work_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // 获取数据库实例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('work_records.db');
    return _database!;
  }

  // 初始化数据库
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5, // 提升版本，增加标签列与标签表
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  // 创建数据库表
  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE work_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        images TEXT NOT NULL,
        tag TEXT NOT NULL,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');
    await _seedDefaultTags(db);
  }

  // 数据库迁移
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      final hasTitle = await _hasColumn(db, 'work_records', 'title');
      await db.execute('''
        CREATE TABLE work_records_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content TEXT NOT NULL,
          images TEXT NOT NULL,
          tag TEXT NOT NULL DEFAULT '未分类',
          date TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        INSERT INTO work_records_new (id, content, images, tag, date, created_at)
        SELECT id,
               ${hasTitle ? "CASE WHEN title IS NOT NULL AND title != '' THEN title || CASE WHEN content IS NOT NULL AND content != '' THEN '\\n' || content ELSE '' END ELSE COALESCE(content, '') END" : "COALESCE(content, '')"},
               '[]' as images,
               '未分类' as tag,
               date,
               created_at
        FROM work_records
      ''');

      await db.execute('DROP TABLE work_records');
      await db.execute('ALTER TABLE work_records_new RENAME TO work_records');
    }

    if (oldVersion < 5) {
      final hasTag = await _hasColumn(db, 'work_records', 'tag');
      if (!hasTag) {
        await db.execute("ALTER TABLE work_records ADD COLUMN tag TEXT NOT NULL DEFAULT '未分类'");
      }
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='tags'",
      );
      if (tables.isEmpty) {
        await db.execute('''
          CREATE TABLE tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
          )
        ''');
        await _seedDefaultTags(db);
      }
    }
  }

  // 判断列是否存在
  Future<bool> _hasColumn(Database db, String table, String column) async {
    final result = await db.rawQuery(
      "PRAGMA table_info($table)",
    );
    return result.any((row) => row['name'] == column);
  }

  // 获取数据库文件路径（用于调试）
  Future<String> get databasePath async {
    final db = await database;
    return db.path;
  }

  // 标签表：种子数据
  Future<void> _seedDefaultTags(Database db) async {
    const defaults = ['开发', '测试', '设计', '运营', '需求', '总结', '未分类'];
    for (final name in defaults) {
      await db.insert(
        'tags',
        {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // 插入工作记录
  Future<int> insertWorkRecord(WorkRecord record) async {
    final db = await database;
    return await db.insert('work_records', record.toMap());
  }

  // 获取所有工作记录，按日期倒序排列
  Future<List<WorkRecord>> getAllWorkRecords() async {
    final db = await database;
    final result = await db.query(
      'work_records',
      orderBy: 'date DESC, created_at DESC',
    );
    return result.map((map) => WorkRecord.fromMap(map)).toList();
  }

  // 根据日期获取工作记录
  Future<List<WorkRecord>> getWorkRecordsByDate(DateTime date) async {
    final db = await database;
    final dateStr = date.toIso8601String().split('T')[0];
    final result = await db.query(
      'work_records',
      where: 'date LIKE ?',
      whereArgs: ['$dateStr%'],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => WorkRecord.fromMap(map)).toList();
  }

  // 根据ID获取工作记录
  Future<WorkRecord?> getWorkRecordById(int id) async {
    final db = await database;
    final result = await db.query(
      'work_records',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return WorkRecord.fromMap(result.first);
  }

  // 更新工作记录
  Future<int> updateWorkRecord(WorkRecord record) async {
    final db = await database;
    return await db.update(
      'work_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  // 删除工作记录
  Future<int> deleteWorkRecord(int id) async {
    final db = await database;
    return await db.delete(
      'work_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 标签 CRUD
  Future<List<String>> getAllTags() async {
    final db = await database;
    final result = await db.query('tags', orderBy: 'id ASC');
    return result.map((e) => e['name'] as String).toList();
  }

  Future<int> insertTag(String name) async {
    final db = await database;
    return await db.insert('tags', {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> updateTag(String oldName, String newName) async {
    final db = await database;
    final count = await db.update('tags', {'name': newName},
        where: 'name = ?', whereArgs: [oldName]);
    // 同步更新记录表中的标签名称
    await db.update('work_records', {'tag': newName},
        where: 'tag = ?', whereArgs: [oldName]);
    return count;
  }

  Future<int> deleteTag(String name) async {
    final db = await database;
    // 先把使用该标签的记录改为未分类
    await db.update('work_records', {'tag': '未分类'},
        where: 'tag = ?', whereArgs: [name]);
    return await db.delete('tags', where: 'name = ?', whereArgs: [name]);
  }

  // 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
