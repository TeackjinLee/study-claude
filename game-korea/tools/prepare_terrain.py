#!/usr/bin/env python3
"""서울 지형 높이 그림 → data/terrain/seoul.tres (TerrainMap).

그림(output/imagegen/terrain/seoul_height.png)은 도시 블록 격자(가로 11 × 세로 17칸, 위가 북쪽)에 맞춘 흑백 높이 지도다.
그림은 잠실(동쪽 확장, 블록 x 6~8) 전의 지도(IMG_MAX)만 덮는다 — 그 동쪽은 평지(0)로 채운다.
칸 경계 선 = 도로 한가운데. 검정 = 가장 낮은 곳, 흰색 = 가장 높은 곳.
CELL(월드 192px — 교차로 상자 한 변)마다 밝기를 0~1로 읽어 적는다. 강가를 낮추고 고가를 평평하게 하는 것은 게임(Terrain)이 한다.

    python3 tools/prepare_terrain.py [그림] [--debug]
"""
import sys
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "output/imagegen/terrain/seoul_height.png"
OUT = ROOT / "data/terrain/seoul.tres"

# City / CityMap 수치 (scripts/world/city.gd·city_map.gd)
ROAD = 192.0
PITCH = 768.0
MIN = (-5, -11)
MAX = (8, 5)
IMG_MAX = (5, 5)     # 높이 그림이 덮는 동쪽 끝 블록 (그 너머는 평지)
CELL = 192.0
BLUR = 0.18          # 블러 반지름 (칸 크기 배수) — 생성 그림의 얼룩을 고른다
# 높이 조절 값 (TerrainMap). 이미 .tres에 있으면 그 값을 지킨다
TUNING = {"max_height": "190.0", "contrast": "1.8", "shore_fall": "700.0", "flat_fall": "420.0", "shading": "2.0",
          # 남산(타워 블록 북동 모서리) · 북악(변두리 북동) · 관악 끝자락(강남·공단 남쪽 끝)
          "hills": "Array[Vector3]([Vector3(3, -5.9, 1.7), Vector3(3.6, -10.6, 1.8), Vector3(2, 6.6, 3)])",
          "forests": "Array[Vector2i]([Vector2i(1, -6), Vector2i(3, -6), Vector2i(3, -11), Vector2i(4, -11)])"}


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    src = Path(args[0]) if args else SRC
    im = Image.open(src).convert("L")
    cols = IMG_MAX[0] - MIN[0] + 1
    rows = IMG_MAX[1] - MIN[1] + 1
    cw = im.width / cols
    ch = im.height / rows
    # 칸 경계 선(1~2px 밝은 회색)을 지운 뒤 고른다 — 남으면 도로마다 둑이 솟는다
    im = im.filter(ImageFilter.MedianFilter(7))
    im = im.filter(ImageFilter.GaussianBlur(BLUR * (cw + ch) * 0.5))
    px = im.load()

    def sample(x: float, y: float) -> float:
        x = min(max(x, 0.0), im.width - 1.001)
        y = min(max(y, 0.0), im.height - 1.001)
        x0, y0 = int(x), int(y)
        fx, fy = x - x0, y - y0
        a = px[x0, y0] * (1 - fx) + px[x0 + 1, y0] * fx
        b = px[x0, y0 + 1] * (1 - fx) + px[x0 + 1, y0 + 1] * fx
        return (a * (1 - fy) + b * fy) / 255.0

    per = int(PITCH / CELL)
    nx = (MAX[0] + 2 - MIN[0]) * per + 1
    ny = (MAX[1] + 2 - MIN[1]) * per + 1
    origin = (MIN[0] * PITCH, MIN[1] * PITCH)
    values = []
    for j in range(ny):
        for i in range(nx):
            wx = origin[0] + i * CELL
            wy = origin[1] + j * CELL
            # 그림 칸 경계 선 = 도로 한가운데 (교차로 MIN + k의 중심)
            gx = ((wx - ROAD * 0.5) / PITCH - MIN[0]) * cw
            gy = ((wy - ROAD * 0.5) / PITCH - MIN[1]) * ch
            values.append(sample(gx, gy) if wx <= (IMG_MAX[0] + 2) * PITCH else 0.0)

    nums = ", ".join("%.4f" % v for v in values)
    tuning = dict(TUNING)
    if OUT.exists():
        for line in OUT.read_text(encoding="utf-8").splitlines():
            key, _, val = line.partition(" = ")
            if key in tuning:
                tuning[key] = val
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        '[gd_resource type="Resource" script_class="TerrainMap" load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="res://scripts/world/terrain_map.gd" id="1"]\n\n'
        "[resource]\n"
        'script = ExtResource("1")\n'
        "origin = Vector2(%g, %g)\n"
        "cell = %g\n"
        "size = Vector2i(%d, %d)\n"
        "values = PackedFloat32Array(%s)\n" % (origin[0], origin[1], CELL, nx, ny, nums)
        + "".join("%s = %s\n" % kv for kv in tuning.items()),
        encoding="utf-8")
    print("%s ← %s (%d×%d)" % (OUT.relative_to(ROOT), src.name, nx, ny))
    if "--debug" in sys.argv:
        dbg = Image.new("L", (nx, ny))
        dbg.putdata([int(v * 255) for v in values])
        path = ROOT / "output/imagegen/terrain/seoul_height_debug.png"
        dbg.resize((nx * 8, ny * 8), Image.NEAREST).save(path)
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
