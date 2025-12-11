import 'dart:io';
import 'dart:typed_data';

import '../models/work_record.dart';
import '../repositories/work_record_repository.dart';
import 'image_storage_service.dart';

/// 工作记录管理器
/// 统一管理记录的增删改查操作
class WorkRecordManager {
  WorkRecordManager({
    required WorkRecordRepository recordRepository,
    required ImageStorageService imageService,
  })  : _recordRepository = recordRepository,
        _imageService = imageService;

  final WorkRecordRepository _recordRepository;
  final ImageStorageService _imageService;

  // 所有记录
  List<WorkRecord> _allRecords = [];
  
  // 当前过滤后的记录
  List<WorkRecord> _filteredRecords = [];
  
  // 当前过滤标签
  String _activeTag = '全部';

  // Getters
  List<WorkRecord> get allRecords => List.unmodifiable(_allRecords);
  List<WorkRecord> get filteredRecords => List.unmodifiable(_filteredRecords);
  String get activeTag => _activeTag;

  /// 加载所有记录
  Future<List<WorkRecord>> loadAllRecords() async {
    _allRecords = await _recordRepository.getAll();
    _applyFilter();
    return _allRecords;
  }

  /// 根据ID获取记录
  Future<WorkRecord?> getRecordById(int id) async {
    return await _recordRepository.getById(id);
  }

  /// 添加记录
  /// [content] 记录内容
  /// [imagePaths] 图片路径列表（临时路径，会被持久化）
  /// [tag] 标签
  /// [date] 日期（可选，默认为当前时间）
  Future<WorkRecord> addRecord({
    required String content,
    required List<String> imagePaths,
    required String tag,
    DateTime? date,
  }) async {
    final now = date ?? DateTime.now();
    
    // 持久化图片路径
    final storedImages = await _imageService.persistPaths(imagePaths, now);
    
    // 创建记录
    final record = WorkRecord(
      content: content.trim(),
      imagePaths: storedImages,
      tag: tag.isEmpty ? '未分类' : tag,
      date: now,
      createdAt: now,
    );
    
    // 插入数据库
    final id = await _recordRepository.insert(record);
    
    // 更新本地记录列表
    final newRecord = record.copyWith(id: id);
    _allRecords.insert(0, newRecord); // 新记录插入到最前面
    _applyFilter();
    
    return newRecord;
  }

  /// 添加记录（支持内存图片与路径）
  Future<WorkRecord> addRecordWithBytes({
    required String content,
    required List<Uint8List> imageBytes,
    required String tag,
    DateTime? date,
  }) async {
    final now = date ?? DateTime.now();

    // 持久化内存图片
    final storedImages = <String>[];
    for (final bytes in imageBytes) {
      final saved = await _imageService.saveBytes(bytes, now);
      if (saved != null) {
        storedImages.add(saved);
      }
    }

    final record = WorkRecord(
      content: content.trim(),
      imagePaths: storedImages,
      tag: tag.isEmpty ? '未分类' : tag,
      date: now,
      createdAt: now,
    );

    final id = await _recordRepository.insert(record);
    final newRecord = record.copyWith(id: id);
    _allRecords.insert(0, newRecord);
    _applyFilter();
    return newRecord;
  }

  /// 更新记录
  /// [record] 要更新的记录
  Future<WorkRecord> updateRecord(WorkRecord record) async {
    await _recordRepository.update(record);
    
    // 更新本地记录列表
    final index = _allRecords.indexWhere((r) => r.id == record.id);
    if (index != -1) {
      _allRecords[index] = record;
      _applyFilter();
    }
    
    return record;
  }

  /// 删除记录
  /// [id] 记录ID
  /// [deleteImages] 是否同时删除关联的图片文件（默认true）
  Future<void> deleteRecord(int id, {bool deleteImages = true}) async {
    // 获取记录信息（用于删除图片）
    WorkRecord? record;
    if (deleteImages) {
      record = await _recordRepository.getById(id);
    }
    
    // 删除数据库记录
    await _recordRepository.delete(id);
    
    // 删除关联的图片文件
    if (deleteImages && record != null) {
      for (final path in record.imagePaths) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // 忽略单个文件删除失败
        }
      }
    }
    
    // 更新本地记录列表
    _allRecords.removeWhere((r) => r.id == id);
    _applyFilter();
  }

  /// 设置过滤标签
  /// [tag] 标签名称，'全部' 表示不过滤
  void setFilterTag(String tag) {
    _activeTag = tag;
    _applyFilter();
  }

  /// 应用过滤条件
  void _applyFilter() {
    if (_activeTag == '全部') {
      _filteredRecords = List.from(_allRecords);
    } else {
      _filteredRecords = _allRecords.where((r) => r.tag == _activeTag).toList();
    }
  }

  /// 根据标签过滤记录
  /// [tag] 标签名称
  List<WorkRecord> filterByTag(String tag) {
    if (tag == '全部') {
      return List.from(_allRecords);
    }
    return _allRecords.where((r) => r.tag == tag).toList();
  }

  /// 搜索记录
  /// [keyword] 搜索关键词
  List<WorkRecord> search(String keyword) {
    if (keyword.isEmpty) {
      return List.from(_filteredRecords);
    }
    
    final lowerKeyword = keyword.toLowerCase();
    return _filteredRecords.where((record) {
      // 搜索内容
      if (record.content.toLowerCase().contains(lowerKeyword)) {
        return true;
      }
      // 搜索标签
      if (record.tag.toLowerCase().contains(lowerKeyword)) {
        return true;
      }
      return false;
    }).toList();
  }

  /// 刷新记录列表
  Future<List<WorkRecord>> refresh() async {
    return await loadAllRecords();
  }

  /// 清空所有记录（谨慎使用）
  Future<void> clearAll() async {
    // 删除所有图片文件
    for (final record in _allRecords) {
      for (final path in record.imagePaths) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // 忽略删除失败
        }
      }
    }
    
    // 清空数据库（需要实现批量删除方法）
    // 这里暂时逐个删除
    for (final record in _allRecords) {
      if (record.id != null) {
        await _recordRepository.delete(record.id!);
      }
    }
    
    _allRecords.clear();
    _filteredRecords.clear();
  }
}

