import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/database_helper.dart';
import '../models/work_record.dart';
import '../repositories/tag_repository.dart';
import '../repositories/work_record_repository.dart';
import '../services/clipboard_service.dart';
import '../services/image_storage_service.dart';
import '../services/work_record_manager.dart';

const _vscodeBg = Color(0xFF1E1E1E);
const _vscodePanel = Color(0xFF252526);
const _vscodeCard = Color(0xFF2D2D2D);
const _vscodeBorder = Color(0xFF3C3C3C);
const _vscodeText = Color(0xFFD4D4D4);
const _vscodeMuted = Color(0xFF9DA5B4);
const _vscodeAccent = Color(0xFF569CD6);
const _vscodeRed = Color(0xFFF48771);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  late final TagRepository _tagRepo;
  late final WorkRecordManager _recordManager;
  late final ClipboardService _clipboardService;
  late final ImageStorageService _imageService;
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode(debugLabel: 'paste-listener');
  final List<Uint8List> _newImageBytes = [];
  List<String> _tags = [];
  String _activeTag = '全部';
  int _settingsIndex = 0;
  bool _showSearch = false;
  String _searchQuery = '';

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDragOver = false;
  bool get _hasDraft => _contentController.text.trim().isNotEmpty || _newImageBytes.isNotEmpty;

  List<WorkRecord> get _visibleRecords {
    if (_searchQuery.isEmpty) return _recordManager.filteredRecords;
    final q = _searchQuery.toLowerCase();
    return _recordManager.filteredRecords.where((r) {
      return r.content.toLowerCase().contains(q) || r.tag.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tagRepo = TagRepository(_dbHelper);
    final recordRepo = WorkRecordRepository(_dbHelper);
    _imageService = ImageStorageService();
    _recordManager = WorkRecordManager(
      recordRepository: recordRepo,
      imageService: _imageService,
    );
    _clipboardService = ClipboardService(_imageService);
    _logDbPath();
    _loadTagsAndRecords();
    _contentController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _selectTag(String tag) {
    setState(() {
      _activeTag = tag;
      _recordManager.setFilterTag(tag);
    });
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 24.h + MediaQuery.of(context).padding.top, 12.w, 12.h),
      decoration: const BoxDecoration(
        color: _vscodePanel,
        border: Border(
          bottom: BorderSide(color: _vscodeBorder),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧：标签选择器（显示当前选中标签，点击可切换）
          PopupMenuButton<String>(
            tooltip: '切换标签',
            color: _vscodePanel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: _vscodeBorder),
            ),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: _vscodeAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _vscodeAccent.withValues(alpha: 0.3)),
              ),
              child: Text(
                _activeTag,
                style: TextStyle(
                  color: _vscodeAccent,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            itemBuilder: (context) {
              return _tags.map((tag) {
                final isSelected = tag == _activeTag;
                return PopupMenuItem<String>(
                  value: tag,
                  height: 30.h,
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: isSelected ? _vscodeAccent : _vscodeText,
                      fontSize: 12.sp,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                );
              }).toList();
            },
            onSelected: (tag) {
              _selectTag(tag);
            },
          ),
          // 右侧：搜索和设置按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showSearch) ...[
                Container(
                  width: 180.w,
                  constraints: BoxConstraints(
                    maxHeight: 30.h,
                    minHeight: 30.h,
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: TextStyle(color: _vscodeText, fontSize: 12.sp),
                    decoration: InputDecoration(
                      hintText: '搜索内容或标签',
                      hintStyle: TextStyle(color: _vscodeMuted, fontSize: 12.sp),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const ImageIcon(
                                AssetImage('assets/images/close.png'),
                                size: 16,
                                color: _vscodeMuted,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                              },
                            )
                          : null,
                      contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 8.w),
                      filled: true,
                      fillColor: _vscodeCard,
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: _vscodeBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: _vscodeAccent),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {
                        _searchQuery = v.trim();
                      });
                    },
                  ),
                ),
                SizedBox(width: 10.w),
              ],
              IconButton(
                icon: ImageIcon(
                  AssetImage(_showSearch ? 'assets/images/close.png' : 'assets/images/search.png'),
                  size: 16,
                  color: _vscodeText,
                ),
                tooltip: '搜索',
                onPressed: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) {
                      _searchQuery = '';
                      _searchController.clear();
                    }
                  });
                },
              ),
              GestureDetector(
                child: IconButton(
                  icon: const ImageIcon(
                    AssetImage('assets/images/setting.png'),
                    color: _vscodeText,
                  ),
                  onPressed: _showSettingsDialog,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    final TextEditingController addController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          backgroundColor: _vscodePanel,
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.6,
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                Widget tagManager() {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('标签管理', style: TextStyle(color: _vscodeText, fontSize: 16.sp, fontWeight: FontWeight.bold)),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: addController,
                              decoration: const InputDecoration(
                                hintText: '输入标签名称',
                              ),
                              style: TextStyle(color: _vscodeText, fontSize: 14.sp),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          ElevatedButton(
                            onPressed: () {
                              final text = addController.text.trim();
                              if (text.isEmpty || text == '全部') return;
                              if (_tags.contains(text)) return;
                              _dbHelper.insertTag(text).then((_) async {
                                await _loadTags();
                                setStateDialog(() {});
                              });
                              addController.clear();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _vscodeAccent,
                              foregroundColor: Colors.white,
                            ),
                            child: Text('新增', style: TextStyle(fontSize: 13.sp)),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: _vscodeCard,
                            border: Border.all(color: _vscodeBorder),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.all(8.w),
                          child: ListView.separated(
                            itemCount: _tags.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: _vscodeBorder,
                            ),
                            itemBuilder: (context, index) {
                              final tag = _tags[index];
                              final TextEditingController editCtrl = TextEditingController(text: tag);
                              return Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: editCtrl,
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                      ),
                                      style: TextStyle(
                                        color: _vscodeText,
                                        fontSize: 14.sp,
                                      ),
                                      onSubmitted: (value) async {
                                        final v = value.trim();
                                        if (v.isEmpty || v == '全部') return;
                                        if (_tags.contains(v) && v != tag) return;
                                        await _dbHelper.updateTag(tag, v);
                                        await _loadTags();
                                        if (_activeTag == tag) {
                                          _activeTag = v;
                                          _recordManager.setFilterTag(v);
                                        }
                                        setStateDialog(() {});
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const ImageIcon(
                                      AssetImage('assets/images/delete.png'),
                                      color: _vscodeRed,
                                    ),
                                    onPressed: () {
                                      if (tag == '全部' || tag == '未分类') return;
                                      _dbHelper.deleteTag(tag).then((_) async {
                                        await _loadTags();
                                        if (_activeTag == tag) {
                                          _activeTag = '全部';
                                          _recordManager.setFilterTag('全部');
                                        }
                                        setStateDialog(() {});
                                      });
                                    },
                                    tooltip: '删除',
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                }

                final List<String> settingsTitles = ['标签管理', '预留功能'];

                return Row(
                  children: [
                    Container(
                      width: 100.w,
                      decoration: const BoxDecoration(
                        color: _vscodeCard,
                        border: Border(
                          right: BorderSide(color: _vscodeBorder),
                        ),
                      ),
                      child: ListView.separated(
                        itemCount: settingsTitles.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: _vscodeBorder),
                        itemBuilder: (context, index) {
                          final selected = index == _settingsIndex;
                          return ListTile(
                            dense: true,
                            title: Text(
                              settingsTitles[index],
                              style: TextStyle(
                                color: selected ? _vscodeAccent : _vscodeText,
                                fontSize: 14.sp,
                              ),
                            ),
                            selected: selected,
                            selectedTileColor: _vscodeAccent.withOpacity(0.1),
                            onTap: () {
                              setStateDialog(() {
                                _settingsIndex = index;
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(16.w),
                        child: _settingsIndex == 0 ? tagManager() : Container(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    ).then((_) {
      addController.dispose();
    });
  }

  @override
  void dispose() {
    _contentController.removeListener(_onInputChanged);
    _contentController.dispose();
    _searchController.dispose();
    _inputFocusNode.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _logDbPath() async {
    final path = await _dbHelper.databasePath;
    debugPrint('Database path: $path');
  }

  Future<void> _loadTagsAndRecords() async {
    await _loadTags();
    await _loadWorkRecords();
  }

  Future<void> _loadTags() async {
    final tags = await _tagRepo.getAll();
    setState(() {
      _tags = ['全部', ...tags];
      if (!_tags.contains(_activeTag)) {
        _activeTag = '全部';
      }
      _recordManager.setFilterTag(_activeTag);
    });
  }

  Future<void> _loadWorkRecords() async {
    setState(() {
      _isLoading = true;
    });
    await _recordManager.loadAllRecords();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    if (result == null) return;
    final bytesList = <Uint8List>[];
    for (final f in result.files) {
      final path = f.path;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          bytesList.add(await file.readAsBytes());
        }
      } else if (f.bytes != null) {
        bytesList.add(f.bytes!);
      }
    }
    _addNewImageBytes(bytesList);
  }

  void _addNewImageBytes(List<Uint8List> bytesList) {
    if (bytesList.isEmpty) return;
    setState(() {
      _newImageBytes.addAll(bytesList);
    });
  }

  Future<List<Uint8List>> _loadBytesFromPaths(List<String> paths) async {
    final bytesList = <Uint8List>[];
    for (final p in paths) {
      final file = File(p);
      if (await file.exists()) {
        bytesList.add(await file.readAsBytes());
      }
    }
    return bytesList;
  }

  Future<List<Uint8List>> _loadBytesFromDropFiles(List<XFile> files) async {
    final bytesList = <Uint8List>[];
    for (final f in files) {
      try {
        bytesList.add(await f.readAsBytes());
      } catch (_) {}
    }
    return bytesList;
  }

  void _removeNewImageBytes(int index) {
    if (index < 0 || index >= _newImageBytes.length) return;
    setState(() {
      _newImageBytes.removeAt(index);
    });
  }

  Future<void> _handlePasteFromClipboard() async {
    final result = await _clipboardService.smartPaste();

    switch (result.type) {
      case SmartPasteType.image:
        _addNewImageBytes([result.imageBytes!]);
        break;
      case SmartPasteType.imageFiles:
        final bytesList = await _loadBytesFromPaths(result.filePaths ?? const []);
        _addNewImageBytes(bytesList);
        break;
      case SmartPasteType.html:
        final html = result.text ?? '';
        if (html.isNotEmpty) {
          final current = _contentController.text;
          final updated = current.isEmpty ? html : '$current\n$html';
          _contentController.text = updated;
          _contentController.selection = TextSelection.fromPosition(
            TextPosition(offset: _contentController.text.length),
          );
        }
        break;
      case SmartPasteType.text:
        final text = result.text ?? '';
        if (text.isNotEmpty) {
          final current = _contentController.text;
          final updated = current.isEmpty ? text : '$current\n$text';
          _contentController.text = updated;
          _contentController.selection = TextSelection.fromPosition(
            TextPosition(offset: _contentController.text.length),
          );
        }
        break;
      case SmartPasteType.empty:
        // 无可处理内容，不做提示
        break;
    }
  }

  /// 图片存储逻辑已移至 ImageStorageService

  Future<void> _addRecord() async {
    if (_isSaving) return;
    if (_contentController.text.trim().isEmpty && _newImageBytes.isEmpty) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await _recordManager.addRecordWithBytes(
        content: _contentController.text.trim(),
        imageBytes: _newImageBytes,
        tag: _activeTag == '全部' ? '未分类' : _activeTag,
      );
      _contentController.clear();
      _newImageBytes.clear();
      setState(() {}); // 刷新UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('添加成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteWorkRecord(int id) async {
    try {
      await _recordManager.deleteRecord(id);
      setState(() {}); // 刷新UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  Future<void> _confirmAndDelete(WorkRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _vscodePanel,
        title: Text('确认删除', style: TextStyle(color: _vscodeText, fontSize: 16.sp)),
        content: Text('删除后不可恢复，确定删除？', style: TextStyle(color: _vscodeText, fontSize: 14.sp)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: TextStyle(color: _vscodeText, fontSize: 14.sp)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('删除', style: TextStyle(color: _vscodeRed, fontSize: 14.sp)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _deleteWorkRecord(record.id!);
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    // 刚刚（小于1分钟）
    if (difference.inMinutes < 1) {
      return '刚刚';
    }
    // X分钟前（小于1小时）
    if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    }
    // X小时前（小于1天）
    if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    }
    // X天前（小于30天）
    if (difference.inDays < 30) {
      return '${difference.inDays}天前';
    }
    // X个月前（小于1年）
    if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months个月前';
    }
    // X年前
    final years = (difference.inDays / 365).floor();
    return '$years年前';
  }

  /// 解析文本中的URL并生成 TextSpan
  List<TextSpan> _parseTextWithLinks(String text) {
    final spans = <TextSpan>[];
    // URL 正则表达式：匹配 http://, https://, www. 开头的链接
    final urlPattern = RegExp(
      r'(https?://[^\s]+|www\.[^\s]+)',
      caseSensitive: false,
    );

    int lastMatchEnd = 0;
    for (final match in urlPattern.allMatches(text)) {
      // 添加链接前的普通文本
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: TextStyle(
            fontSize: 13.sp,
            height: 1.5,
            color: _vscodeText,
          ),
        ));
      }

      // 添加链接文本
      final url = match.group(0)!;
      final urlToLaunch = url.startsWith('http://') || url.startsWith('https://') ? url : 'https://$url';

      spans.add(TextSpan(
        text: url,
        style: TextStyle(
          fontSize: 13.sp,
          height: 1.5,
          color: _vscodeAccent,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _launchUrl(urlToLaunch),
      ));

      lastMatchEnd = match.end;
    }

    // 添加剩余的普通文本
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: TextStyle(
          fontSize: 13.sp,
          height: 1.5,
          color: _vscodeText,
        ),
      ));
    }

    // 如果没有找到任何链接，返回原始文本
    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 13.sp,
          height: 1.5,
          color: _vscodeText,
        ),
      ));
    }

    return spans;
  }

  /// 打开URL
  Future<void> _launchUrl(String url) async {
    try {
      // 确保 URL 格式正确
      String urlToLaunch = url;
      if (!urlToLaunch.startsWith('http://') && !urlToLaunch.startsWith('https://')) {
        urlToLaunch = 'https://$urlToLaunch';
      }

      debugPrint('尝试打开链接: $urlToLaunch');

      // 在 macOS 上，优先使用系统命令作为备选方案
      if (Platform.isMacOS) {
        try {
          final result = await Process.run('open', [urlToLaunch]);
          if (result.exitCode == 0) {
            debugPrint('使用 open 命令成功打开链接');
            return;
          } else {
            debugPrint('open 命令失败: ${result.stderr}');
          }
        } catch (e) {
          debugPrint('使用 open 命令异常: $e');
        }
      }

      // 尝试使用 url_launcher
      try {
        final uri = Uri.parse(urlToLaunch);
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (launched) {
          debugPrint('使用 url_launcher 成功打开链接');
          return;
        } else {
          debugPrint('url_launcher 返回 false');
        }
      } catch (e) {
        debugPrint('url_launcher 异常: $e');
      }

      // 如果都失败了，显示错误提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $urlToLaunch')),
        );
      }
    } catch (e) {
      debugPrint('打开链接异常: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开链接失败: $e')),
        );
      }
    }
  }

  Future<void> _showImagePreview(List<String> imagePaths, int initialIndex) async {
    if (imagePaths.isEmpty) return;
    if (!mounted) return;

    // 确保索引在有效范围内
    final validIndex = initialIndex < 0 || initialIndex >= imagePaths.length ? 0 : initialIndex;

    try {
      // 创建新窗口显示图片（desktop_multi_window 新 API）
      final arguments = jsonEncode({
        'type': 'imageViewer',
        'imagePaths': imagePaths,
        'initialIndex': validIndex,
      });

      final controller = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: arguments,
        ),
      );

      await controller.show();
    } catch (e) {
      debugPrint('创建图片查看窗口失败: $e');
      // 如果创建窗口失败，可以回退到对话框方式
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开图片查看器失败: $e')),
        );
      }
    }
  }

  double _calcImageSize(double maxWidth) {
    final spacing = 8.w;
    const columns = 7;
    // 固定 7 列，按照当前可用宽度平均分配
    final size = (maxWidth - (columns - 1) * spacing) / columns;
    return size;
  }

  Widget _buildImagePreview() {
    if (_newImageBytes.isEmpty) return const SizedBox.shrink();
    final items = <Widget>[];

    // 内存图片
    for (var i = 0; i < _newImageBytes.length; i++) {
      final bytes = _newImageBytes[i];
      items.add(
        Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              width: 60.w,
              height: 60.w,
              decoration: BoxDecoration(
                color: _vscodeCard,
                border: Border.all(color: _vscodeBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
            Positioned(
              top: -6,
              right: -6,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const ImageIcon(
                    AssetImage('assets/images/close.png'),
                    size: 18,
                    color: _vscodeRed,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _removeNewImageBytes(i),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8.w,
      runSpacing: 8.w,
      children: items,
    );
  }

  Widget _buildRecordItem(WorkRecord record) {
    return GestureDetector(
      onLongPress: () => _confirmAndDelete(record),
      child: Card(
        margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        color: _vscodeCard,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _vscodeBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: EdgeInsets.all(8.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (record.content.isNotEmpty)
                Text.rich(
                  TextSpan(children: _parseTextWithLinks(record.content)),
                ),
              if (record.content.isNotEmpty) SizedBox(height: 6.h),
              if (record.imagePaths.isNotEmpty) ...[
                SizedBox(height: 8.h),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final size = _calcImageSize(constraints.maxWidth);
                    return Wrap(
                      spacing: 8.w,
                      runSpacing: 8.w,
                      children: record.imagePaths.asMap().entries.map((entry) {
                        final index = entry.key;
                        final p = entry.value;
                        final file = File(p);
                        return GestureDetector(
                          onTap: () => _showImagePreview(record.imagePaths, index),
                          child: Container(
                            width: size,
                            height: size,
                            decoration: BoxDecoration(
                              color: _vscodePanel,
                              border: Border.all(color: _vscodeBorder),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: file.existsSync()
                                ? Image.file(file, fit: BoxFit.cover)
                                : Container(
                                    color: _vscodePanel,
                                    child: const Center(
                                      child: Icon(Icons.broken_image, color: _vscodeMuted),
                                    ),
                                  ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
              SizedBox(height: 8.h),
              Row(
                children: [
                  if (record.tag.isNotEmpty && record.tag != '未分类') ...[
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: _vscodeAccent.withOpacity(0.15),
                        border: Border.all(color: _vscodeAccent),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        record.tag,
                        style: TextStyle(color: _vscodeAccent, fontSize: 11.sp),
                      ),
                    ),
                    SizedBox(width: 8.w),
                  ],
                  Text(
                    _formatDate(record.createdAt),
                    style: TextStyle(fontSize: 12.sp, color: _vscodeMuted),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: ImageIcon(
                      const AssetImage('assets/images/copy.png'),
                      color: _vscodeText,
                      size: 14.sp,
                    ),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: record.content.trim()),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制文本')),
                        );
                      }
                    },
                    tooltip: '复制',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragOver = true),
      onDragExited: (_) => setState(() => _isDragOver = false),
      onDragDone: (detail) async {
        debugPrint('Drag drop files: ${detail.files.length}');
        final bytesList = await _loadBytesFromDropFiles(detail.files);
        debugPrint('Loaded drop bytes count: ${bytesList.length}');
        _addNewImageBytes(bytesList);
        setState(() => _isDragOver = false);
      },
      child: Container(
        decoration: BoxDecoration(
          color: _isDragOver ? _vscodeAccent.withValues(alpha: 0.12) : _vscodePanel,
          border: const Border(
            top: BorderSide(color: _vscodeBorder),
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Shortcuts(
              shortcuts: <LogicalKeySet, Intent>{
                LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyV): const ActivateIntent(),
                LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyV): const ActivateIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      _handlePasteFromClipboard();
                      return null;
                    },
                  ),
                },
                child: Focus(
                  focusNode: _keyboardFocusNode,
                  autofocus: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_hasDraft)
                        Container(
                          margin: EdgeInsets.only(bottom: 8.h),
                          height: 34.h,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const ClampingScrollPhysics(),
                            itemCount: _tags.length,
                            separatorBuilder: (_, __) => SizedBox(width: 8.w),
                            itemBuilder: (context, index) {
                              final tag = _tags[index];
                              final selected = tag == _activeTag;
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _activeTag = tag;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                                  decoration: BoxDecoration(
                                    color: selected ? _vscodeAccent.withOpacity(0.2) : _vscodeCard,
                                    border: Border.all(color: selected ? _vscodeAccent : _vscodeBorder),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      color: selected ? _vscodeAccent : _vscodeText,
                                      fontSize: 11.sp,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      TextField(
                        controller: _contentController,
                        cursorColor: _vscodeAccent,
                        decoration: InputDecoration(
                          hintText: '输入工作内容（可拖入图片，支持 Ctrl/⌘+V 粘贴图片路径或截图）',
                          hintStyle: TextStyle(
                            color: _vscodeMuted,
                            fontSize: 13.sp,
                            height: 1.4,
                          ),
                          contentPadding: EdgeInsets.all(12.w),
                          enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: _vscodeBorder),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: _vscodeAccent),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: _vscodeCard,
                        ),
                        maxLines: null,
                        minLines: 3,
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(
                          color: _vscodeText,
                          fontSize: 14.sp,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickImages,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _vscodeText,
                    side: const BorderSide(color: _vscodeBorder),
                    backgroundColor: _vscodeCard,
                  ),
                  icon: const Icon(Icons.image, color: _vscodeAccent),
                  label: Text('添加图片', style: TextStyle(fontSize: 12.sp)),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _addRecord,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.send,
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _vscodeAccent,
                    foregroundColor: Colors.white,
                  ),
                  label: Text('保存', style: TextStyle(fontSize: 12.sp)),
                ),
              ],
            ),
            if (_newImageBytes.isNotEmpty) ...[
              SizedBox(height: 8.h),
              _buildImagePreview(),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _vscodeBg,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadWorkRecords,
                    child: _visibleRecords.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(height: 120.h),
                              Center(
                                child: Text(
                                  '还没有工作记录，试着在下方输入并保存吧',
                                  style: TextStyle(
                                    color: _vscodeMuted,
                                    fontSize: 14.sp,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            itemCount: _visibleRecords.length,
                            itemBuilder: (context, index) {
                              return _buildRecordItem(_visibleRecords[index]);
                            },
                          ),
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }
}
