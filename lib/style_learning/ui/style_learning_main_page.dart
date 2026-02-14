import 'package:flutter/material.dart';
import 'sample_collection_page.dart';
import 'style_transfer_page.dart';
import '../services/style_model_manager.dart';

/// 风格学习主页面
/// 
/// 统一入口，整合所有功能
class StyleLearningMainPage extends StatefulWidget {
  const StyleLearningMainPage({super.key});

  @override
  State<StyleLearningMainPage> createState() => _StyleLearningMainPageState();
}

class _StyleLearningMainPageState extends State<StyleLearningMainPage> {
  final StyleModelManager _modelManager = StyleModelManager();
  
  List<StyleModelMetadata> _styleModels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      final models = await _modelManager.listStyles();
      setState(() {
        _styleModels = models;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('手写风格学习'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 功能入口卡片
                  _buildFeatureCards(),
                  const SizedBox(height: 24),

                  // 已保存的风格模型
                  _buildSavedModels(),
                ],
              ),
            ),
    );
  }

  Widget _buildFeatureCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '功能',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FeatureCard(
                icon: Icons.camera_alt,
                title: '采集样本',
                description: '拍照或选择手写图片\n系统自动提取书写风格',
                color: Colors.blue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SampleCollectionPage(),
                    ),
                  ).then((_) => _loadModels());
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FeatureCard(
                icon: Icons.style,
                title: '风格迁移',
                description: '将您的书写风格\n应用到任意汉字',
                color: Colors.green,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StyleTransferPage(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSavedModels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '已保存的风格',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (_styleModels.isNotEmpty)
              TextButton(
                onPressed: _loadModels,
                child: const Text('刷新'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_styleModels.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.folder_open, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  '暂无保存的风格',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  '请先采集手写样本并分析风格',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _styleModels.length,
            itemBuilder: (context, index) {
              final model = _styleModels[index];
              return _StyleModelCard(
                model: model,
                onDelete: () => _deleteModel(model.name),
                onExport: () => _exportModel(model.name),
              );
            },
          ),
      ],
    );
  }

  Future<void> _deleteModel(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除风格 "$name" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _modelManager.deleteStyle(name);
      _loadModels();
    }
  }

  Future<void> _exportModel(String name) async {
    try {
      final json = await _modelManager.exportStyle(name);
      
      // 显示导出结果（实际应用中可以分享或保存文件）
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('导出成功'),
            content: SingleChildScrollView(
              child: SelectableText(
                json,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleModelCard extends StatelessWidget {
  final StyleModelMetadata model;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  const _StyleModelCard({
    required this.model,
    required this.onDelete,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.style),
        ),
        title: Text(model.name),
        subtitle: Text(
          '${model.sampleCount} 个样本 · ${_formatDate(model.createdAt)}',
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 8),
                  Text('导出'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('删除', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'export') onExport();
            if (value == 'delete') onDelete();
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}