import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klipper/state/printer_controller.dart';
import 'package:klipper/state/printcart_controller.dart';
import 'package:klipper/data/printcart/printcart_serial_service.dart';
import 'package:klipper/ui/coating/coating_page.dart';
import 'package:provider/provider.dart';

void main() {
  Future<void> pumpPage(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PrinterController()),
          ChangeNotifierProvider(
            create: (_) => PrintcartController(transport: _NoopTransport()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(body: CoatingPage()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the desktop acceptance controls', (tester) async {
    await pumpPage(tester, const Size(1280, 900));

    expect(find.text('联合运动状态'), findsOneWidget);
    expect(find.text('双舵机姿态'), findsOneWidget);
    expect(find.text('俯仰 Pitch 舵机'), findsOneWidget);
    expect(find.text('偏航 Yaw 舵机'), findsOneWidget);
    expect(find.text('上抬 50°'), findsOneWidget);
    expect(find.text('水平 80°'), findsOneWidget);
    expect(find.text('下垂 180°'), findsOneWidget);
    expect(find.text('+X / A 臂 30°'), findsOneWidget);
    expect(find.text('应用全部姿态'), findsOneWidget);
    expect(find.text('释放全部 PWM'), findsOneWidget);
    expect(find.text('XYZ + 舵机联合运动'), findsOneWidget);
    expect(find.text('联合执行'), findsOneWidget);
    expect(find.text('喷头连接'), findsOneWidget);
    expect(find.text('静态单喷嘴测试'), findsOneWidget);
    expect(find.text('喷嘴健康记录'), findsOneWidget);
    expect(find.text('急停'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without overflow at a narrow viewport', (tester) async {
    await pumpPage(tester, const Size(620, 900));

    expect(find.text('联合运动状态'), findsOneWidget);
    expect(find.text('连续下发'), findsOneWidget);
    expect(find.text('舵机先到位'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _NoopTransport implements PrintcartTransport {
  @override
  bool get isConnected => false;
  @override
  Stream<String> get events => const Stream.empty();
  @override
  Future<String> command(
    String command, {
    Duration timeout = const Duration(seconds: 2),
  }) => throw StateError('not connected');
  @override
  Future<void> connect(String portName) async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<List<PrintcartPortInfo>> listPorts() async => const [];
}
