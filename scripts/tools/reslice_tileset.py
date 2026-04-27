#!/usr/bin/env python3
"""
reslice_tileset.py — 基于手工标注坐标的精确切片工具

原始 tileset 网格不均匀，自动检测失败。
此脚本使用人工标注的精确像素边界进行切片。
"""

import os
import sys
from PIL import Image
import numpy as np

# ===== 手工标注的精确坐标 =====
# Row boundaries: (y_start, y_end_exclusive)
# 分析依据: 行分隔线在 y=0,24,48,73-76,103-104,134,160,182-186
ROW_BOUNDS = [
    (1,   24),   # r00: 草地A  (23px)
    (25,  48),   # r01: 草地B  (23px)
    (49,  73),   # r02: 森林   (24px)
    (77, 103),   # r03: 山脉   (26px)
    (105, 134),  # r04: 水域   (29px)
    (135, 160),  # r05: 农田   (25px)
    (161, 182),  # r06: 城池   (21px)
    (187, 209),  # r07: 桥梁   (22px)
    (210, 232),  # r08: 道路   (22px)
    (233, 255),  # r09: 沙地   (22px)
]

# Column boundaries: (x_start, x_end_exclusive)
# 分析依据: 列分隔线在 x=32,57,81,105,130,155,180,205,230
COL_BOUNDS = [
    (9,   32),   # c00  (23px, 弱分隔)
    (33,  57),   # c01  (24px, 弱分隔)
    (58,  81),   # c02  (23px, 弱分隔)
    (82, 105),   # c03  (23px, 弱分隔)
    (106, 130),  # c04  (24px)
    (131, 155),  # c05  (24px)
    (156, 180),  # c06  (24px)
    (181, 205),  # c07  (24px)
    (206, 230),  # c08  (24px)
]

OUTPUT_SIZE = 24  # 统一输出尺寸


def make_white_transparent(tile_arr, threshold=235):
    """白色/近白色像素 -> 透明"""
    rgba = np.copy(tile_arr)
    if rgba.shape[2] == 3:
        alpha = np.full((*rgba.shape[:2], 1), 255, dtype=np.uint8)
        rgba = np.concatenate([rgba, alpha], axis=2)

    r, g, b = rgba[:, :, 0], rgba[:, :, 1], rgba[:, :, 2]

    # 完全白 -> 完全透明
    white_mask = (r > threshold) & (g > threshold) & (b > threshold)
    rgba[white_mask, 3] = 0

    # 半白 -> 渐变透明
    near_threshold = threshold - 20
    near_white = (
        (r > near_threshold) & (g > near_threshold) & (b > near_threshold)
        & ~white_mask
    )
    if np.any(near_white):
        brightness = (r[near_white].astype(float) + g[near_white].astype(float) + b[near_white].astype(float)) / 3.0
        alpha_values = ((threshold - brightness) / (threshold - near_threshold) * 255).clip(0, 255).astype(np.uint8)
        rgba[near_white, 3] = alpha_values

    return rgba


def is_empty_tile(tile_arr, threshold=235):
    """判断 tile 是否全空白"""
    if tile_arr.shape[2] == 4:
        alpha = tile_arr[:, :, 3]
        if np.all(alpha < 10):
            return True
    rgb = tile_arr[:, :, :3]
    white_ratio = np.sum(np.all(rgb > threshold, axis=2)) / (rgb.shape[0] * rgb.shape[1])
    return white_ratio > 0.95


def main():
    input_path = "assets/image/spr_sanguo_map_tileset_20260427103958.png"
    output_dir = "assets/Textures/tiles_sliced"

    if not os.path.exists(input_path):
        print(f"ERROR: input not found {input_path}")
        sys.exit(1)

    img = Image.open(input_path).convert("RGBA")
    arr = np.array(img)
    h, w = arr.shape[:2]
    print(f"Tileset: {w}x{h}")
    print(f"Rows: {len(ROW_BOUNDS)}, Cols: {len(COL_BOUNDS)}")
    print(f"Output size: {OUTPUT_SIZE}x{OUTPUT_SIZE}")
    print()

    os.makedirs(output_dir, exist_ok=True)

    saved = 0
    skipped = 0

    for ri, (ry0, ry1) in enumerate(ROW_BOUNDS):
        row_tiles = []
        for ci, (cx0, cx1) in enumerate(COL_BOUNDS):
            ry1_safe = min(ry1, h)
            cx1_safe = min(cx1, w)

            tile_data = arr[ry0:ry1_safe, cx0:cx1_safe].copy()

            if is_empty_tile(tile_data):
                skipped += 1
                continue

            tile_rgba = make_white_transparent(tile_data)

            if tile_rgba.shape[2] == 4 and np.sum(tile_rgba[:, :, 3] > 10) < 5:
                skipped += 1
                continue

            tile_img = Image.fromarray(tile_rgba)
            if tile_img.size != (OUTPUT_SIZE, OUTPUT_SIZE):
                tile_img = tile_img.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.LANCZOS)

            filename = f"tile_r{ri:02d}_c{ci:02d}.png"
            filepath = os.path.join(output_dir, filename)
            tile_img.save(filepath)
            saved += 1
            row_tiles.append(f"c{ci:02d}({cx1-cx0}px)")

        print(f"  r{ri:02d} y=[{ry0},{ry1}) h={ry1-ry0}px -> {len(row_tiles)} tiles: {', '.join(row_tiles)}")

    print(f"\n=== Done ===")
    print(f"  Saved: {saved}")
    print(f"  Skipped: {skipped}")
    print(f"  Output: {output_dir}/")


if __name__ == "__main__":
    main()
