import '../database/database_helper.dart';

class TagRepository {
  TagRepository(this._db);

  final DatabaseHelper _db;

  Future<List<String>> getAll() => _db.getAllTags();

  Future<int> insert(String name) => _db.insertTag(name);

  Future<int> update(String oldName, String newName) => _db.updateTag(oldName, newName);

  Future<int> delete(String name) => _db.deleteTag(name);
}

