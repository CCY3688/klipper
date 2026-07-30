import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
//数据可能需要在多个页面显示。Provider 就像一个“全局广播站”，当数据更新时，所有订阅了这个数据的页面都会自动刷新。

import 'state/printer_controller.dart';
import 'state/navigation_controller.dart';
import 'state/paper_config_controller.dart';
import 'state/settings_controller.dart';
import 'state/camera_viewer_controller.dart';
import 'state/parameter_calibration_controller.dart';
import 'state/user_font_controller.dart';
import 'state/printcart_controller.dart';
import 'ui/connection_page.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PrinterController()),
        ChangeNotifierProvider(create: (_) => NavigationController()),
        ChangeNotifierProvider(create: (_) => PaperConfigController()),
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(create: (_) => CameraViewerController()),
        ChangeNotifierProvider(create: (_) => ParameterCalibrationController()),
        ChangeNotifierProvider(create: (_) => UserFontController()),
        ChangeNotifierProvider(create: (_) => PrintcartController()),
      ],
      //将控制器 PrinterController 和 NavigationController "挂"在了整个 App 的顶层，任何页面都可以通过 Provider 访问它们。
      child: const MyApp(),
    ),
  );
}
// main.dart 是 Flutter 应用的入口文件，负责启动应用并设置全局状态管理（Provider）。
//它将 PrinterController 作为一个 ChangeNotifierProvider 提供给整个应用，使得任何页面都可以访问和监听 PrinterController 中的数据变化。

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智绘随形',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        //useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF181A1B),
        cardColor: const Color(0xFF2C3034),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blue,
          surface: Color(0xFF212529),
        ),
      ),
      home: const ConnectionPage(),
    );
  }
}
