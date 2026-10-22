#!/usr/bin/env python3
"""받은 폭발·불 효과 넘김 그림(output/imagegen/fx/*.png)을 게임 그림(assets/fx/)으로 다듬는다.
요청 규칙·가이드는 output/imagegen/fx/GPT_EXPLOSION_PROMPT.md, 가이드 좌표는 guides/fx_guides.json.

  python3 tools/prepare_fx_sprites.py [이름 ...] [--debug]

- 시트를 가이드 칸 배치(4×4·4×2·2×2)대로 고르게 잘라 칸마다 CELL px로 줄인다. 생성기가 가이드대로 그려서
  칸 안 자리(바닥 점·커지는 크기)를 그대로 둔다 — 칸마다 덩어리를 다시 맞추면 커지고 떠오르는 움직임이 사라진다.
- 불(검정 배경): 가장 밝은 채널을 불투명도로 보고 색을 그만큼 나눈다 — 보통 섞기로 그려도 검정 위에 더한 것과 같다.
- 연기·그을음(마젠타 배경): 빨강·파랑이 초록보다 높은 만큼 배경이 섞인 것으로 보고 반투명으로 푼다.
- 칸마다 덩어리 크기를 재서 assets/fx/fx.json에 적는다 (게임 FireFx가 크기·바닥 점을 맞춘다).
- --debug: output/imagegen/fx/<이름>_debug.png (회색 바둑판 위에 얹어 본다)
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "output/imagegen/fx"
OUT = ROOT / "assets/fx"
GUIDE = SRC / "guides/fx_guides.json"
CELL = 256
SOLID = 0.3   ## 덩어리 크기를 잴 때 이 불투명도 넘는 곳만


def unmix_black(rgb: np.ndarray) -> np.ndarray:
    """검정 위에 그린 빛 → RGBA (불투명도 = 가장 밝은 채널, 색은 그만큼 나눠 원래 밝기로)"""
    c = rgb.astype(np.float64)
    a = c.max(axis=2)
    a = np.where(a < 10, 0.0, a)   # 압축 잡티
    k = np.maximum(a, 1.0)[..., None] / 255.0
    col = np.clip(c / k, 0, 255)
    return np.dstack([col, a]).astype(np.uint8)


def unmix_magenta(rgb: np.ndarray) -> np.ndarray:
    """마젠타 위에 그린 무채색·갈색 → RGBA (빨강·파랑의 낮은 쪽이 초록보다 높은 만큼 배경)"""
    c = rgb.astype(np.float64)
    e = np.clip((np.minimum(c[..., 0], c[..., 2]) - c[..., 1]) / 245.0, 0.0, 1.0)
    keep = np.maximum(1.0 - e, 0.05)[..., None]
    col = np.clip((c - e[..., None] * np.array([255.0, 0.0, 255.0])) / keep, 0, 255)
    # 옅은 곳은 배경을 덜 빼거나 더 빼서 초록·분홍 기운이 남는다 — 연기는 무채색이라 초록이 빨강·파랑을 넘지 않게
    col[..., 1] = np.minimum(col[..., 1], (col[..., 0] + col[..., 2]) / 2 + 4)
    a = 255.0 * (1.0 - e)
    a = np.where(a < 12, 0.0, a)
    return np.dstack([col, a]).astype(np.uint8)


def char_tone(rgba: np.ndarray) -> np.ndarray:
    """그을음: 생성기가 바깥을 분홍빛 밝은 황토로 그렸다 — 밝기만 남겨 탄 갈색으로, 밝은 곳일수록 옅게"""
    c = rgba[..., :3].astype(np.float64)
    lum = c.mean(axis=2)
    col = np.stack([lum, lum * 0.86, lum * 0.74], axis=2) * 0.55
    a = rgba[..., 3] * np.clip(1.25 - lum / 170.0, 0.0, 1.0)
    return np.dstack([col, a]).astype(np.uint8)


def cells(img: Image.Image, cols: int, rows: int) -> list:
    w, h = img.size
    out = []
    for r in range(rows):
        for c in range(cols):
            box = (round(c * w / cols), round(r * h / rows), round((c + 1) * w / cols), round((r + 1) * h / rows))
            out.append(img.crop(box).resize((CELL, CELL), Image.LANCZOS))
    return out


def measure(cell: np.ndarray) -> list:
    """덩어리 [가운데 x, 가운데 y, 가로 반, 위 y, 아래 y] (칸 px). 비었으면 칸 가운데"""
    m = cell[..., 3] > 255 * SOLID
    if not m.any():
        return [CELL / 2, CELL / 2, 0, CELL / 2, CELL / 2]
    ys, xs = np.nonzero(m)
    x0, x1 = np.percentile(xs, [1, 99])
    y0, y1 = np.percentile(ys, [1, 99])
    return [round((x0 + x1) / 2, 1), round((y0 + y1) / 2, 1), round((x1 - x0) / 2, 1), round(y0, 1), round(y1, 1)]


def debug_sheet(sheet: np.ndarray, path: Path) -> None:
    h, w = sheet.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    board = np.where(((yy // 16 + xx // 16) % 2)[..., None] == 0, 70, 110).astype(np.float64) * np.ones(3)
    a = sheet[..., 3:4] / 255.0
    out = sheet[..., :3] * a + board * (1 - a)
    Image.fromarray(out.astype(np.uint8)).save(path)


def prepare(name: str, spec: dict, debug: bool) -> "dict | None":
    src = SRC / f"{name}.png"
    if not src.exists():
        print(f"  {name}: 받은 그림 없음 ({src.relative_to(ROOT)}) — 건너뜀")
        return None
    cols, rows = spec["grid"]
    img = Image.open(src).convert("RGB")
    key = unmix_black if spec["bg"] == "black" else unmix_magenta
    frames = [key(np.asarray(c)) for c in cells(img, cols, rows)]
    if spec.get("ground_decal"):
        frames = [char_tone(f) for f in frames]
    sheet = np.zeros((rows * CELL, cols * CELL, 4), np.uint8)
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        sheet[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = f
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(sheet).save(OUT / f"{name}.png")
    if debug:
        debug_sheet(sheet, SRC / f"{name}_debug.png")
    boxes = [measure(f) for f in frames]
    info = {"grid": [cols, rows], "cell": CELL, "frames": len(frames), "boxes": boxes}
    if spec.get("ground_decal"):
        info["anchor"] = [CELL / 2, CELL / 2]
    elif spec.get("loop"):
        # 불꽃: 바닥 = 칸마다 덩어리 아래 끝의 가운데값, 키 = 덩어리 높이의 가운데값
        info["anchor"] = [CELL / 2, round(float(np.median([b[4] for b in boxes])), 1)]
        info["height"] = round(float(np.median([b[4] - b[3] for b in boxes])), 1)
    else:
        info["anchor"] = [CELL / 2, 214 * CELL / 256]   # 가이드의 바닥 점 (폭발이 일어난 땅)
    if "seconds" in spec:
        info["seconds"] = spec["seconds"]
    print(f"  {name}: {len(frames)}칸 → assets/fx/{name}.png  바닥 {info['anchor']}" + (f"  키 {info['height']}" if "height" in info else ""))
    return info


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    debug = "--debug" in sys.argv
    sheets = json.loads(GUIDE.read_text())["sheets"]
    meta_path = OUT / "fx.json"
    meta = json.loads(meta_path.read_text()) if meta_path.exists() else {}
    for name, spec in sheets.items():
        if args and name not in args:
            continue
        info = prepare(name, spec, debug)
        if info:
            meta[name] = info
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    print(f"→ {meta_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
