#!/usr/bin/env python3
"""한강 물 그림 다듬기: GPT가 그린 물 무늬·호안 그림을 게임용 이음매 없는 타일로 만든다.

  output/imagegen/water/river_tile.png  → assets/water/river_tile.png  (512×512, 상하좌우 이음매 없음)
  output/imagegen/water/river_bank.png  → assets/water/river_bank.png  (높이 256, 좌우 이음매 없음, 위 = 땅 쪽)

- 생성기는 이음매를 잘 못 맞춘다 → 반 칸 민 그림과 가장자리를 섞어 이음매를 지운다.
- 그림 전체의 밝기 얼룩(가운데가 밝은 비네팅 등)은 크게 흐린 그림으로 나눠 고르게 편다 — 반복될 때 큰 얼룩이 줄지어 보이지 않게.
- 마젠타 배경이 섞여 왔으면 실패로 본다(물 그림은 화면을 꽉 채워야 한다).

사용: python3 tools/prepare_water_textures.py [--debug]   (--debug: 2×2로 이어 붙인 확인 그림을 output/imagegen/water/debug/에)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "output/imagegen/water"
DST = ROOT / "assets/water"


def flatten(a: np.ndarray, radius: float) -> np.ndarray:
    """큰 밝기 얼룩을 편다: 흐린 그림으로 나누고 평균 밝기를 곱한다"""
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    blur = np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32) + 1.0
    return a / blur * a.reshape(-1, 3).mean(axis=0)


def seamless(a: np.ndarray, axes: tuple) -> np.ndarray:
    """반 칸 민 그림과 섞어 가장자리를 잇는다 (가운데는 원본, 가장자리로 갈수록 민 그림)"""
    h, w = a.shape[:2]
    rolled = a.copy()
    m = np.ones((h, w), dtype=np.float32)
    if 1 in axes:
        rolled = np.roll(rolled, w // 2, axis=1)
        x = np.abs(np.linspace(-1.0, 1.0, w))
        m *= np.clip((1.0 - x) / 0.35, 0.0, 1.0)[None, :]
    if 0 in axes:
        rolled = np.roll(rolled, h // 2, axis=0)
        y = np.abs(np.linspace(-1.0, 1.0, h))
        m *= np.clip((1.0 - y) / 0.35, 0.0, 1.0)[:, None]
    m = m[..., None]
    return a * m + rolled * (1.0 - m)


def magenta_share(a: np.ndarray) -> float:
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return float(((r > 200) & (b > 200) & (g < 80)).mean())


def load(name: str):
    p = SRC / name
    if not p.exists():
        print(f"{name}: 없음 — 건너뜀")
        return None
    a = np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)
    if magenta_share(a) > 0.01:
        print(f"{name}: 마젠타 배경이 섞였다 — 화면을 꽉 채운 물 그림으로 다시 받는다")
        return None
    return a


def save(a: np.ndarray, name: str, size, debug: bool, tile_xy) -> None:
    DST.mkdir(parents=True, exist_ok=True)
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).resize(size, Image.LANCZOS)
    img.save(DST / name)
    print(f"{name}: {size[0]}×{size[1]} → {DST / name}")
    if debug:
        d = SRC / "debug"
        d.mkdir(exist_ok=True)
        tx, ty = tile_xy
        sheet = Image.new("RGB", (size[0] * tx, size[1] * ty))
        for y in range(ty):
            for x in range(tx):
                sheet.paste(img, (x * size[0], y * size[1]))
        sheet.save(d / name.replace(".png", "_tiled.png"))


def main() -> None:
    debug = "--debug" in sys.argv
    a = load("river_tile.png")
    if a is not None:
        a = flatten(a, a.shape[1] / 5.0)
        a = seamless(a, (0, 1))
        save(a, "river_tile.png", (512, 512), debug, (2, 2))
    b = load("river_bank.png")
    if b is not None:
        # 호안은 위아래(땅 → 물)로 밝기가 변해야 하니 가로로만 편다
        h, w = b.shape[:2]
        b = seamless(b, (1,))
        height = 256
        save(b, "river_bank.png", (round(w * height / h), height), debug, (3, 1))


if __name__ == "__main__":
    main()
