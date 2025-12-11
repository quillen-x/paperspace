import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

import 'image_storage_service.dart';

class ClipboardService {
  ClipboardService(this._imageStorage);

  final ImageStorageService _imageStorage;

  /// 智能粘贴：优先图片，其次 HTML，再次文本
  Future<SmartPasteResult> smartPaste() async {
    // 先尝试图片
    // try {
    //   final Uint8List? imageBytes = await Pasteboard.image;
    //   if (imageBytes != null && imageBytes.isNotEmpty) {
    //     return SmartPasteResult.image(imageBytes);
    //   }
    // } catch (_) {
    //   // 忽略，继续尝试文本
    // }

    // 再尝试文件列表（复制文件/图片时）
    try {
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        const exts = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.heif'];
        final imageFiles = files.where((p) {
          final lower = p.toLowerCase();
          return exts.any((ext) => lower.endsWith(ext));
        }).toList();
        if (imageFiles.isNotEmpty) {
          return SmartPasteResult.imageFiles(imageFiles);
        }
      }
    } catch (_) {
      // 忽略
    }

    // 再尝试 HTML
    try {
      final html = await Pasteboard.html;
      if (html != null && html.trim().isNotEmpty) {
        return SmartPasteResult.html(html.trim());
      }
    } catch (_) {
      // 忽略
    }

    // 再尝试文本
    try {
      final text = await Pasteboard.text;
      if (text != null && text.trim().isNotEmpty) {
        return SmartPasteResult.text(text.trim());
      }
    } catch (_) {
      // 忽略
    }

    return const SmartPasteResult.empty();
  }

  /// 从剪贴板导入图片，返回已保存的本地路径列表
  Future<List<String>> importImages(DateTime date) async {
    // 1) 使用 pasteboard 插件获取图片（优先）
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final saved = await _imageStorage.saveBytes(imageBytes, date);
        if (saved != null) return [saved];
      }
    } catch (e) {
      // 忽略错误，继续尝试其他方法
    }

    // 2) 使用 pasteboard 插件获取文件列表（桌面平台）
    try {
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        const exts = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.heif'];
        final imagePaths = <String>[];
        for (final filePath in files) {
          final file = File(filePath);
          if (file.existsSync()) {
            final lowerPath = filePath.toLowerCase();
            for (final ext in exts) {
              if (lowerPath.endsWith(ext)) {
                imagePaths.add(filePath);
                break;
              }
            }
          }
        }
        if (imagePaths.isNotEmpty) {
          return _imageStorage.persistPaths(imagePaths, date);
        }
      }
    } catch (e) {
      // 忽略错误，继续尝试其他方法
    }

    // 3) 从 HTML 中提取 base64 图片（Windows 平台）
    try {
      final html = await Pasteboard.html;
      if (html != null && html.contains('data:image')) {
        final match = RegExp(r'data:image/[^;]+;base64,([A-Za-z0-9+/=]+)').firstMatch(html);
        if (match != null) {
          try {
            final decoded = base64Decode(match.group(1)!);
            final saved = await _imageStorage.saveBytes(decoded, date);
            if (saved != null) return [saved];
          } catch (_) {
            // 忽略解码错误
          }
        }
      }
    } catch (e) {
      // 忽略错误，继续尝试其他方法
    }

    // 4) 从文本中提取图片路径
    try {
      final text = await Pasteboard.text;
      if (text == null || text.trim().isEmpty) return [];

      final separators = RegExp(r'[\r\n]+');
      final candidates = text
          .split(separators)
          .expand((line) => line.split(' '))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      const exts = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.heic', '.heif'];
      final imagePaths = <String>[];
      for (final c in candidates) {
        String path = c;
        if (path.startsWith('file://')) {
          path = Uri.parse(path).toFilePath();
        }
        for (final ext in exts) {
          if (path.toLowerCase().endsWith(ext)) {
            final f = File(path);
            if (f.existsSync()) {
              imagePaths.add(f.path);
            }
            break;
          }
        }
      }

      if (imagePaths.isNotEmpty) {
        return _imageStorage.persistPaths(imagePaths, date);
      }
    } catch (e) {
      // 忽略错误
    }

    return [];
  }
}

enum SmartPasteType { image, imageFiles, html, text, empty }

class SmartPasteResult {
  final SmartPasteType type;
  final Uint8List? imageBytes;
  final String? text; // 可用于纯文本或 HTML
  final List<String>? filePaths; // 剪贴板中的文件路径（不落盘）

  const SmartPasteResult._(this.type, {this.imageBytes, this.text, this.filePaths});

  const SmartPasteResult.empty() : this._(SmartPasteType.empty);

  factory SmartPasteResult.image(Uint8List bytes) =>
      SmartPasteResult._(SmartPasteType.image, imageBytes: bytes);

  factory SmartPasteResult.imageFiles(List<String> paths) =>
      SmartPasteResult._(SmartPasteType.imageFiles, filePaths: paths);

  factory SmartPasteResult.text(String text) =>
      SmartPasteResult._(SmartPasteType.text, text: text);

  factory SmartPasteResult.html(String html) =>
      SmartPasteResult._(SmartPasteType.html, text: html);
}

