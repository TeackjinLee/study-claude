#!/usr/bin/env python3
"""제미나이가 그린 건물 정면도를 게임 텍스처로 다듬는다 (output/imagegen/buildings/GEMINI_BUILDING_PROMPT.md 방식 A).

입력  output/imagegen/buildings/facade/<ID>_facade.png         낮 그림 (마젠타 배경)
      output/imagegen/buildings/facade/<ID>_facade_lights.png  밤 불빛 그림 (검정 배경. 어두운 밤 건물이 비쳐도 된다)
      output/imagegen/buildings/guides/<ID>_facade.json        tools/building_guide.tscn -- --facade 가 낸 템플릿 정보
출력  assets/buildings/facade/<id>.png · <id>_lights.png · <id>.json   (BuildingSkin이 읽는다)

생성기는 템플릿 칸(난간·윗층·1층 한 줄씩)을 그대로 지키지 않고 건물 정면 전체를 그리곤 한다.
그래서 칸 좌표를 믿지 않고, 마젠타가 아닌 덩어리 셋(정면·옆벽·옥상)을 찾아 층 높이(템플릿의 층 높이 px)로 줄을 다시 나눈다:
위에서부터 난간(층 높이의 PARAPET배) + 층 N개. 윗층 띠는 맨 위 층, 1층 띠는 맨 아래 층을 쓴다 (ROWS로 바꿀 수 있다).

사용: python3 tools/prepare_building_textures.py [ID ...] [--debug]
--debug 면 자른 띠를 표시한 그림을 output/imagegen/buildings/facade/<ID>_cut_debug.png 로 낸다.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "output/imagegen/buildings/facade"
GUIDES = ROOT / "output/imagegen/buildings/guides"
DST = ROOT / "assets/buildings/facade"

PARAPET = 0.5          # 난간 높이 (층 높이 배수, building_guide.gd와 같다)
TEXEL = 3.0            # 게임 화면(줌 1) 1px당 텍스처 px. 게임은 밉맵으로 줄여 그린다
BLOCKS = ("front", "side", "roof")
# 종류별로 어느 층 띠를 쓸지 (위에서부터 0번 층, 음수는 아래에서부터). 없으면 윗층 0 · 1층 -1
ROWS = {}


def magenta(a: np.ndarray) -> np.ndarray:
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    return (r > 170) & (g < 110) & (b > 170) & (np.abs(r - b) < 70)


def pinkish(a: np.ndarray) -> np.ndarray:
    """마젠타가 섞인 가장자리 (붉은 벽돌은 파랑이 낮아 걸리지 않는다)."""
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    return (np.minimum(r, b) - g > 45) & (np.abs(r - b) < 90)


def despill(rgb: np.ndarray, near: np.ndarray) -> np.ndarray:
    """배경 가까이에서 남은 분홍기를 뺀다: 빨강·파랑을 초록 쪽으로 당긴다."""
    out = rgb.astype(int).copy()
    r, g, b = out[..., 0], out[..., 1], out[..., 2]
    spill = np.clip(np.minimum(r, b) - g, 0, None) * near
    out[..., 0] = r - spill
    out[..., 2] = b - spill
    return np.clip(out, 0, 255).astype(np.uint8)


def grow(mask: np.ndarray, steps: int) -> np.ndarray:
    m = mask.copy()
    for _ in range(steps):
        m = m | np.roll(m, 1, 0) | np.roll(m, -1, 0) | np.roll(m, 1, 1) | np.roll(m, -1, 1)
    return m


def runs(v: np.ndarray, th: float) -> list:
    out, s = [], None
    for i, x in enumerate(v):
        if x > th and s is None:
            s = i
        elif x <= th and s is not None:
            out.append((s, i))
            s = None
    if s is not None:
        out.append((s, len(v)))
    return out


def find_blocks(solid: np.ndarray) -> list:
    """마젠타가 아닌 큰 덩어리 셋 (왼쪽부터 정면·옆벽·옥상). 제미나이 표식 같은 작은 점은 버린다."""
    cols = runs(solid.sum(0), solid.shape[0] * 0.15)
    cols = [c for c in cols if c[1] - c[0] > 40]
    if len(cols) != 3:
        sys.exit(f"덩어리를 셋 찾지 못했다 (찾은 열: {cols}) — 정면·옆벽·옥상이 떨어져 있어야 한다")
    out = []
    for c0, c1 in cols:
        rows = runs(solid[:, c0:c1].sum(1), (c1 - c0) * 0.3)
        r0, r1 = max(rows, key=lambda r: r[1] - r[0])
        out.append((c0, r0, c1, r1))
    return out


def bleed(rgba: np.ndarray, steps: int = 6) -> np.ndarray:
    """투명한 칸의 색을 옆 불투명 칸 색으로 채운다 (밉맵·선형 보간에 마젠타가 번지지 않게)."""
    rgb = rgba[..., :3].astype(float)
    known = rgba[..., 3] > 0
    for _ in range(steps):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(known.shape)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            k = np.roll(known, (dy, dx), (0, 1))
            acc += np.roll(rgb, (dy, dx), (0, 1)) * k[..., None]
            cnt += k
        fill = (~known) & (cnt > 0)
        rgb[fill] = acc[fill] / cnt[fill][:, None]
        known = known | fill
    out = rgba.copy()
    out[..., :3] = rgb.astype(np.uint8)
    return out


def prepare(tid: str, debug: bool) -> None:
    day_p = SRC / f"{tid}_facade.png"
    lit_p = SRC / f"{tid}_facade_lights.png"
    guide_p = GUIDES / f"{tid}_facade.json"
    if not guide_p.exists():
        sys.exit(f"{guide_p} 없음 — godot --path . res://tools/building_guide.tscn -- --facade --ids={tid}")
    guide = json.loads(guide_p.read_text())
    day = np.asarray(Image.open(day_p).convert("RGB"))
    lit = np.asarray(Image.open(lit_p).convert("RGB")) if lit_p.exists() else None
    if lit is not None and lit.shape != day.shape:
        sys.exit(f"불빛 그림 크기가 다르다: {lit.shape[1]}×{lit.shape[0]} (낮 {day.shape[1]}×{day.shape[0]})")
    # 받은 그림이 템플릿 캔버스와 크기가 다르면 같은 비율로 본다
    k_img = day.shape[1] / guide["sheet"][0]
    fl_t = guide["floor_height"] * guide["texel_per_screen_px"] * k_img      # 템플릿의 층 높이 (받은 그림 px)
    solid = ~magenta(day)
    blocks = dict(zip(BLOCKS, find_blocks(solid)))
    fx0, fy0, fx1, fy1 = blocks["front"]
    n = max(1, round((fy1 - fy0 - PARAPET * fl_t) / fl_t))
    fl = (fy1 - fy0) / (n + PARAPET)                                          # 받은 그림의 실제 층 높이
    rows = ROWS.get(tid, {})
    up = rows.get("upper", 0) % n
    gr = rows.get("ground", -1) % n
    print(f"{tid}: 층 {n}개 · 층 높이 {fl:.1f}px (템플릿 {fl_t:.1f}) · 윗층 띠 {up}번 · 1층 띠 {gr}번")

    # 텍스처 배율: 게임 화면 1px = TEXEL px
    s = TEXEL * guide["floor_height"] / fl
    x0 = min(b[0] for b in blocks.values())
    y0 = min(b[1] for b in blocks.values())
    x1 = max(b[2] for b in blocks.values())
    y1 = max(b[3] for b in blocks.values())
    crop = (x0, y0, x1, y1)
    size = (round((x1 - x0) * s), round((y1 - y0) * s))

    def to_tex(x, y):
        return (x - x0) * s, (y - y0) * s

    def rect(xa, ya, xb, yb):
        (ax, ay), (bx, by) = to_tex(xa, ya), to_tex(xb, yb)
        return [round(ax, 2), round(ay, 2), round(bx - ax, 2), round(by - ay, 2)]

    info = {"id": tid, "windows": guide["windows"], "bay_world": guide["bay_world"], "parapet": PARAPET,
            "texel_per_screen_px": TEXEL, "size": list(size)}
    for name in ("front", "side"):
        bx0, by0, bx1, by1 = blocks[name]
        top = by0 + PARAPET * fl
        bays = guide["front_bays"] if name == "front" else guide["side_bays"]
        # 띠를 안으로 조금: 위아래는 이웃 줄 색이, 좌우는 마젠타 가장자리가 섞이지 않게
        info[name] = {
            "bays": bays,
            "parapet": rect(bx0 + 3, by0, bx1 - 3, top - 0.5),
            "upper": rect(bx0 + 3, top + up * fl + 0.5, bx1 - 3, top + (up + 1) * fl - 0.5),
            "ground": rect(bx0 + 3, top + gr * fl + 0.5, bx1 - 3, top + (gr + 1) * fl - 1),
        }
    rx0, ry0, rx1, ry1 = blocks["roof"]
    info["roof"] = rect(rx0 + 2, ry0 + 2, rx1 - 2, ry1 - 2)

    DST.mkdir(parents=True, exist_ok=True)
    # 덩어리 안의 마젠타(난간 살 사이)와 그 둘레의 분홍 섞인 가장자리는 비우고, 덩어리 밖은 모두 비운다
    keep = np.zeros(solid.shape, bool)
    for b in blocks.values():
        keep[b[1]:b[3], b[0]:b[2]] = True
    bg = ~solid
    near = grow(bg, 3)
    opaque = keep & solid & ~(near & pinkish(day))
    rgba = np.dstack([despill(day, grow(bg, 6)), np.where(opaque, 255, 0).astype(np.uint8)])
    img = Image.fromarray(bleed(rgba)).crop(crop).resize(size, Image.LANCZOS)
    img.save(DST / f"{tid.lower()}.png")
    if lit is not None:
        # 밝은 곳만 불빛으로 (밤 그림의 어두운 건물은 버린다). 알파 = 밝기, 색은 원래 불빛 색
        lum = lit.max(2).astype(float)
        a = np.clip((lum - 45.0) / 70.0, 0.0, 1.0)
        a[~keep] = 0.0
        la = np.dstack([lit, (a * 255).astype(np.uint8)])
        Image.fromarray(bleed(la, 3)).crop(crop).resize(size, Image.LANCZOS).save(DST / f"{tid.lower()}_lights.png")
    (DST / f"{tid.lower()}.json").write_text(json.dumps(info, ensure_ascii=False, indent=2))
    print(f"  → {DST.relative_to(ROOT)}/{tid.lower()}.png {size[0]}×{size[1]}" + (" + 불빛" if lit is not None else ""))

    if debug:
        dbg = Image.fromarray(day).convert("RGB")
        d = ImageDraw.Draw(dbg)
        for name in ("front", "side"):
            for band, col in (("parapet", (0, 255, 255)), ("upper", (255, 255, 0)), ("ground", (0, 255, 0))):
                x, y, w, h = info[name][band]
                d.rectangle([x / s + x0, y / s + y0, (x + w) / s + x0, (y + h) / s + y0], outline=col, width=3)
            x, y, w, h = info[name]["upper"]
            for i in range(1, info[name]["bays"]):
                xx = x / s + x0 + w / s * i / info[name]["bays"]
                d.line([xx, y / s + y0, xx, (y + h) / s + y0], fill=(255, 255, 0), width=1)
        x, y, w, h = info["roof"]
        d.rectangle([x / s + x0, y / s + y0, (x + w) / s + x0, (y + h) / s + y0], outline=(0, 128, 255), width=3)
        dbg.save(SRC / f"{tid}_cut_debug.png")


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    debug = "--debug" in sys.argv
    ids = args or sorted(p.name[: -len("_facade.png")] for p in SRC.glob("*_facade.png"))
    for tid in ids:
        prepare(tid, debug)


if __name__ == "__main__":
    main()
