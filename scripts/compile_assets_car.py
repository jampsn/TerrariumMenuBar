#!/usr/bin/env python3
"""将 Resources/Pixel/*.png 打包为临时 .xcassets 并使用 Xcode actool 编译为 Assets.car（1x 原始像素）"""
import json
import os
import shutil
import subprocess
import sys

ACTOOL = "/Applications/Xcode.app/Contents/Developer/usr/bin/actool"

def main():
    if len(sys.argv) < 3:
        sys.exit("Usage: compile_assets_car.py <pixel_dir> <out_resources_dir>")

    pixel_dir = os.path.abspath(sys.argv[1])
    out_dir = os.path.abspath(sys.argv[2])
    xcassets_dir = "/tmp/terrarium-build/PixelAssets.xcassets"

    if not os.path.exists(ACTOOL):
        sys.exit(f"ERROR: actool not found at {ACTOOL}")

    if os.path.exists(xcassets_dir):
        shutil.rmtree(xcassets_dir)
    os.makedirs(xcassets_dir, exist_ok=True)

    with open(os.path.join(xcassets_dir, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f)

    count = 0
    for fname in sorted(os.listdir(pixel_dir)):
        if not fname.endswith(".png"):
            continue
        name = fname[:-4]
        imgset_dir = os.path.join(xcassets_dir, f"{name}.imageset")
        os.makedirs(imgset_dir, exist_ok=True)
        shutil.copy2(os.path.join(pixel_dir, fname), os.path.join(imgset_dir, fname))
        contents = {
            "images": [
                {"filename": fname, "idiom": "universal", "scale": "1x"}
            ],
            "info": {"author": "xcode", "version": 1},
            "properties": {"compression-type": "lossless"}
        }
        with open(os.path.join(imgset_dir, "Contents.json"), "w") as f:
            json.dump(contents, f)
        count += 1

    os.makedirs(out_dir, exist_ok=True)
    cmd = [
        ACTOOL,
        xcassets_dir,
        "--compile", out_dir,
        "--platform", "macosx",
        "--minimum-deployment-target", "13.0",
        "--warnings", "--errors"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(res.stdout)
        print(res.stderr, file=sys.stderr)
        sys.exit(res.returncode)

    car_path = os.path.join(out_dir, "Assets.car")
    if not os.path.exists(car_path):
        sys.exit("ERROR: Assets.car was not generated")
    print(f"Compiled {count} pixel assets into {car_path} ({os.path.getsize(car_path)} bytes)")

if __name__ == "__main__":
    main()
