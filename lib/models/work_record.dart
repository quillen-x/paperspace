import 'dart:convert';

class WorkRecord {
  final int? id;
  final String content;
  final List<String> imagePaths;
  final String tag;
  final DateTime date;
  final DateTime createdAt;

  WorkRecord({
    this.id,
    required this.content,
    this.imagePaths = const [],
    required this.tag,
    required this.date,
    required this.createdAt,
  });

  // 将对象转换为Map，用于数据库存储
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'images': jsonEncode(imagePaths),
      'tag': tag,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  // 从Map创建对象，用于从数据库读取
  factory WorkRecord.fromMap(Map<String, dynamic> map) {
    return WorkRecord(
      id: map['id'] as int?,
      content: map['content'] as String,
      imagePaths: _decodeImages(map['images']),
      tag: (map['tag'] as String?) ?? '未分类',
      date: DateTime.parse(map['date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  // 复制对象，用于更新
  WorkRecord copyWith({
    int? id,
    String? content,
    List<String>? imagePaths,
    String? tag,
    DateTime? date,
    DateTime? createdAt,
  }) {
    return WorkRecord(
      id: id ?? this.id,
      content: content ?? this.content,
      imagePaths: imagePaths ?? this.imagePaths,
      tag: tag ?? this.tag,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static List<String> _decodeImages(dynamic raw) {
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      // ignore parse error, return empty list
    }
    return [];
  }
}
