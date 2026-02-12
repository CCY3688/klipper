import 'package:flutter/material.dart';

import 'sample_collection_page.dart';

/// 风格学习工作台
///
/// 在同一界面中整合：
/// 1. 图像采集（采集 + 预处理预览）
/// 2. 完整流程（图像编辑 + 字符分割 + 骨架分析）
class StyleLearningWorkspacePage extends StatefulWidget {
  const StyleLearningWorkspacePage({super.key});

  @override
  State<StyleLearningWorkspacePage> createState() => _StyleLearningWorkspacePageState();
}

class _StyleLearningWorkspacePageState extends State<StyleLearningWorkspacePage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          decoration: BoxDecoration(
            color: theme.cardColor,
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '图像采集',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const Expanded(child: SampleCollectionPage(embedded: true)),
      ],
    );
  }
}
