import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
  bool _isTagPanelOpen = false;
  Timer? _tagPanelTimer;
  bool _showSearch = false;
  String _searchQuery = '';

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDragOver = false;
  bool _isTagButtonDragging = false;
  bool get _hasDraft => _contentController.text.trim().isNotEmpty || _newImageBytes.isNotEmpty;

  // 标签浮动按钮位置
  Offset _tagButtonPos = Offset.zero;
  bool _tagButtonPosInitialized = false;

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
    _hideTagPanel();
  }

  Widget _buildSideTagPanel() {
    return Positioned(
      right: 16.w,
      bottom: (MediaQuery.of(context).size.height - 320.h) / 2,
      child: MouseRegion(
        onEnter: (_) => _resetTagPanelTimer(),
        onHover: (_) => _resetTagPanelTimer(),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _isTagPanelOpen ? 1 : 0,
          child: IgnorePointer(
            ignoring: !_isTagPanelOpen,
            child: Container(
              width: 180.w,
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: _vscodePanel.withValues(alpha: 0.86),
                border: Border.all(color: _vscodeBorder),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 320.h),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _tags.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: _vscodeBorder),
                      itemBuilder: (context, index) {
                        final tag = _tags[index];
                        final selected = tag == _activeTag;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 0),
                          title: Text(
                            tag,
                            style: TextStyle(
                              color: selected ? _vscodeAccent : _vscodeText,
                              fontSize: 13.sp,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          onTap: () => _selectTag(tag),
                          selected: selected,
                          selectedTileColor: _vscodeAccent.withOpacity(0.12),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingTagButton() {
    const edgePadding = 8.0;
    final btnSize = Size(32.w, 32.h);

    double clamp(double v, double min, double max) {
      if (v < min) return min;
      if (v > max) return max;
      return v;
    }

    return Positioned(
      left: _tagButtonPos.dx,
      top: _tagButtonPos.dy,
      child: GestureDetector(
        onPanStart: (_) {
          setState(() {
            _isTagButtonDragging = true;
          });
        },
        onPanUpdate: (details) {
          setState(() {
            final screenSize = MediaQuery.of(context).size;
            final nx = clamp(
              _tagButtonPos.dx + details.delta.dx,
              edgePadding,
              screenSize.width - btnSize.width - edgePadding,
            );
            final ny = clamp(
              _tagButtonPos.dy + details.delta.dy,
              edgePadding,
              screenSize.height - btnSize.height - edgePadding,
            );
            _tagButtonPos = Offset(nx, ny);
          });
        },
        onPanEnd: (_) {
          setState(() {
            _isTagButtonDragging = false;
          });
        },
        onTap: () {
          setState(() {
            _isTagPanelOpen = true;
          });
          _resetTagPanelTimer();
        },
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: _vscodeAccent.withValues(alpha: _isTagButtonDragging ? 0.4 : 0.1),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(2, 3),
              ),
            ],
          ),
          child: Icon(Icons.local_offer_outlined, color: Colors.white.withValues(alpha: _isTagButtonDragging ? 0.8 : 0.2), size: 14.w),
        ),
      ),
    );
  }

  void _hideTagPanel() {
    _tagPanelTimer?.cancel();
    setState(() {
      _isTagPanelOpen = false;
    });
  }

  void _resetTagPanelTimer() {
    _tagPanelTimer?.cancel();
    _tagPanelTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isTagPanelOpen = false;
        });
      }
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
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_showSearch) ...[
            SizedBox(
              width: 220.w,
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索内容或标签',
                  prefixIcon: const Icon(Icons.search, size: 18, color: _vscodeMuted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16, color: _vscodeMuted),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        )
                      : null,
                  contentPadding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 8.w),
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
                style: TextStyle(color: _vscodeText, fontSize: 12.sp),
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
            icon: Icon(_showSearch ? Icons.close : Icons.search, color: _vscodeText),
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
          IconButton(
            icon: const Icon(Icons.settings, color: _vscodeText),
            tooltip: '设置',
            onPressed: _showSettingsDialog,
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
                                    icon: const Icon(Icons.delete, color: _vscodeRed),
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
    _tagPanelTimer?.cancel();
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
        title: const Text('确认删除'),
        content: const Text('删除后不可恢复，确定删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除', style: TextStyle(color: _vscodeRed)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _deleteWorkRecord(record.id!);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}:'
        '${date.second.toString().padLeft(2, '0')}';
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
                  icon: const Icon(Icons.close, size: 18, color: _vscodeRed),
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
    return Card(
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
              Text(
                record.content,
                style: TextStyle(
                  fontSize: 13.sp,
                  height: 1.5,
                  color: _vscodeText,
                ),
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
                  icon: Icon(Icons.copy, color: _vscodeText, size: 14.sp),
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
                IconButton(
                  icon: Icon(Icons.delete, color: _vscodeRed, size: 14.sp),
                  onPressed: () => _confirmAndDelete(record),
                  tooltip: '删除',
                ),
              ],
            ),
          ],
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
                  label: Text('添加图片', style: TextStyle(fontSize: 14.sp)),
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
                      : const Icon(Icons.send),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _vscodeAccent,
                    foregroundColor: Colors.white,
                  ),
                  label: Text('保存', style: TextStyle(fontSize: 14.sp)),
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
    final screenSize = MediaQuery.of(context).size;
    if (!_tagButtonPosInitialized) {
      _tagButtonPosInitialized = true;
      _tagButtonPos = Offset(
        screenSize.width - 80.w,
        screenSize.height - 220.h,
      );
    }

    return Scaffold(
      backgroundColor: _vscodeBg,
      body: Stack(
        children: [
          Column(
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
          _buildSideTagPanel(),
          _buildFloatingTagButton(),
        ],
      ),
    );
  }
}
