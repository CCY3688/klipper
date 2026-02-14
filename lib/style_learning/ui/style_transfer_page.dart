import 'package:flutter/material.dart';
import '../models/character_data.dart';
import '../models/stroke_trajectory.dart';
import '../models/style_vector.dart';
import '../services/style_transfer.dart';
import '../services/style_model_manager.dart';
import '../../writing/font/stroke_font.dart';

/// 风格迁移页面
class StyleTransferPage extends StatefulWidget {
  const StyleTransferPage({super.key});

  @override
  State<StyleTransferPage> createState() => _StyleTransferPageState();
}

class _StyleTransferPageState extends State<StyleTransferPage> {
  final StyleModelManager _modelManager = StyleModelManager();
  final TextEditingController _charactersController =
      TextEditingController(text: '永丕');

  List<StyleModelMetadata> _styleModels = [];
  StyleVector? _selectedStyle;
  String? _selectedModelName;
  StrokeFont? _strokeFont;

  // 测试用的标准字符
  final List<CharacterData> _testCharacters = [];

  // 转换后的字符
  List<CharacterData> _transformedCharacters = [];

  // 风格参数
  double _intensity = 1.0;
  double _randomness = 0.1;

  bool _isLoading = false;
  bool _isLoadingChars = false;

  @override
  void initState() {
    super.initState();
    _loadStyleModels();
    _loadTestCharacters();
  }

  @override
  void dispose() {
    _charactersController.dispose();
    super.dispose();
  }

  Future<void> _loadStyleModels() async {
    setState(() => _isLoading = true);

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

  List<String> _parseCharactersInput(String raw) {
    final compact = raw.replaceAll(RegExp(r'[\s,，;；、]+'), '');
    final result = <String>[];
    final seen = <String>{};
    for (final rune in compact.runes) {
      final ch = String.fromCharCode(rune);
      if (seen.add(ch)) {
        result.add(ch);
      }
    }
    return result;
  }

  Future<void> _loadTestCharacters([String? value]) async {
    final targets = _parseCharactersInput(value ?? _charactersController.text);
    if (targets.isEmpty) {
      if (!mounted) return;
      setState(() {
        _testCharacters.clear();
        _transformedCharacters = [];
      });
      return;
    }

    setState(() => _isLoadingChars = true);

    try {
      final font = _strokeFont ??
          await StrokeFont.loadFromAsset('assets/fonts/makemeahanzi_standard.json');
      _strokeFont = font;
      final loaded = <CharacterData>[];

      for (final ch in targets) {
        final glyph = font.richGlyphOf(ch);
        if (glyph == null || glyph.strokes.isEmpty) continue;

        final strokes = glyph.strokes.map((stroke) {
          final medians = stroke.points
              .map((p) => [
                    (p.x * 1024).round().clamp(0, 1024),
                    // 关于水平线镜像：y -> 1 - y
                    ((1.0 - p.y) * 1024).round().clamp(0, 1024),
                  ])
              .toList();

          final path = StringBuffer();
          if (medians.isNotEmpty) {
            path.write('M ${medians.first[0]} ${medians.first[1]} ');
            for (int i = 1; i < medians.length; i++) {
              path.write('L ${medians[i][0]} ${medians[i][1]} ');
            }
            path.write('Z');
          }

          return StrokeTrajectory(
            svgPath: path.toString(),
            medians: medians,
          );
        }).toList();

        loaded.add(CharacterData(character: ch, strokes: strokes));
      }

      if (!mounted) return;
      setState(() {
        _testCharacters
          ..clear()
          ..addAll(loaded);
        _transformedCharacters = [];
        _isLoadingChars = false;
      });
      _applyTransfer();
    } catch (_) {
      if (!mounted) return;
      // 回退：至少保证页面可用
      setState(() {
        _testCharacters
          ..clear()
          ..addAll([
            CharacterData.fromLibraryJson({
              'character': '永',
              'strokes': ['M 500 224 L 500 624 Z'],
              'medians': [
                [
                  [500, 224],
                  [500, 324],
                  [500, 424],
                  [500, 524],
                  [500, 624]
                ]
              ],
            }),
            CharacterData.fromLibraryJson({
              'character': '丕',
              'strokes': ['M 220 324 L 810 304 Z'],
              'medians': [
                [
                  [220, 324],
                  [350, 319],
                  [500, 314],
                  [650, 309],
                  [810, 304]
                ]
              ],
            }),
          ]);
        _transformedCharacters = [];
        _isLoadingChars = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('风格迁移'),
      ),
      body: Row(
        children: [
          // 左侧：风格选择和参数
          SizedBox(
            width: 300,
            child: _buildControlPanel(),
          ),
          const VerticalDivider(width: 1),
          // 右侧：预览
          Expanded(
            child: _buildPreviewPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        // 测试字符输入
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '测试字符列表',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _charactersController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '输入字符，如：永丕中水火',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (value) => _loadTestCharacters(value),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoadingChars
                      ? null
                      : () => _loadTestCharacters(_charactersController.text),
                  icon: _isLoadingChars
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_isLoadingChars ? '加载中...' : '更新字符'),
                ),
              ),
            ],
          ),
        ),
        const Divider(),

        // 风格模型选择
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择风格模型',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_styleModels.isEmpty)
                const Text(
                  '暂无风格模型，请先采集样本并分析风格',
                  style: TextStyle(color: Colors.grey),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _selectedModelName,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  items: _styleModels.map((model) {
                    return DropdownMenuItem(
                      value: model.name,
                      child: Text(model.name),
                    );
                  }).toList(),
                  onChanged: (name) {
                    if (name != null) {
                      _loadStyle(name);
                    }
                  },
                ),
            ],
          ),
        ),
        const Divider(),

        // 参数调节
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '风格参数',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // 强度
              Row(
                children: [
                  const SizedBox(width: 80, child: Text('强度')),
                  Expanded(
                    child: Slider(
                      value: _intensity,
                      min: 0,
                      max: 2,
                      divisions: 20,
                      label: _intensity.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() => _intensity = value);
                        _applyTransfer();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(_intensity.toStringAsFixed(1)),
                  ),
                ],
              ),

              // 随机性
              Row(
                children: [
                  const SizedBox(width: 80, child: Text('随机性')),
                  Expanded(
                    child: Slider(
                      value: _randomness,
                      min: 0,
                      max: 1,
                      divisions: 20,
                      label: _randomness.toStringAsFixed(2),
                      onChanged: (value) {
                        setState(() => _randomness = value);
                        _applyTransfer();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(_randomness.toStringAsFixed(2)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(),

        // 风格信息
            if (_selectedStyle != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '风格信息',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _InfoItem(
                      '样本数量',
                      '${_selectedStyle!.sampleCount} 个字符',
                    ),
                    _InfoItem(
                      '倾斜角度',
                      '${(_selectedStyle!.global.avgSlantAngle * 180 / 3.14159).toStringAsFixed(1)}°',
                    ),
                    _InfoItem(
                      '高宽比',
                      _selectedStyle!.global.avgAspectRatio.toStringAsFixed(2),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    if (_isLoadingChars) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_testCharacters.isEmpty) {
      return const Center(child: Text('无测试字符，请先输入字符并点击“更新字符”'));
    }

    return Column(
      children: [
        // 标题
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '原始字符',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  '风格化后',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),

        // 字符对比
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _testCharacters.length,
            itemBuilder: (context, index) {
              final original = _testCharacters[index];
              final transformed = index < _transformedCharacters.length
                  ? _transformedCharacters[index]
                  : null;

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                height: 200,
                child: Row(
                  children: [
                    // 原始字符
                    Expanded(
                      child: _CharacterPreview(
                        character: original,
                        color: Colors.grey,
                        label: original.character,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 箭头
                    Icon(
                      Icons.arrow_forward,
                      color: _selectedStyle != null
                          ? Colors.blue
                          : Colors.grey[300],
                    ),
                    const SizedBox(width: 16),
                    // 风格化字符
                    Expanded(
                      child: transformed != null
                          ? _CharacterPreview(
                              character: transformed,
                              color: Colors.blue,
                              label: '${transformed.character} (风格化)',
                            )
                          : Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Text(
                                  '请选择风格模型',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _loadStyle(String name) async {
    try {
      final style = await _modelManager.loadStyle(name);
      if (!mounted) return;
      setState(() {
        _selectedModelName = name;
        _selectedStyle = style;
      });
      _applyTransfer();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('加载失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _applyTransfer() {
    if (_selectedStyle == null) return;

    final transfer = StyleTransfer(
      intensity: _intensity,
      randomness: _randomness,
    );

    setState(() {
      _transformedCharacters = _testCharacters
          .map((c) => transfer.transfer(c, _selectedStyle!))
          .toList();
    });
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value),
        ],
      ),
    );
  }
}

class _CharacterPreview extends StatelessWidget {
  final CharacterData character;
  final Color color;
  final String label;

  const _CharacterPreview({
    required this.character,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _CharacterPainter(character, color),
              size: Size.infinite,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(8),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterPainter extends CustomPainter {
  final CharacterData character;
  final Color color;

  _CharacterPainter(this.character, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 计算缩放（按较小边，避免裁切）
    final base = (size.width < size.height ? size.width : size.height);
    final scale = base / 1024 * 0.8;
    final drawSize = 1024 * scale;
    final offsetX = (size.width - drawSize) / 2;
    final offsetY = (size.height - drawSize) / 2;

    for (final stroke in character.strokes) {
      if (stroke.medians.isEmpty) continue;

      final path = Path();

      for (int i = 0; i < stroke.medians.length; i++) {
        final point = stroke.medians[i];
        final x = point[0] * scale + offsetX;
        final y = (1024 - point[1]) * scale + offsetY;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}