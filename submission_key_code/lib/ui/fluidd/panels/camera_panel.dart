import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/camera_viewer_controller.dart';
import '../widgets/fluidd_card.dart';

class CameraPanel extends StatefulWidget {
  const CameraPanel({super.key});

  @override
  State<CameraPanel> createState() => _CameraPanelState();
}

class _CameraPanelState extends State<CameraPanel> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _pythonCtrl;

  @override
  void initState() {
    super.initState();
    final c = context.read<CameraViewerController>();
    _urlCtrl = TextEditingController(text: c.baseUrl);
    _pythonCtrl = TextEditingController(text: c.pythonExecutable);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _pythonCtrl.dispose();
    super.dispose();
  }

  String _humanAge(DateTime? ts) {
    if (ts == null) return '--';
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 1) return '刚刚';
    return '${diff.inSeconds} 秒前';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraViewerController>(
      builder: (context, c, _) {
        if (_urlCtrl.text != c.baseUrl && !_urlCtrl.selection.isValid) {
          _urlCtrl.text = c.baseUrl;
        }
        if (_pythonCtrl.text != c.pythonExecutable &&
            !_pythonCtrl.selection.isValid) {
          _pythonCtrl.text = c.pythonExecutable;
        }

        final statusColor = c.running ? Colors.greenAccent : Colors.grey;
        final serviceColor = c.serviceRunning
            ? Colors.greenAccent
            : c.serviceStarting
            ? Colors.orangeAccent
            : Colors.grey;
        final errorText = c.lastError;
        final serviceError = c.serviceError;
        final nonce = c.nonce;
        final frameBytes = c.frameBytes;

        return FluiddCard(
          title: '相机画面',
          subtitle: c.running ? '实时' : '已停止',
          scrollable: false,
          actions: [
            IconButton(
              tooltip: '检查摄像头服务',
              icon: const Icon(
                Icons.health_and_safety_outlined,
                color: Colors.grey,
                size: 20,
              ),
              onPressed: c.probeService,
            ),
            IconButton(
              tooltip: c.serviceRunning ? '停止摄像头服务' : '启动摄像头服务',
              icon: Icon(
                c.serviceRunning
                    ? Icons.power_settings_new
                    : Icons.video_call_outlined,
                color: c.serviceRunning ? Colors.orangeAccent : Colors.blue,
                size: 20,
              ),
              onPressed: c.serviceStarting
                  ? null
                  : c.serviceRunning
                  ? c.stopCameraService
                  : c.startCameraService,
            ),
            IconButton(
              tooltip: '刷新一帧',
              icon: const Icon(Icons.refresh, color: Colors.grey, size: 20),
              onPressed: c.refresh,
            ),
            IconButton(
              tooltip: c.running ? '停止实时预览' : '启动实时预览',
              icon: Icon(
                c.running
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outlined,
                color: c.running ? Colors.orangeAccent : Colors.blue,
                size: 20,
              ),
              onPressed: c.running ? c.stop : c.start,
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: '预览服务地址',
                        labelStyle: TextStyle(color: Colors.white54),
                        isDense: true,
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white12),
                        ),
                      ),
                      onSubmitted: c.setBaseUrl,
                      onTapOutside: (_) => c.setBaseUrl(_urlCtrl.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => c.setBaseUrl(_urlCtrl.text),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('应用'),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: '恢复默认地址',
                    onPressed: () {
                      c.resetBaseUrl();
                      _urlCtrl.text = CameraViewerController.defaultBaseUrl;
                    },
                    icon: const Icon(Icons.restore_outlined, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pythonCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Python 解释器',
                        labelStyle: TextStyle(color: Colors.white54),
                        isDense: true,
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white12),
                        ),
                      ),
                      onSubmitted: c.setPythonExecutable,
                      onTapOutside: (_) =>
                          c.setPythonExecutable(_pythonCtrl.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => c.setPythonExecutable(_pythonCtrl.text),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('应用'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF101316),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white12),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (frameBytes != null)
                        Image.memory(
                          frameBytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        )
                      else
                        Center(
                          child: Icon(
                            errorText == null
                                ? Icons.videocam_outlined
                                : Icons.videocam_off_outlined,
                            color: Colors.white24,
                            size: 56,
                          ),
                        ),
                      if (c.loading)
                        const Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Text(
                              errorText == null
                                  ? c.lastFrameAt == null
                                        ? '等待图像'
                                        : '帧 #$nonce'
                                  : '取图失败',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            child: Text(
                              c.running ? '运行中' : '已停止',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (errorText != null)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.68),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orangeAccent),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Text(
                                errorText,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (serviceError != null)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: errorText == null ? 12 : 82,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.68),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orangeAccent),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              child: Text(
                                serviceError,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: c.running ? Icons.play_arrow : Icons.pause,
                    label: c.running ? '自动刷新已开启' : '自动刷新已关闭',
                    color: statusColor,
                  ),
                  _InfoChip(
                    icon: c.serviceRunning
                        ? Icons.videocam_outlined
                        : Icons.videocam_off_outlined,
                    label: c.serviceStarting
                        ? '摄像头服务启动中'
                        : c.serviceRunning
                        ? '摄像头服务运行中'
                        : '摄像头服务未启动',
                    color: serviceColor,
                  ),
                  _InfoChip(
                    icon: Icons.schedule_outlined,
                    label: _humanAge(c.lastFrameAt),
                    color: Colors.blueAccent,
                  ),
                  _InfoChip(
                    icon: Icons.timer_outlined,
                    label: '${c.refreshMs} ms',
                    color: Colors.orangeAccent,
                  ),
                  _InfoChip(
                    icon: Icons.link_outlined,
                    label: c.normalizedBaseUrl,
                    color: Colors.lightBlueAccent,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: c.serviceStarting
                        ? null
                        : c.serviceRunning
                        ? c.stopCameraService
                        : c.startCameraService,
                    icon: Icon(
                      c.serviceRunning
                          ? Icons.power_settings_new
                          : Icons.video_call_outlined,
                      size: 18,
                    ),
                    label: Text(c.serviceRunning ? '停止摄像头服务' : '启动摄像头服务'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: c.running ? c.stop : c.start,
                    icon: Icon(
                      c.running ? Icons.stop : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(c.running ? '停止预览' : '启动预览'),
                  ),
                  OutlinedButton.icon(
                    onPressed: c.refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('刷新'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        c.setRefreshMs(c.refreshMs <= 200 ? 400 : 200),
                    icon: const Icon(Icons.speed_outlined, size: 18),
                    label: Text('${c.refreshMs} ms'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Switch(
                    value: c.autoStart,
                    onChanged: c.setAutoStart,
                    activeThumbColor: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '自动启动预览',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
