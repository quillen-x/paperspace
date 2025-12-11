import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageStorageService {
  /// 按日期（yyyy-MM-dd）存储图片，返回保存后的路径
  Future<List<String>> persistPaths(List<String> sourcePaths, DateTime date) async {
    if (sourcePaths.isEmpty) return [];
    final dayDir = await _ensureDayDir(date);
    final saved = <String>[];
    for (final src in sourcePaths) {
      final file = File(src);
      if (!await file.exists()) continue;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${p.basename(src)}';
      final target = File(p.join(dayDir.path, fileName));
      await file.copy(target.path);
      saved.add(target.path);
    }
    return saved;
  }

  /// 保存内存中的图片字节到日期目录，返回路径
  Future<String?> saveBytes(Uint8List bytes, DateTime date) async {
    if (bytes.isEmpty) return null;
    final dayDir = await _ensureDayDir(date);
    final fileName = 'paste_${DateTime.now().millisecondsSinceEpoch}.png';
    final target = File(p.join(dayDir.path, fileName));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<Directory> _ensureDayDir(DateTime date) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(appDir.path, 'work_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final dirName =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final dayDir = Directory(p.join(imagesDir.path, dirName));
    if (!await dayDir.exists()) {
      await dayDir.create(recursive: true);
    }
    return dayDir;
  }
}

