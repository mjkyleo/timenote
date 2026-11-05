#!/usr/bin/env python3
"""从 assets/icon/timenote-launcher-icon-1024.png 生成各平台启动图标。

用法（本机 Python 3.11 + Pillow）：
    py tool/make_icons.py

尺寸不是随手定的：Android 按 mdpi 48 / hdpi 72 / xhdpi 96 / xxhdpi 144 / xxxhdpi 192
（Google 的 launcher icon 规范），鸿蒙那两个沿用 DevEco 模板的 144x144。
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "icon", "timenote-launcher-icon-1024.png")

ANDROID_DPI = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
OHOS_TARGETS = [
    os.path.join("ohos", "entry", "src", "main", "resources", "base", "media", "icon.png"),
    os.path.join("ohos", "AppScope", "resources", "base", "media", "app_icon.png"),
]

if not os.path.exists(SRC):
    sys.exit(f"找不到源图：{SRC}")

square = Image.open(SRC).convert("RGBA")
side = min(square.size)
square = square.crop(
    (
        (square.width - side) // 2,
        (square.height - side) // 2,
        (square.width + side) // 2,
        (square.height + side) // 2,
    )
)

for dpi, px in ANDROID_DPI.items():
    out_dir = os.path.join(ROOT, "android", "app", "src", "main", "res", f"mipmap-{dpi}")
    os.makedirs(out_dir, exist_ok=True)
    square.resize((px, px), Image.LANCZOS).save(os.path.join(out_dir, "ic_launcher.png"))
    print(f"android  mipmap-{dpi}/ic_launcher.png  {px}x{px}")

for rel in OHOS_TARGETS:
    path = os.path.join(ROOT, rel)
    px = Image.open(path).size[0]
    square.resize((px, px), Image.LANCZOS).save(path)
    print(f"ohos     {rel}  {px}x{px}")
