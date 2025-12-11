import '../database/database_helper.dart';
import '../models/work_record.dart';

class WorkRecordRepository {
  WorkRecordRepository(this._db);

  final DatabaseHelper _db;

  Future<int> insert(WorkRecord record) => _db.insertWorkRecord(record);

  Future<int> update(WorkRecord record) => _db.updateWorkRecord(record);

  Future<int> delete(int id) => _db.deleteWorkRecord(id);

  Future<List<WorkRecord>> getAll() => _db.getAllWorkRecords();

  Future<WorkRecord?> getById(int id) => _db.getWorkRecordById(id);
}

