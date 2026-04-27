#!/usr/bin/env python3
"""
tileset_slicer.py — Tileset 自动切片 + 白底透明化 一条龙工具

功能:
  1. 自动检测左侧标签列宽度
  2. 自动检测网格尺寸 (tile size)
  3. 按网格切片
  4. 白色/近白背景像素透明化
  5. 跳过全空白 tile
  6. 输出切片报告

用法:
  python3 tileset_slicer.py <input.png> <output_dir> [--tile-size N] [--label-width N] [--white-threshold N]
"""

import argparse
import os
import sys
from PIL import Image
import numpy as np
from collections import Counter


def detect_label_width(arr, threshold=230):
    """
    自动检测左侧标签列宽度。
    策略: 从左向右扫描，找到第一个"内容密度跳变"的位置。
    标签列之后紧跟的是 tile 内容区（内容密度明显更高）。
    """
    h, w = arr.shape[:2]
    densities = []
    for c in range(w):
        col = arr[:, c, :3]
        content = np.sum(~np.all(col > threshold, axis=1))
        densities.append(content / h)

    # 找从低密度到高密度的跳变点
    # 先平滑（5px 窗口）
    window = 5
    smoothed = []
    for i in range(len(densities)):
        start = max(0, i - window // 2)
        end = min(len(densities), i + window // 2 + 1)
        smoothed.append(np.mean(densities[start:end]))

    # 找第一个稳定高密度区域的起点（密度 > 0.5 持续 5+ 列）
    run_count = 0
    for c in range(len(smoothed)):
        if smoothed[c] > 0.5:
            run_count += 1
            if run_count >= 5:
                label_end = c - run_count + 1
                # 向前找最近的低密度列作为边界
                while label_end > 0 and smoothed[label_end - 1] > 0.3:
                    label_end -= 1
                return label_end
        else:
            run_count = 0

    return 0  # 无标签列


def detect_tile_size(arr, content_x, threshold=230):
    """
    自动检测 tile 网格尺寸。
    策略: 在内容区域检测行/列方向上的周期性分隔线。
    """
    h, w = arr.shape[:2]
    content_w = w - content_x

    # === 检测行分隔 ===
    row_content = []
    for r in range(h):
        row = arr[r, content_x:, :3]
        content = np.sum(~np.all(row > threshold, axis=1))
        row_content.append(content / content_w)

    # 找所有低密度行（分隔线候选）
    sep_rows = [r for r in range(h) if row_content[r] < 0.15]

    # 计算相邻分隔线的间距
    row_gaps = []
    for i in range(1, len(sep_rows)):
        gap = sep_rows[i] - sep_rows[i - 1]
        if gap > 5:  # 忽略连续分隔线
            row_gaps.append(gap)

    # === 检测列分隔 ===
    col_content = []
    for c in range(content_x, w):
        col = arr[:, c, :3]
        content = np.sum(~np.all(col > threshold, axis=1))
        col_content.append(content / h)

    sep_cols = [c for c in range(len(col_content)) if col_content[c] < 0.15]

    col_gaps = []
    for i in range(1, len(sep_cols)):
        gap = sep_cols[i] - sep_cols[i - 1]
        if gap > 5:
            col_gaps.append(gap)

    # 统计最常见的间距
    print(f"  行间距统计: {Counter(row_gaps).most_common(5)}")
    print(f"  列间距统计: {Counter(col_gaps).most_common(5)}")

    # 取最常见的间距作为 tile size（行列应该一致）
    all_gaps = row_gaps + col_gaps
    if all_gaps:
        gap_counter = Counter(all_gaps)
        # 找最常见的，且 > 10 的间距
        for gap, count in gap_counter.most_common():
            if gap > 10:
                return gap

    # 回退：尝试常见尺寸
    print("  警告: 无法自动检测，尝试常见尺寸...")
    for size in [24, 25, 16, 32, 20]:
        if content_w % size < 3:
            return size

    return 24  # 默认


def detect_grid(arr, content_x, tile_size, threshold=230):
    """
    精确检测网格起点和每个 tile 的位置。
    返回 (grid_x, grid_y, rows, cols) 列表。
    """
    h, w = arr.shape[:2]

    # 找行方向的分隔线组
    row_content = []
    for r in range(h):
        row = arr[r, content_x:, :3]
        content = np.sum(~np.all(row > threshold, axis=1))
        row_content.append(content / (w - content_x))

    # 找列方向的分隔线
    col_content = []
    for c in range(content_x, w):
        col = arr[:, c, :3]
        content = np.sum(~np.all(col > threshold, axis=1))
        col_content.append(content / h)

    # 用分隔线定位 tile 行
    # 找所有分隔行（连续低密度行合并为一组）
    sep_mask = [row_content[r] < 0.15 for r in range(h)]
    tile_row_ranges = []
    in_tile = False
    tile_start = 0

    for r in range(h):
        if not sep_mask[r]:  # 有内容的行
            if not in_tile:
                tile_start = r
                in_tile = True
        else:  # 分隔行
            if in_tile:
                tile_end = r
                height = tile_end - tile_start
                if height >= tile_size * 0.7:  # 至少是 tile 高度的 70%
                    tile_row_ranges.append((tile_start, tile_end))
                in_tile = False
    if in_tile:
        tile_end = h
        height = tile_end - tile_start
        if height >= tile_size * 0.7:
            tile_row_ranges.append((tile_start, tile_end))

    # 用分隔线定位 tile 列
    sep_col_mask = [col_content[c] < 0.15 for c in range(len(col_content))]
    tile_col_ranges = []
    in_tile = False

    for c in range(len(sep_col_mask)):
        if not sep_col_mask[c]:
            if not in_tile:
                tile_start = c + content_x
                in_tile = True
        else:
            if in_tile:
                tile_end = c + content_x
                width = tile_end - tile_start
                if width >= tile_size * 0.7:
                    tile_col_ranges.append((tile_start, tile_end))
                in_tile = False
    if in_tile:
        tile_end = w
        width = tile_end - tile_start
        if width >= tile_size * 0.7:
            tile_col_ranges.append((tile_start, tile_end))

    return tile_row_ranges, tile_col_ranges


def make_white_transparent(tile_arr, threshold=235):
    """
    将白色/近白色像素转为透明。
    策略: RGB 三通道都 > threshold 的像素，alpha 设为 0。
    对于边缘半白像素做渐变处理。
    """
    rgba = np.copy(tile_arr)

    # 确保是 RGBA
    if rgba.shape[2] == 3:
        alpha = np.full((*rgba.shape[:2], 1), 255, dtype=np.uint8)
        rgba = np.concatenate([rgba, alpha], axis=2)

    r, g, b = rgba[:, :, 0], rgba[:, :, 1], rgba[:, :, 2]

    # 完全白色 → 完全透明
    white_mask = (r > threshold) & (g > threshold) & (b > threshold)
    rgba[white_mask, 3] = 0

    # 半白色（接近但不完全白） → 半透明（渐变过渡，避免锯齿）
    near_threshold = threshold - 20
    near_white = (
        (r > near_threshold) & (g > near_threshold) & (b > near_threshold)
        & ~white_mask
    )
    if np.any(near_white):
        # 计算"白色程度"：三通道平均值越高越白
        brightness = (r[near_white].astype(float) + g[near_white].astype(float) + b[near_white].astype(float)) / 3.0
        # 线性映射: near_threshold → alpha=255, threshold → alpha=0
        alpha_values = ((threshold - brightness) / (threshold - near_threshold) * 255).clip(0, 255).astype(np.uint8)
        rgba[near_white, 3] = alpha_values

    return rgba


def is_empty_tile(tile_arr, threshold=235):
    """判断 tile 是否为全空白（全白/透明）"""
    if tile_arr.shape[2] == 4:
        # RGBA: 检查是否全透明或全白
        alpha = tile_arr[:, :, 3]
        if np.all(alpha < 10):
            return True

    rgb = tile_arr[:, :, :3]
    white_ratio = np.sum(np.all(rgb > threshold, axis=2)) / (rgb.shape[0] * rgb.shape[1])
    return white_ratio > 0.95


def slice_tileset(input_path, output_dir, tile_size=None, label_width=None,
                  white_threshold=235, padding=0):
    """主切片流程"""
    print(f"=== Tileset Slicer ===")
    print(f"输入: {input_path}")
    print(f"输出: {output_dir}")

    # 加载图片
    img = Image.open(input_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]
    print(f"图片尺寸: {w}x{h}")

    # 1. 检测标签列宽度
    if label_width is None:
        label_width = detect_label_width(arr)
        print(f"自动检测标签列宽度: {label_width}px")
    else:
        print(f"手动指定标签列宽度: {label_width}px")

    content_x = label_width

    # 2. 检测 tile 尺寸
    if tile_size is None:
        print("自动检测 tile 尺寸...")
        tile_size = detect_tile_size(arr, content_x)
        print(f"检测到 tile 尺寸: {tile_size}x{tile_size}")
    else:
        print(f"手动指定 tile 尺寸: {tile_size}x{tile_size}")

    # 3. 检测网格位置
    print("检测网格位置...")
    tile_row_ranges, tile_col_ranges = detect_grid(arr, content_x, tile_size)
    print(f"  发现 {len(tile_row_ranges)} 个行区域, {len(tile_col_ranges)} 个列区域")

    for i, (rs, re) in enumerate(tile_row_ranges):
        print(f"  行 {i}: y={rs}-{re} (高度={re - rs}px, ~{(re - rs) / tile_size:.1f} tiles)")
    for i, (cs, ce) in enumerate(tile_col_ranges):
        print(f"  列 {i}: x={cs}-{ce} (宽度={ce - cs}px, ~{(ce - cs) / tile_size:.1f} tiles)")

    # 4. 切片
    os.makedirs(output_dir, exist_ok=True)
    total_tiles = 0
    empty_tiles = 0
    saved_tiles = 0

    tile_manifest = []

    for ri, (row_start, row_end) in enumerate(tile_row_ranges):
        row_height = row_end - row_start
        # 这一行可能包含多个 sub-tile 行
        n_sub_rows = max(1, round(row_height / tile_size))

        for ci, (col_start, col_end) in enumerate(tile_col_ranges):
            col_width = col_end - col_start
            n_sub_cols = max(1, round(col_width / tile_size))

            for sr in range(n_sub_rows):
                for sc in range(n_sub_cols):
                    # 计算精确的 sub-tile 坐标
                    sy = row_start + int(sr * row_height / n_sub_rows)
                    ey = row_start + int((sr + 1) * row_height / n_sub_rows)
                    sx = col_start + int(sc * col_width / n_sub_cols)
                    ex = col_start + int((sc + 1) * col_width / n_sub_cols)

                    # 裁剪 tile
                    tile_data = arr[sy:ey, sx:ex].copy()
                    total_tiles += 1

                    # 跳过空白 tile
                    if is_empty_tile(tile_data, white_threshold):
                        empty_tiles += 1
                        continue

                    # 白底透明化
                    tile_rgba = make_white_transparent(tile_data, white_threshold)

                    # 检查透明化后是否还有内容
                    if tile_rgba.shape[2] == 4 and np.sum(tile_rgba[:, :, 3] > 10) < 5:
                        empty_tiles += 1
                        continue

                    # 保存
                    tile_img = Image.fromarray(tile_rgba)
                    abs_row = ri * n_sub_rows + sr  # 绝对行索引（用于标记地形类型）
                    abs_col = ci * n_sub_cols + sc
                    filename = f"tile_r{abs_row:02d}_c{abs_col:02d}.png"
                    filepath = os.path.join(output_dir, filename)
                    tile_img.save(filepath)
                    saved_tiles += 1

                    tile_manifest.append({
                        "file": filename,
                        "row": abs_row,
                        "col": abs_col,
                        "src_rect": [sx, sy, ex - sx, ey - sy],
                        "size": [tile_img.width, tile_img.height],
                    })

    # 5. 输出报告
    print(f"\n=== 切片报告 ===")
    print(f"  扫描 tile 总数: {total_tiles}")
    print(f"  空白跳过: {empty_tiles}")
    print(f"  有效切片: {saved_tiles}")
    print(f"  输出目录: {output_dir}")

    # 按行分组报告
    row_groups = {}
    for t in tile_manifest:
        r = t["row"]
        if r not in row_groups:
            row_groups[r] = []
        row_groups[r].append(t)

    print(f"\n  按行分组:")
    for r in sorted(row_groups.keys()):
        tiles = row_groups[r]
        print(f"    行 {r}: {len(tiles)} tiles → {[t['file'] for t in tiles]}")

    return tile_manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Tileset 自动切片 + 白底透明化")
    parser.add_argument("input", help="输入 tileset 图片路径")
    parser.add_argument("output", help="输出切片目录")
    parser.add_argument("--tile-size", type=int, default=None, help="指定 tile 尺寸 (默认自动检测)")
    parser.add_argument("--label-width", type=int, default=None, help="指定左侧标签列宽度 (默认自动检测)")
    parser.add_argument("--white-threshold", type=int, default=235, help="白色阈值 (默认 235)")
    args = parser.parse_args()

    slice_tileset(args.input, args.output,
                  tile_size=args.tile_size,
                  label_width=args.label_width,
                  white_threshold=args.white_threshold)
