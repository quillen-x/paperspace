import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

const _vscodeBg = Color(0xFF1E1E1E);
const _vscodePanel = Color(0xFF252526);
const _vscodeBorder = Color(0xFF3C3C3C);
const _vscodeText = Color(0xFFD4D4D4);
const _vscodeMuted = Color(0xFF9DA5B4);
const _vscodeAccent = Color(0xFF569CD6);

class ImageViewerWindowApp extends StatelessWidget {
  const ImageViewerWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(1000, 600),
      minTextAdapt: true,
      splitScreenMode: true,
      
      builder: (context, child) {
        return MaterialApp(
          title: '图片查看器',
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: _vscodeBg,
          ),
          home: const ImageViewerPage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key});

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  List<String> _imagePaths = [];
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadImageData();
  }

  Future<void> _loadImageData() async {
    // 从窗口参数中获取图片路径和初始索引
    try {
      final windowController = await WindowController.fromCurrentEngine();
      final argumentsStr = windowController.arguments;
      if (argumentsStr.isNotEmpty) {
        final arguments = jsonDecode(argumentsStr) as Map<String, dynamic>;
        if (arguments['type'] == 'imageViewer') {
          final imagePaths = (arguments['imagePaths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ?? [];
          final initialIndex = arguments['initialIndex'] as int? ?? 0;
          
          setState(() {
            _imagePaths = imagePaths;
            _currentIndex = initialIndex;
          });
          
          if (_imagePaths.isNotEmpty && _currentIndex < _imagePaths.length) {
            _pageController.dispose();
            _pageController = PageController(initialPage: _currentIndex);
            _pageController.addListener(_onPageChanged);
          }
        }
      }
    } catch (e) {
      debugPrint('加载图片数据失败: $e');
    }
  }

  void _onPageChanged() {
    if (_pageController.page != null) {
      setState(() {
        _currentIndex = _pageController.page!.round();
      });
    }
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_imagePaths.isEmpty) {
      return const Scaffold(
        backgroundColor: _vscodeBg,
        body: Center(
          child: Text(
            '没有图片',
            style: TextStyle(color: _vscodeText),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _vscodeBg,
      body: Stack(
        children: [
          // 图片查看器
          PageView.builder(
            controller: _pageController,
            itemCount: _imagePaths.length,
            itemBuilder: (context, index) {
              final path = _imagePaths[index];
              final file = File(path);
              return Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: file.existsSync()
                      ? Image.file(file, fit: BoxFit.contain)
                      : Container(
                          color: _vscodePanel,
                          child: const Center(
                            child: Icon(
                              Icons.broken_image,
                              color: _vscodeMuted,
                              size: 64,
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
          // 顶部信息栏
          // Positioned(
          //   top: MediaQuery.of(context).padding.top + 16.h,
          //   left: 0,
          //   right: 0,
          //   child: SafeArea(
          //     child: Row(
          //       mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //       children: [
          //         Padding(
          //           padding: EdgeInsets.only(left: 16.w),
          //           child: Container(
          //             padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          //             decoration: BoxDecoration(
          //               color: _vscodePanel.withOpacity(0.8),
          //               borderRadius: BorderRadius.circular(8),
          //             ),
          //             child: Text(
          //               '${_currentIndex + 1} / ${_imagePaths.length}',
          //               style: TextStyle(
          //                 color: _vscodeText,
          //                 fontSize: 14.sp,
          //               ),
          //             ),
          //           ),
          //         ),
          //         IconButton(
          //           icon: const Icon(Icons.close, color: _vscodeText),
          //           onPressed: () async {
          //             final windowController = await WindowController.fromCurrentEngine();
          //             windowController.hide();
          //           },
          //           tooltip: '关闭',
          //         ),
          //       ],
          //     ),
          //   ),
          // ),
          // 底部缩略图导航（如果有多张图片）
          if (_imagePaths.length > 1)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 100.h,
                color: _vscodePanel.withOpacity(0.9),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                  itemCount: _imagePaths.length,
                  itemBuilder: (context, index) {
                    final path = _imagePaths[index];
                    final file = File(path);
                    final isSelected = index == _currentIndex;
                    return GestureDetector(
                      onTap: () {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: Container(
                        width: 80.w,
                        height: 80.h,
                        margin: EdgeInsets.symmetric(horizontal: 4.w),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected ? _vscodeAccent : _vscodeBorder,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: file.existsSync()
                            ? Image.file(file, fit: BoxFit.cover)
                            : Container(
                                color: _vscodePanel,
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: _vscodeMuted,
                                    size: 32,
                                  ),
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

