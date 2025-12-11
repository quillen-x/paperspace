import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/work_record.dart';

class AddEditRecordPage extends StatefulWidget {
  final WorkRecord? record;

  const AddEditRecordPage({super.key, this.record});

  @override
  State<AddEditRecordPage> createState() => _AddEditRecordPageState();
}

class _AddEditRecordPageState extends State<AddEditRecordPage> {
  final _formKey = GlobalKey<FormState>();
  final _contentController = TextEditingController();
  final _dbHelper = DatabaseHelper.instance;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.record != null) {
      _contentController.text = widget.record!.content;
      _selectedDate = widget.record!.date;
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // 选择日期
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('zh', 'CN'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // 保存工作记录
  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();
      final record = WorkRecord(
        id: widget.record?.id,
        content: _contentController.text.trim(),
        date: now,
        createdAt: widget.record?.createdAt ?? now,
        imagePaths: widget.record?.imagePaths ?? [],
        tag: widget.record?.tag ?? '未分类',
      );

      if (widget.record == null) {
        await _dbHelper.insertWorkRecord(record);
      } else {
        await _dbHelper.updateWorkRecord(record);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.record == null ? '添加成功' : '更新成功'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
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

  // 格式化日期显示
  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.record == null ? '添加工作记录' : '编辑工作记录'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _saveRecord,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 日期选择
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: '日期',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDate(_selectedDate)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 内容输入
            TextFormField(
              controller: _contentController,
              
              decoration: const InputDecoration(
                labelText: '工作内容',
                hintText: '请输入详细的工作内容...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,

              ),
              maxLines: null,
              minLines: 10,
              maxLength: 2000,
              textInputAction: TextInputAction.newline,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入工作内容';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // 保存按钮
            ElevatedButton(
              onPressed: _isSaving ? null : _saveRecord,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '保存',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
