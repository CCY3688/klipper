#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
配准问题诊断工具
"""
import json
import struct
import sys

def read_stl_binary(filename):
    """读取二进制STL文件"""
    with open(filename, 'rb') as f:
        # 跳过80字节头
        f.read(80)
        # 读取三角形数量
        num_triangles = struct.unpack('I', f.read(4))[0]

        triangles = []
        for _ in range(num_triangles):
            # 法向量
            normal = struct.unpack('fff', f.read(12))
            # 三个顶点
            v1 = struct.unpack('fff', f.read(12))
            v2 = struct.unpack('fff', f.read(12))
            v3 = struct.unpack('fff', f.read(12))
            # 属性字节计数（跳过）
            f.read(2)

            triangles.append({
                'normal': normal,
                'vertices': [v1, v2, v3]
            })

    return triangles

def analyze_stl(filename):
    """分析STL模型"""
    print(f"\n=== 分析 STL 模型: {filename} ===")

    triangles = read_stl_binary(filename)
    print(f"三角形数量: {len(triangles)}")

    # 计算包围盒
    all_vertices = []
    for tri in triangles:
        all_vertices.extend(tri['vertices'])

    x_coords = [v[0] for v in all_vertices]
    y_coords = [v[1] for v in all_vertices]
    z_coords = [v[2] for v in all_vertices]

    min_x, max_x = min(x_coords), max(x_coords)
    min_y, max_y = min(y_coords), max(y_coords)
    min_z, max_z = min(z_coords), max(z_coords)

    print(f"\n包围盒:")
    print(f"  X: {min_x:.2f} 到 {max_x:.2f} mm (跨度: {max_x - min_x:.2f} mm)")
    print(f"  Y: {min_y:.2f} 到 {max_y:.2f} mm (跨度: {max_y - min_y:.2f} mm)")
    print(f"  Z: {min_z:.2f} 到 {max_z:.2f} mm (跨度: {max_z - min_z:.2f} mm)")

    # 计算中心
    center_x = (min_x + max_x) / 2
    center_y = (min_y + max_y) / 2
    center_z = (min_z + max_z) / 2
    print(f"\n中心点: ({center_x:.2f}, {center_y:.2f}, {center_z:.2f})")

    # 分析朝上的面
    upward_facing = [tri for tri in triangles if tri['normal'][2] > 0.2]
    print(f"\n朝上的三角形 (normal.z > 0.2): {len(upward_facing)} / {len(triangles)}")

    return {
        'bounds': {'min_x': min_x, 'max_x': max_x, 'min_y': min_y,
                  'max_y': max_y, 'min_z': min_z, 'max_z': max_z},
        'center': (center_x, center_y, center_z),
        'triangles': len(triangles),
        'upward_facing': len(upward_facing)
    }

def analyze_point_cloud(filename):
    """分析点云"""
    print(f"\n=== 分析点云: {filename} ===")

    with open(filename, 'r', encoding='utf-8') as f:
        data = json.load(f)

    points = data['points']
    valid_points = [p for p in points if p['valid']]

    print(f"总点数: {len(points)}")
    print(f"有效点数: {len(valid_points)}")

    x_coords = [p['x'] for p in valid_points]
    y_coords = [p['y'] for p in valid_points]
    z_coords = [p['z'] for p in valid_points]

    print(f"\n点云范围:")
    print(f"  X: {min(x_coords):.1f} 到 {max(x_coords):.1f} mm (跨度: {max(x_coords) - min(x_coords):.1f} mm)")
    print(f"  Y: {min(y_coords):.1f} 到 {max(y_coords):.1f} mm (跨度: {max(y_coords) - min(y_coords):.1f} mm)")
    print(f"  Z: {min(z_coords):.1f} 到 {max(z_coords):.1f} mm (跨度: {max(z_coords) - min(z_coords):.1f} mm)")

    center_x = sum(x_coords) / len(x_coords)
    center_y = sum(y_coords) / len(y_coords)
    center_z = sum(z_coords) / len(z_coords)
    print(f"\n点云中心: ({center_x:.1f}, {center_y:.1f}, {center_z:.1f})")

    # 分析Z值分布
    z_sorted = sorted(z_coords)
    z_median = z_sorted[len(z_sorted) // 2]
    z_p25 = z_sorted[len(z_sorted) // 4]
    z_p75 = z_sorted[3 * len(z_sorted) // 4]

    print(f"\nZ值统计:")
    print(f"  最小值: {min(z_coords):.1f} mm")
    print(f"  25%分位: {z_p25:.1f} mm")
    print(f"  中位数: {z_median:.1f} mm")
    print(f"  75%分位: {z_p75:.1f} mm")
    print(f"  最大值: {max(z_coords):.1f} mm")

    # 识别零件表面（高点）
    threshold = z_median + 10  # 中位数+10mm作为阈值
    surface_points = [(p['x'], p['y'], p['z']) for p in valid_points if p['z'] > threshold]

    if surface_points:
        x_surf = [p[0] for p in surface_points]
        y_surf = [p[1] for p in surface_points]
        z_surf = [p[2] for p in surface_points]

        print(f"\n零件表面点 (Z > {threshold:.1f} mm): {len(surface_points)} 点")
        print(f"  X范围: {min(x_surf):.1f} 到 {max(x_surf):.1f} mm (跨度: {max(x_surf) - min(x_surf):.1f} mm)")
        print(f"  Y范围: {min(y_surf):.1f} 到 {max(y_surf):.1f} mm (跨度: {max(y_surf) - min(y_surf):.1f} mm)")
        print(f"  Z范围: {min(z_surf):.1f} 到 {max(z_surf):.1f} mm")

    return {
        'bounds': {'min_x': min(x_coords), 'max_x': max(x_coords),
                  'min_y': min(y_coords), 'max_y': max(y_coords),
                  'min_z': min(z_coords), 'max_z': max(z_coords)},
        'center': (center_x, center_y, center_z),
        'total_points': len(valid_points)
    }

def compare_scale(stl_info, scan_info):
    """比较尺度"""
    print(f"\n=== 尺度对比 ===")

    stl_bounds = stl_info['bounds']
    scan_bounds = scan_info['bounds']

    stl_x_span = stl_bounds['max_x'] - stl_bounds['min_x']
    stl_y_span = stl_bounds['max_y'] - stl_bounds['min_y']
    stl_z_span = stl_bounds['max_z'] - stl_bounds['min_z']

    scan_x_span = scan_bounds['max_x'] - scan_bounds['min_x']
    scan_y_span = scan_bounds['max_y'] - scan_bounds['min_y']
    scan_z_span = scan_bounds['max_z'] - scan_bounds['min_z']

    print(f"STL 跨度: X={stl_x_span:.1f}, Y={stl_y_span:.1f}, Z={stl_z_span:.1f} mm")
    print(f"点云跨度: X={scan_x_span:.1f}, Y={scan_y_span:.1f}, Z={scan_z_span:.1f} mm")

    # 检查是否可能是旋转了
    print(f"\n可能的匹配:")
    if abs(stl_x_span - scan_x_span) < 20 and abs(stl_y_span - scan_y_span) < 20:
        print(f"  ✓ STL的XY与点云的XY匹配 (不需要旋转)")
    if abs(stl_x_span - scan_y_span) < 20 and abs(stl_y_span - scan_x_span) < 20:
        print(f"  ✓ STL的XY与点云的YX匹配 (需要旋转90度)")

    # 检查尺度因子
    print(f"\n尺度因子:")
    if scan_x_span > 0 and scan_y_span > 0:
        print(f"  STL_X / Scan_X = {stl_x_span / scan_x_span:.3f}")
        print(f"  STL_Y / Scan_Y = {stl_y_span / scan_y_span:.3f}")

if __name__ == '__main__':
    stl_file = '零件1.STL'
    scan_file = 'box.json'

    stl_info = analyze_stl(stl_file)
    scan_info = analyze_point_cloud(scan_file)
    compare_scale(stl_info, scan_info)

    print("\n" + "="*60)
    print("诊断完成")
