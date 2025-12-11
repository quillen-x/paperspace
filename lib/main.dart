import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:window_manager/window_manager.dart';

import 'pages/home_page.dart';
import 'pages/image_viewer_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 获取当前窗口控制器，并解析启动参数决定启动哪个窗口
  final currentWindow = await WindowController.fromCurrentEngine();
  final windowArgs = _parseWindowArgs(currentWindow.arguments);

  if (windowArgs.type == WindowType.imageViewer) {
    await windowManager.ensureInitialized();
    const windowOptions1 = WindowOptions(
      size: Size(1000, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    windowManager.waitUntilReadyToShow(windowOptions1, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    runApp(const ImageViewerWindowApp());
    return;
  }

  // 主窗口启动
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(400, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const MyApp());
}

enum WindowType { main, imageViewer }

class WindowArgs {
  final WindowType type;
  final Map<String, dynamic> data;
  const WindowArgs(this.type, this.data);
}

WindowArgs _parseWindowArgs(String? args) {
  if (args == null || args.isEmpty) {
    return const WindowArgs(WindowType.main, {});
  }
  try {
    final decoded = jsonDecode(args) as Map<String, dynamic>;
    final typeStr = decoded['type'] as String? ?? '';
    final type = typeStr == 'imageViewer' ? WindowType.imageViewer : WindowType.main;
    return WindowArgs(type, decoded);
  } catch (_) {
    return const WindowArgs(WindowType.main, {});
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(400, 800),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: '工作记录',
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'SanJiLuoLiHei',
            colorScheme: const ColorScheme.dark(
              brightness: Brightness.dark,
              primary: Color(0xFF569CD6),
              secondary: Color(0xFF4EC9B0),
              surface: Color(0xFF252526),
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onSurface: Color(0xFFD4D4D4),
            ),
            scaffoldBackgroundColor: const Color(0xFF1E1E1E),
            cardColor: const Color(0xFF2D2D2D),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF252526),
              foregroundColor: Color(0xFFD4D4D4),
              elevation: 0,
            ),
            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Color(0xFF2D2D2D),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF3C3C3C)),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF3C3C3C)),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF569CD6)),
              ),
              labelStyle: TextStyle(color: Color(0xFF9DA5B4)),
              hintStyle: TextStyle(color: Color(0xFF9DA5B4)),
            ),
            snackBarTheme: const SnackBarThemeData(
              backgroundColor: Color(0xFF252526),
              contentTextStyle: TextStyle(color: Color(0xFFD4D4D4)),
            ),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(color: Color(0xFFD4D4D4)),
              bodySmall: TextStyle(color: Color(0xFF9DA5B4)),
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF252526)),
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          home: const HomePage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
