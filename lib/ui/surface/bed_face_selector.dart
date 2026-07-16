import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stl_mesh.dart';
import 'surface_registration.dart';

/// 床面方向枚举
enum BedFaceDirection {
  posX('+X', '右侧面接触床', StlVector3(1, 0, 0)),
  negX('-X', '左侧面接触床', StlVector3(-1, 0, 0)),
  posY('+Y', '后侧面接触床', StlVector3(0, 1, 0)),
  negY('-Y', '前侧面接触床', StlVector3(0, -1, 0)),
  posZ('+Z', '顶面接触床', StlVector3(0, 0, 1)),
  negZ('-Z', '底面接触床', StlVector3(0, 0, -1));

  final String label;
  final String description;
  final StlVector3 normal;

  const BedFaceDirection(this.label, this.description, this.normal);

  /// 获取将此面旋转到 -Z 方向（床面）的变换
  Transform3D getAlignmentTransform(StlBounds bounds) {
    // 目标法向量是 -Z (0, 0, -1)，即床面向上
    const target = StlVector3(0, 0, -1);

    // 如果当前法向量已经是 -Z，不需要旋转
    if ((normal - target).length < 1e-6) {
      return Transform3D.identity();
    }

    // 如果当前法向量是 +Z，需要旋转 180 度
    if ((normal - const StlVector3(0, 0, 1)).length < 1e-6) {
      return Transform3D.centeredRotation(
        sourceCenter: bounds.center,
        targetCenter: bounds.center,
        rotation: [
          1, 0, 0,
          0, -1, 0,
          0, 0, -1,
        ],
      );
    }

    // 其他情况：计算旋转轴和角度
    final axis = StlVector3.cross(normal, target).normalized();
    final angle = math.acos(normal.dot(target).clamp(-1.0, 1.0));

    if (axis.length < 1e-6) {
      // 法向量平行，使用任意垂直轴
      return Transform3D.identity();
    }

    final c = math.cos(angle);
    final s = math.sin(angle);
    final t = 1 - c;

    final rotation = [
      t * axis.x * axis.x + c,
      t * axis.x * axis.y - s * axis.z,
      t * axis.x * axis.z + s * axis.y,
      t * axis.x * axis.y + s * axis.z,
      t * axis.y * axis.y + c,
      t * axis.y * axis.z - s * axis.x,
      t * axis.x * axis.z - s * axis.y,
      t * axis.y * axis.z + s * axis.x,
      t * axis.z * axis.z + c,
    ];

    return Transform3D.centeredRotation(
      sourceCenter: bounds.center,
      targetCenter: bounds.center,
      rotation: rotation,
    );
  }
}

/// 床面方向选择对话框
class BedFaceSelectorDialog extends StatefulWidget {
  final StlMesh mesh;
  final BedFaceDirection? initialDirection;

  const BedFaceSelectorDialog({
    super.key,
    required this.mesh,
    this.initialDirection,
  });

  @override
  State<BedFaceSelectorDialog> createState() => _BedFaceSelectorDialogState();
}

class _BedFaceSelectorDialogState extends State<BedFaceSelectorDialog> {
  late BedFaceDirection _selectedDirection;

  @override
  void initState() {
    super.initState();
    _selectedDirection = widget.initialDirection ?? BedFaceDirection.negZ;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF2C3034),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(child: _buildContent()),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.flip_camera_android, color: Colors.blue, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择床面接触方向',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '指定模型的哪个包围盒面应该接触打印床',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            color: Colors.white60,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final bounds = widget.mesh.bounds;
    final dimensions = {
      'X': bounds.width,
      'Y': bounds.depth,
      'Z': bounds.height,
    };

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard(dimensions),
        const SizedBox(height: 16),
        ...BedFaceDirection.values.map(_buildDirectionOption),
      ],
    );
  }

  Widget _buildInfoCard(Map<String, double> dimensions) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Color(0xFF60A5FA)),
              SizedBox(width: 8),
              Text(
                '模型包围盒尺寸',
                style: TextStyle(
                  color: Color(0xFF60A5FA),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDimensionChip('X', dimensions['X']!, Colors.red),
              _buildDimensionChip('Y', dimensions['Y']!, Colors.green),
              _buildDimensionChip('Z', dimensions['Z']!, Colors.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionChip(String axis, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            axis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${value.toStringAsFixed(1)} mm',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionOption(BedFaceDirection direction) {
    final isSelected = _selectedDirection == direction;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF1E3A5F) : const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? const Color(0xFF3B82F6) : Colors.white10,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedDirection = direction),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? const Color(0xFF3B82F6) : Colors.white24,
                    width: 2,
                  ),
                  color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      direction.label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      direction.description,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _buildDirectionIcon(direction, isSelected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDirectionIcon(BedFaceDirection direction, bool isSelected) {
    IconData icon;
    switch (direction) {
      case BedFaceDirection.posX:
        icon = Icons.arrow_forward;
      case BedFaceDirection.negX:
        icon = Icons.arrow_back;
      case BedFaceDirection.posY:
        icon = Icons.arrow_upward;
      case BedFaceDirection.negY:
        icon = Icons.arrow_downward;
      case BedFaceDirection.posZ:
        icon = Icons.vertical_align_top;
      case BedFaceDirection.negZ:
        icon = Icons.vertical_align_bottom;
    }

    return Icon(
      icon,
      color: isSelected ? const Color(0xFF60A5FA) : Colors.white38,
      size: 24,
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            icon: const Icon(Icons.check, size: 18),
            label: const Text('确认'),
            onPressed: () => Navigator.pop(context, _selectedDirection),
          ),
        ],
      ),
    );
  }
}
