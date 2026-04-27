#!/usr/bin/env python3
"""
根据 Tiled 翻转标记生成翻转后的瓦片 PNG。

Tiled 翻转标记含义（参考 Tiled 文档）：
- H (水平翻转): 左右镜像
- V (垂直翻转): 上下镜像
- D (对角翻转): 沿主对角线(左上-右下)转置

组合翻转的变换矩阵（Tiled 文档定义）：
- H:    水平翻转
- V:    垂直翻转
- D:    对角转置（沿主对角线翻转，等效于转置）
- HV:   旋转180度
- HD:   顺时针旋转90度
- VD:   逆时针旋转90度
- HVD:  顺时针旋转90度 + 垂直翻转（等效于反对角线翻转）
"""

from PIL import Image
import os

SRC_DIR = "/workspace/assets/Textures/tiles_sliced"
DST_DIR = SRC_DIR  # 输出到同一目录

# 需要生成的翻转列表: (row, col, flip_combo)
FLIPS = [
    (4, 1, "hd"),
    (4, 1, "hvd"),
    (4, 1, "v"),
    (4, 1, "vd"),
    (5, 2, "hvd"),
    (6, 1, "d"),
    (6, 2, "hd"),
    (6, 2, "vd"),
    (8, 4, "hv"),
    (8, 4, "vd"),
]


def apply_tiled_flip(img, combo):
    """
    按照 Tiled 的翻转标记规则变换图片。
    
    Tiled 的变换顺序是：先对角翻转(D)，再水平翻转(H)，再垂直翻转(V)。
    但更直觉的理解是用组合结果：
    - H:    左右镜像
    - V:    上下镜像  
    - D:    转置（沿左上-右下对角线）
    - HV:   180度旋转
    - HD:   顺时针90度
    - VD:   逆时针90度
    - HVD:  逆时针90度 + 水平翻转 = 反对角线翻转
    """
    combo = combo.lower()
    
    if combo == "h":
        return img.transpose(Image.FLIP_LEFT_RIGHT)
    elif combo == "v":
        return img.transpose(Image.FLIP_TOP_BOTTOM)
    elif combo == "d":
        # 对角翻转 = 转置 = 逆时针90度 + 水平翻转
        return img.transpose(Image.TRANSPOSE)
    elif combo == "hv":
        # 旋转180度
        return img.transpose(Image.ROTATE_180)
    elif combo == "hd":
        # 顺时针90度
        return img.transpose(Image.ROTATE_270)
    elif combo == "vd":
        # 逆时针90度
        return img.transpose(Image.ROTATE_90)
    elif combo == "hvd":
        # 反对角线翻转(TRANSVERSE) = 顺时针90度 + 垂直翻转
        return img.transpose(Image.TRANSVERSE)
    else:
        print(f"  警告: 未知翻转组合 '{combo}'，返回原图")
        return img


def main():
    generated = 0
    for row, col, combo in FLIPS:
        src_name = f"tile_r{row:02d}_c{col:02d}.png"
        dst_name = f"tile_r{row:02d}_c{col:02d}_{combo}.png"
        src_path = os.path.join(SRC_DIR, src_name)
        dst_path = os.path.join(DST_DIR, dst_name)

        if not os.path.exists(src_path):
            print(f"  跳过: {src_name} 不存在")
            continue

        img = Image.open(src_path)
        flipped = apply_tiled_flip(img, combo)
        flipped.save(dst_path)
        print(f"  生成: {dst_name} ({combo.upper()} 翻转)")
        generated += 1

    print(f"\n完成! 共生成 {generated} 个翻转瓦片")


if __name__ == "__main__":
    main()
