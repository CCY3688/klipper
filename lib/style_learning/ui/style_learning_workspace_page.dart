import 'package:flutter/material.dart';

import '../services/style_model_manager.dart';
import 'sample_collection_page.dart';
import 'style_transfer_page.dart';

/// 风格学习工作台
///
/// 整合完整的风格学习流程：
/// 1. 图像采集与校准
/// 2. 预处理 → 字符分割 → 骨架提取  
/// 3. 基于骨架的风格分析
/// 4. 风格迁移与应用
class StyleLearningWorkspacePage extends StatefulWidget {
  const StyleLearningWorkspacePage({super.key});

  @override
  State<StyleLearningWorkspacePage> createState() => _StyleLearningWorkspacePageState();
}

class _StyleLearningWorkspacePageState extends State<StyleLearningWorkspacePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final StyleModelManager _modelManager = StyleModelManager();
  List<StyleModelMetadata> _styleModels = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadModels();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final models = await _modelManager.listStyles();
      if (mounted) {
        setState(() => _styleModels = models);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '风格学习',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: '采集分析', icon: Icon(Icons.camera_alt, size: 18)),
                  Tab(text: '已保存风格', icon: Icon(Icons.style, size: 18)),
                  Tab(text: '风格迁移', icon: Icon(Icons.transform, size: 18)),
                ],
                labelStyle: const TextStyle(fontSize: 12),
                onTap: (_) => _loadModels(),
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: 采集与分析
              const SampleCollectionPage(embedded: true),
              // Tab 2: 已保存的风格模型
              _buildSavedModelsTab(),
              // Tab 3: 风格迁移
              const StyleTransferPage(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSavedModelsTab() {
    if (_styleModels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('暂无保存的风格模型', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text('请先采集手写样本并分析风格', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
              onPressed: _loadModels,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadModels,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _styleModels.length,
        itemBuilder: (context, index) {
          final model = _styleModels[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.style)),
              title: Text(model.name),
              subtitle: Text(
                '${model.sampleCount} 个样本 · ${model.createdAt.month}/${model.createdAt.day} ${model.createdAt.hour}:${model.createdAt.minute.toString().padLeft(2, '0')}',
              ),
              trailing: PopupMenuButton(
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'export',
                    child: Row(children: [Icon(Icons.share, size: 20), SizedBox(width: 8), Text('导出')]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [Icon(Icons.delete, size: 20, color: Colors.red), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))]),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'export') {
                    try {
                      final json = await _modelManager.exportStyle(model.name);
                      if (mounted) {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('导出成功'),
                            content: SingleChildScrollView(
                              child: SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                            ),
                            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
                      }
                    }
                  } else if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('确认删除'),
                        content: Text('确定要删除风格 "${model.name}" 吗？'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _modelManager.deleteStyle(model.name);
                      _loadModels();
                    }
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }
}