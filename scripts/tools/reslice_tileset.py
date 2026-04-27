#!/usr/bin/env python3
"""
reslice_tileset.py — 智能 Tileset 切片工具（支持非均匀网格）

核心算法:
1. 多阈值渐进扫描，能发现强分隔线(密度<0.08)和弱分隔线(密度<0.5)
2. 相邻分隔像素合并为"分隔带"，tile 区域 = 带与带之间的间隙
3. 大段无内部分隔的区域按期望 tile 尺寸等分
4. 自动检测左侧标签列并跳过
5. 输出检测到的坐标 JSON，方便复用和人工微调

用法:
  python3 reslice_tileset.py <input.png> <output_dir> [--tile-size 24] [--white-threshold 235]
  python3 reslice_tileset.py  # 无参数时使用项目默认路径
"""

import argparse
import json
import os
import sys
from PIL import Image
import numpy as np


# ---------------------------------------------------------------------------
# 1. 标签列检测
# ---------------------------------------------------------------------------
def detect_label_width(arr, threshold=230):
    """检测左侧标签列宽度（标签列通常是低密度文字区）"""
    h, w = arr.shape[:2]
    densities = []
    for c in range(w):
        col = arr[:, c, :3]
        content = np.sum(~np.all(col > threshold, axis=1))
        densities.append(content / h)

    # 5px 窗口平滑
    window = 5
    smoothed = []
    for i in range(len(densities)):
        s = max(0, i - window // 2)
        e = min(len(densities), i + window // 2 + 1)
        smoothed.append(np.mean(densities[s:e]))

    # 找第一段连续高密度区(>0.5)起点，持续5+列
    run = 0
    for c in range(len(smoothed)):
        if smoothed[c] > 0.5:
            run += 1
            if run >= 5:
                label_end = c - run + 1
                while label_end > 0 and smoothed[label_end - 1] > 0.3:
                    label_end -= 1
                return label_end
        else:
            run = 0
    return 0


# ---------------------------------------------------------------------------
# 2. 密度计算
# ---------------------------------------------------------------------------
def compute_row_densities(arr, x_start, x_end, bg_threshold=230):
    """计算每行在 [x_start, x_end) 范围内的内容密度"""
    h = arr.shape[0]
    span = max(1, x_end - x_start)
    densities = np.zeros(h)
    for y in range(h):
        row = arr[y, x_start:x_end, :3]
        content = np.sum(~np.all(row > bg_threshold, axis=1))
        densities[y] = content / span
    return densities


def compute_col_densities(arr, content_rows, bg_threshold=230):
    """计算每列在 content_rows 中的内容密度"""
    w = arr.shape[1]
    n = len(content_rows)
    if n == 0:
        return np.zeros(w)
    densities = np.zeros(w)
    for x in range(w):
        count = 0
        for y in content_rows:
            pixel = arr[y, x, :3]
            if not np.all(pixel > bg_threshold):
                count += 1
        densities[x] = count / n
    return densities


# ---------------------------------------------------------------------------
# 3. 分隔带检测（核心改进）
# ---------------------------------------------------------------------------
def find_separator_bands(densities, start, end, thresholds, band_gap=3,
                         exclude_edges=True):
    """
    多阈值渐进扫描，找到所有分隔带。

    一个"分隔带"是连续若干个低密度像素行/列，代表 tile 之间的间隙。
    用多个递增阈值逐步放宽，能同时捕获强分隔和弱分隔。

    exclude_edges: 排除紧邻区域边缘的分隔带（通常是图片边界，不是真正分隔线）

    返回: [(band_start, band_end), ...] 列表，band_end 是 exclusive。
    """
    # 收集所有阈值下的候选分隔像素
    all_sep_pixels = set()
    for thresh in thresholds:
        for i in range(start, end):
            if densities[i] < thresh:
                all_sep_pixels.add(i)

    if not all_sep_pixels:
        return []

    # 合并相邻像素为带（间距 <= band_gap 视为同一带）
    sorted_pixels = sorted(all_sep_pixels)
    bands = []
    band_start = sorted_pixels[0]
    band_end = sorted_pixels[0]

    for px in sorted_pixels[1:]:
        if px - band_end <= band_gap:
            band_end = px
        else:
            bands.append((band_start, band_end + 1))
            band_start = px
            band_end = px
    bands.append((band_start, band_end + 1))

    if exclude_edges and bands:
        # 排除触及区域末端的带（图片右/下边缘不是分隔线）
        bands = [b for b in bands if b[1] < end]

    # 收缩分隔带：去掉边缘密度较高的像素，只保留核心低密度区
    # 防止把 tile 起始内容误纳入分隔带
    # 使用最严格阈值作为核心标准，高于此值的边缘像素视为 tile 内容
    shrunk = []
    core_threshold = thresholds[0] if thresholds else 0.08
    for bs, be in bands:
        # 从左侧收缩
        while bs < be - 1 and densities[bs] > core_threshold:
            bs += 1
        # 从右侧收缩
        while be > bs + 1 and densities[be - 1] > core_threshold:
            be -= 1
        shrunk.append((bs, be))
    bands = shrunk

    return bands


def bands_to_tile_ranges(bands, region_start, region_end, expected_tile_size):
    """
    从分隔带列表推导 tile 区间。

    tile 区域 = 相邻分隔带之间的间隙。
    对于大间隙（> 1.8 倍 tile 尺寸），按期望尺寸等分。
    对于小间隙（< 0.5 倍 tile 尺寸），视为分隔带的一部分，跳过。
    """
    # 构建间隙列表：[region_start..band0], [band0..band1], ..., [bandN..region_end]
    gaps = []

    # 区域起点到第一个分隔带
    if bands:
        first_gap_end = bands[0][0]
        if first_gap_end > region_start:
            gaps.append((region_start, first_gap_end))

        # 相邻分隔带之间
        for i in range(len(bands) - 1):
            gap_start = bands[i][1]      # 当前带结束
            gap_end = bands[i + 1][0]    # 下一带开始
            if gap_end > gap_start:
                gaps.append((gap_start, gap_end))

        # 最后一个分隔带到区域终点
        last_gap_start = bands[-1][1]
        if region_end > last_gap_start:
            gaps.append((last_gap_start, region_end))
    else:
        gaps.append((region_start, region_end))

    # 将间隙转化为 tile 区间
    ranges = []
    for gs, ge in gaps:
        size = ge - gs
        if size < expected_tile_size * 0.5:
            continue  # 太小，跳过

        if size > expected_tile_size * 1.8:
            # 大段等分
            n = max(1, round(size / expected_tile_size))
            for j in range(n):
                sub_s = gs + int(j * size / n)
                sub_e = gs + int((j + 1) * size / n)
                ranges.append((sub_s, sub_e))
        else:
            ranges.append((gs, ge))

    return ranges


# ---------------------------------------------------------------------------
# 4. 白底透明化
# ---------------------------------------------------------------------------
def make_white_transparent(tile_arr, threshold=235):
    """白色/近白色像素 -> 透明"""
    rgba = np.copy(tile_arr)
    if rgba.shape[2] == 3:
        alpha = np.full((*rgba.shape[:2], 1), 255, dtype=np.uint8)
        rgba = np.concatenate([rgba, alpha], axis=2)

    r, g, b = rgba[:, :, 0], rgba[:, :, 1], rgba[:, :, 2]

    white_mask = (r > threshold) & (g > threshold) & (b > threshold)
    rgba[white_mask, 3] = 0

    near_threshold = threshold - 20
    near_white = (
        (r > near_threshold) & (g > near_threshold) & (b > near_threshold)
        & ~white_mask
    )
    if np.any(near_white):
        brightness = (
            r[near_white].astype(float)
            + g[near_white].astype(float)
            + b[near_white].astype(float)
        ) / 3.0
        alpha_values = (
            (threshold - brightness) / (threshold - near_threshold) * 255
        ).clip(0, 255).astype(np.uint8)
        rgba[near_white, 3] = alpha_values

    return rgba


def is_empty_tile(tile_arr, threshold=235):
    """判断 tile 是否全空白"""
    if tile_arr.shape[2] == 4:
        if np.all(tile_arr[:, :, 3] < 10):
            return True
    rgb = tile_arr[:, :, :3]
    white_ratio = np.sum(np.all(rgb > threshold, axis=2)) / (rgb.shape[0] * rgb.shape[1])
    return white_ratio > 0.95


# ---------------------------------------------------------------------------
# 5. 主流程
# ---------------------------------------------------------------------------
def analyze_and_slice(input_path, output_dir, tile_size=24, white_threshold=235):
    img = Image.open(input_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]
    print(f"Tileset: {w}x{h}")

    # --- 检测标签列 ---
    label_w = detect_label_width(arr)
    content_x = label_w
    print(f"Label width: {label_w}px, content starts at x={content_x}")

    # --- 行分隔带检测 ---
    row_densities = compute_row_densities(arr, content_x, w)

    # 行方向: 分隔线通常很清晰（密度 < 0.08~0.15）
    row_thresholds = [0.08, 0.12, 0.15]
    row_bands = find_separator_bands(row_densities, 0, h, row_thresholds, band_gap=3)
    print(f"\nRow separator bands ({len(row_bands)}):")
    for bs, be in row_bands:
        print(f"  y=[{bs},{be}) width={be - bs}px")

    row_ranges = bands_to_tile_ranges(row_bands, 0, h, tile_size)
    print(f"\nTile rows ({len(row_ranges)}):")
    for i, (rs, re) in enumerate(row_ranges):
        print(f"  r{i:02d}: y=[{rs},{re}) h={re - rs}px")

    # --- 列分隔带检测 ---
    content_rows = [y for y in range(h) if row_densities[y] > 0.1]
    col_densities = compute_col_densities(arr, content_rows)

    # 列方向: 右半清晰(< 0.08)，左半弱分隔需要高阈值(0.5)
    col_thresholds = [0.05, 0.10, 0.15, 0.25, 0.50]
    col_bands = find_separator_bands(col_densities, content_x, w, col_thresholds, band_gap=2)
    print(f"\nCol separator bands ({len(col_bands)}):")
    for bs, be in col_bands:
        print(f"  x=[{bs},{be}) width={be - bs}px")

    col_ranges = bands_to_tile_ranges(col_bands, content_x, w, tile_size)
    print(f"\nTile cols ({len(col_ranges)}):")
    for i, (cs, ce) in enumerate(col_ranges):
        print(f"  c{i:02d}: x=[{cs},{ce}) w={ce - cs}px")

    # --- 输出坐标 JSON ---
    grid_info = {
        "image": os.path.basename(input_path),
        "image_size": [w, h],
        "label_width": label_w,
        "tile_size": tile_size,
        "row_separator_bands": [[int(bs), int(be)] for bs, be in row_bands],
        "col_separator_bands": [[int(bs), int(be)] for bs, be in col_bands],
        "rows": [{"index": i, "y_start": int(rs), "y_end": int(re), "height": int(re - rs)}
                 for i, (rs, re) in enumerate(row_ranges)],
        "cols": [{"index": i, "x_start": int(cs), "x_end": int(ce), "width": int(ce - cs)}
                 for i, (cs, ce) in enumerate(col_ranges)],
    }
    grid_json_path = os.path.join(output_dir, "grid_coords.json")
    os.makedirs(output_dir, exist_ok=True)
    with open(grid_json_path, "w", encoding="utf-8") as f:
        json.dump(grid_info, f, indent=2, ensure_ascii=False)
    print(f"\nGrid coords saved: {grid_json_path}")

    # --- 切片 ---
    saved = 0
    skipped = 0

    for ri, (ry0, ry1) in enumerate(row_ranges):
        row_tiles = []
        for ci, (cx0, cx1) in enumerate(col_ranges):
            ry1_safe = min(ry1, h)
            cx1_safe = min(cx1, w)

            tile_data = arr[ry0:ry1_safe, cx0:cx1_safe].copy()

            if is_empty_tile(tile_data, white_threshold):
                skipped += 1
                continue

            tile_rgba = make_white_transparent(tile_data, white_threshold)

            if tile_rgba.shape[2] == 4 and np.sum(tile_rgba[:, :, 3] > 10) < 5:
                skipped += 1
                continue

            tile_img = Image.fromarray(tile_rgba)
            if tile_img.size != (tile_size, tile_size):
                tile_img = tile_img.resize((tile_size, tile_size), Image.LANCZOS)

            filename = f"tile_r{ri:02d}_c{ci:02d}.png"
            tile_img.save(os.path.join(output_dir, filename))
            saved += 1
            row_tiles.append(f"c{ci:02d}")

        print(f"  r{ri:02d} y=[{ry0},{ry1}) -> {len(row_tiles)} tiles")

    print(f"\n=== Done ===")
    print(f"  Saved: {saved}, Skipped: {skipped}")
    print(f"  Output: {output_dir}/")

    return grid_info


def main():
    parser = argparse.ArgumentParser(description="Smart tileset slicer (non-uniform grid)")
    parser.add_argument("input", nargs="?",
                        default="assets/image/spr_sanguo_map_tileset_20260427103958.png",
                        help="Input tileset image")
    parser.add_argument("output", nargs="?",
                        default="assets/Textures/tiles_sliced",
                        help="Output directory")
    parser.add_argument("--tile-size", type=int, default=24, help="Output tile size (default 24)")
    parser.add_argument("--white-threshold", type=int, default=235, help="White threshold (default 235)")
    args = parser.parse_args()

    analyze_and_slice(args.input, args.output, args.tile_size, args.white_threshold)


if __name__ == "__main__":
    main()
