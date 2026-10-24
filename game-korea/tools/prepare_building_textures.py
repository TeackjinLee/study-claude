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


# 가져오기 설정: VRAM 압축(BC7)·밉맵 (BuildingSkin._vram이 보고 그대로 쓴다 — RGBA로 풀면 GPU 메모리가 4배).
# 벽면 그림·통째 그림(prepare_building_sprites.py) 모두 그림 옆 .import에 적는다
IMPORT_PARAMS = {"compress/mode": "2", "compress/high_quality": "true", "mipmaps/generate": "true"}


def import_settings(png: Path) -> None:
    """그림 옆 .import에 IMPORT_PARAMS를 넣는다. 없으면 이것만 적은 파일을 두고 godot --import가 나머지를 채운다."""
    imp = png.with_name(png.name + ".import")
    if not imp.exists():
        imp.write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                       + "".join(f"{k}={v}\n" for k, v in IMPORT_PARAMS.items()))
        return
    lines = imp.read_text().splitlines()
    for i, ln in enumerate(lines):
        k = ln.split("=", 1)[0]
        if k in IMPORT_PARAMS:
            lines[i] = f"{k}={IMPORT_PARAMS[k]}"
    imp.write_text("\n".join(lines) + "\n")


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


def floor_pitch(day: np.ndarray, block, fl_t: float) -> float:
    """정면 덩어리에서 가로줄 무늬가 되풀이되는 가장 짧은 간격 (받은 그림 px)."""
    x0, y0, x1, y1 = block
    a = day[y0:y1, x0 + 4:x1 - 4].astype(float).mean(2)
    lags = range(max(8, int(fl_t * 0.35)), min(int(fl_t * 1.4), a.shape[0] // 2))
    d = np.array([np.abs(a[:-L] - a[L:]).mean() for L in lags])
    if len(d) == 0:
        return fl_t
    good = np.nonzero(d <= d.min() * 1.12)[0]
    k = good[0]
    while k + 1 < len(d) and d[k + 1] < d[k]:   # 그 골짜기의 바닥까지
        k += 1
    if d[k] > 0.75 * np.median(d):
        # 뚜렷하게 되풀이되지 않는다(층이 하나뿐인 공장 — 골함석 세로 골만 비슷하다) — 템플릿 층 높이 그대로
        return fl_t
    return float(lags[k])


def snap_edge(day: np.ndarray, block, y: float, win: float) -> float:
    """y 둘레 ±win 안에서 위아래 줄 색이 가장 크게 바뀌는 줄 (턱·차양 경계). 뚜렷하지 않으면 y 그대로."""
    x0, y0, x1, y1 = block
    a = day[y0:y1, x0 + 4:x1 - 4].astype(float).mean(2)
    e = np.zeros(a.shape[0])
    e[1:] = np.abs(a[1:] - a[:-1]).mean(1)
    lo, hi = max(1, int(y - win) - y0), min(a.shape[0] - 1, int(y + win) - y0)
    if hi <= lo:
        return y
    k = lo + int(np.argmax(e[lo:hi]))
    return float(y0 + k) if e[k] > 1.5 * np.median(e) else y


def ground_start(day: np.ndarray, block, pitch: float):
    """1층(가게 앞·출입구)이 시작하는 줄: 한 층 위 줄과 닮지 않게 되는 곳. 뚜렷하지 않으면 None."""
    x0, y0, x1, y1 = block
    p = int(round(pitch))
    a = day[y0:y1, x0 + 4:x1 - 4].astype(float).mean(2)
    if a.shape[0] < 2 * p:
        return None
    d = np.zeros(a.shape[0])
    d[p:] = np.abs(a[p:] - a[:-p]).mean(1)
    w = max(3, p // 4)
    lo, hi = max(p + w, a.shape[0] - int(1.6 * pitch)), a.shape[0] - int(0.6 * pitch)
    best, at = 0.0, None
    for y in range(lo, hi):
        step = d[y:y + w].mean() - d[y - w:y].mean()
        if step > best:
            best, at = step, y
    base = np.median(d[p:max(p + 1, lo)])
    if at is None or best < 2.0 * max(base, 1.0):
        return None
    return y0 + at


def read_cuts(tid: str) -> dict:
    """<ID>_facade.cuts.txt — 층을 고르지 않게 그려 자동으로 못 자르는 그림의 자를 줄 (받은 그림 px).
    줄마다 `front|side 난간끝 윗층위 윗층아래 1층위` (1층 아래는 덩어리 끝). # 뒤는 주석"""
    p = SRC / f"{tid}_facade.cuts.txt"
    out = {}
    if p.exists():
        for line in p.read_text().splitlines():
            w = line.split("#")[0].split()
            if len(w) == 5 and w[0] in ("front", "side"):
                out[w[0]] = [float(v) for v in w[1:]]
    return out


STAR_R, STAR_Q, STAR_A = 24.0, 0.74, 0.30   # 워터마크 별(✦): 1376px 캔버스에서 반지름 · 변의 휨 · 불투명도
STAR_AT = (0.9125, 0.8431)                  # 캔버스 오른쪽 아래, 캔버스 크기에 대한 별 가운데


def remove_star(rgb: np.ndarray, label: str, ref: np.ndarray = None) -> np.ndarray:
    """생성기 워터마크 별(반투명 흰 ✦)이 건물 위(옥상)에 찍혔으면 걷어 낸다. 마젠타 위 별은 어차피 비우므로 그대로.
    원래 색 = (보이는 색 − a × 흰색) / (1 − a) — 가운데·크기를 조금씩 옮겨 보며 되돌린 곳이 가장 매끄러운 것을 쓴다"""
    h, w = rgb.shape[:2]
    k = w / 1376.0
    cx0, cy0 = w * STAR_AT[0], h * STAR_AT[1]
    half = int(STAR_R * k * 1.3) + 6
    y0, x0 = int(cy0) - half, int(cx0) - half
    if y0 < 0 or x0 < 0 or y0 + 2 * half > h or x0 + 2 * half > w:
        return rgb
    patch = rgb[y0:y0 + 2 * half, x0:x0 + 2 * half].astype(float)
    on = (rgb if ref is None else ref)[y0:y0 + 2 * half, x0:x0 + 2 * half]   # 불빛 그림은 낮 그림에서 본다
    if magenta(on).mean() > 0.5:
        return rgb
    yy, xx = np.mgrid[0:2 * half, 0:2 * half] + 0.5

    def rough(img, band):
        # 별 테두리 둘레에서만 잰다 — 옥상 얼룩 무늬 전체를 재면 테두리가 사라진 몫이 묻힌다
        gy = np.abs(np.diff(img, axis=0)).sum(2)[band[1:] | band[:-1]].sum()
        gx = np.abs(np.diff(img, axis=1)).sum(2)[band[:, 1:] | band[:, :-1]].sum()
        return gy + gx

    best = (0.85, None)
    for r in np.arange(STAR_R * k * 0.9, STAR_R * k * 1.12, 0.5):
        for a0 in (0.26, 0.30, 0.34):
            for dy in np.arange(-4.0, 4.01, 1.0):
                for dx in np.arange(-4.0, 4.01, 1.0):
                    f = (np.abs(xx - (cx0 - x0 + dx)) / r) ** STAR_Q + (np.abs(yy - (cy0 - y0 + dy)) / r) ** STAR_Q
                    a = (a0 * np.clip((1.0 - f) * r * 0.45 + 0.5, 0.0, 1.0))[..., None]
                    out = np.clip((patch - a * 255.0) / (1.0 - a), 0, 255)
                    band = (f > 0.7) & (f < 1.4)
                    v = rough(out, band) / max(rough(patch, band), 1.0)
                    if v < best[0]:
                        best = (v, out)
    if best[1] is None:
        # 무늬가 많은 옥상(낮 그림)은 되돌린 색이 맞지 않는다 — 별 자리를 가까운 옥상 무늬로 메운다(테두리가 가장 잘 맞는 곳)
        cx, cy = cx0 - x0, cy0 - y0
        r = STAR_R * k
        f = (np.abs(xx - cx) / r) ** STAR_Q + (np.abs(yy - cy) / r) ** STAR_Q
        m = np.clip((1.2 - f) * r * 0.25, 0.0, 1.0)[..., None]
        ring = (f > 1.2) & (f < 1.8)
        n = 2 * half
        pick = None
        for oy, ox in ((-n, 0), (0, -n), (-n, -n), (-2 * n, 0), (0, -2 * n), (n, -n), (-n, n)):
            sy, sx = y0 + oy, x0 + ox
            if sy < 0 or sx < 0 or sy + n > h or sx + n > w:
                continue
            src = rgb[sy:sy + n, sx:sx + n].astype(float)
            if magenta(src.astype(np.uint8)).any():
                continue
            v = np.abs(src - patch)[ring].mean()
            if pick is None or v < pick[0]:
                pick = (v, src)
        if pick is None:
            return rgb
        best = (None, patch * (1.0 - m) + pick[1] * m)
        print(f"  {label}: 워터마크 별을 옆 무늬로 메움")
    else:
        print(f"  {label}: 워터마크 별 지움 (테두리 거칠기 {best[0]:.0%})")
    res = rgb.copy()
    res[y0:y0 + 2 * half, x0:x0 + 2 * half] = best[1].astype(np.uint8)
    return res


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
        # 생성기가 1~2px 다르게 내는 일이 있다 — 2% 안이면 낮 그림 크기로 늘려 맞춘다
        dw, dh = abs(lit.shape[1] - day.shape[1]) / day.shape[1], abs(lit.shape[0] - day.shape[0]) / day.shape[0]
        if max(dw, dh) > 0.02:
            sys.exit(f"불빛 그림 크기가 다르다: {lit.shape[1]}×{lit.shape[0]} (낮 {day.shape[1]}×{day.shape[0]})")
        print(f"  불빛 그림 {lit.shape[1]}×{lit.shape[0]} → 낮 그림 크기 {day.shape[1]}×{day.shape[0]}로 맞춤")
        lit = np.asarray(Image.fromarray(lit).resize((day.shape[1], day.shape[0]), Image.LANCZOS))
    day = remove_star(day, "낮 그림")
    if lit is not None:
        lit = remove_star(lit, "불빛 그림", ref=day)
    # 받은 그림이 템플릿 캔버스와 크기가 다르면 같은 비율로 본다
    k_img = day.shape[1] / guide["sheet"][0]
    fl_t = guide["floor_height"] * guide["texel_per_screen_px"] * k_img      # 템플릿의 층 높이 (받은 그림 px)
    solid = ~magenta(day)
    blocks = dict(zip(BLOCKS, find_blocks(solid)))
    fx0, fy0, fx1, fy1 = blocks["front"]
    # 생성기가 템플릿을 세로로 늘려 그리기도 한다(오피스텔: 두 배) — 정사각형이어야 할 옥상의 세로/가로로 잰다
    rx0, ry0, rx1, ry1 = blocks["roof"]
    stretch = (ry1 - ry0) / (rx1 - rx0)
    if abs(stretch - 1.0) > 0.25:
        print(f"  옥상이 세로로 {stretch:.2f}배 — 템플릿을 세로로 늘려 그렸다고 보고 층 높이도 늘린다")
        fl_t *= stretch
    else:
        stretch = 1.0
    # 생성기가 층을 템플릿과 다른 높이로 그리기도 한다(상가: 템플릿의 반) — 줄 무늬가 되풀이되는 간격으로 층 높이를 잰다
    pitch = floor_pitch(day, blocks["front"], fl_t)
    measured = abs(pitch / fl_t - 1.0) > 0.12
    if measured:
        print(f"  그림의 층 간격 {pitch:.0f}px — 템플릿({fl_t:.0f}px)과 달라 그림 간격으로 자른다 (1층 띠 = 남는 아래 전부)")
        fl_t = pitch
    n = max(1, round((fy1 - fy0 - PARAPET * fl_t) / fl_t))
    # 받은 그림의 실제 층 높이. 잰 간격이면 그대로 (윗층 띠가 정확히 한 간격이어야 이음매가 안 보인다)
    fl = pitch if measured else (fy1 - fy0) / (n + PARAPET)
    y_ground = ground_start(day, blocks["front"], pitch) if measured else None
    if y_ground is not None:
        # 1층이 시작하는 줄부터 위로 층 간격씩 — 난간 띠는 남는 위 전부
        n = max(1, int((y_ground - fy0 - 0.2 * fl) // fl)) + 1
        print(f"  1층은 {y_ground - fy0}px 줄부터 (위로 {n - 1}개 층, 난간 {y_ground - (n - 1) * fl - fy0:.0f}px)")
    cuts = read_cuts(tid)
    if "front" in cuts:
        fl = cuts["front"][2] - cuts["front"][1]
        print(f"  {tid}_facade.cuts.txt의 줄로 자른다 (윗층 {fl:.0f}px)")
    rows = ROWS.get(tid, {})
    up = rows.get("upper", 0) % n
    gr = rows.get("ground", -1) % n
    print(f"{tid}: 층 {n}개 · 층 높이 {fl:.1f}px (템플릿 {fl_t:.1f}) · 윗층 띠 {up}번 · 1층 띠 {gr}번")

    # 텍스처 배율: 게임 화면 1px = TEXEL px
    s = TEXEL * guide["floor_height"] / (fl / stretch)   # 가로 기준 (세로로 늘린 그림은 세로가 그만큼 촘촘하다 — UV로 편다)
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

    # 칸 하나의 가로세로 비율도 그림대로: 창 칸을 템플릿보다 넓게 그렸으면 게임의 칸 간격(bay_world)을 그만큼 넓힌다
    # (아니면 넓은 창이 칸에 눌려 홀쭉해진다)
    bay_world = guide["bay_world"]
    aspect = ((fx1 - fx0) / guide["front_bays"] / (fl / stretch)) / (guide["bay_screen"] / guide["floor_height"])
    if abs(aspect - 1.0) > 0.15:
        bay_world = round(guide["bay_world"] * aspect, 2)
        print(f"  창 칸이 템플릿보다 {aspect:.2f}배 넓다 — 칸 간격 {guide['bay_world']} → {bay_world}")
    info = {"id": tid, "windows": guide["windows"], "bay_world": bay_world, "parapet": PARAPET,
            "texel_per_screen_px": TEXEL, "size": list(size)}
    for name in ("front", "side"):
        bx0, by0, bx1, by1 = blocks[name]
        top = by0 + PARAPET * fl
        if y_ground is not None:
            top = y_ground - (n - 1) * fl   # 정면·옆벽은 같은 높이로 그려져 있다 — 같은 줄로 자른다
        bays = guide["front_bays"] if name == "front" else guide["side_bays"]
        # 띠를 안으로 조금: 위아래는 이웃 줄 색이, 좌우는 마젠타 가장자리가 섞이지 않게
        info[name] = {
            "bays": bays,
            "parapet": rect(bx0 + 3, by0, bx1 - 3, top - 0.5),
            "upper": rect(bx0 + 3, top + up * fl + 0.5, bx1 - 3, top + (up + 1) * fl - 0.5),
            "ground": rect(bx0 + 3, (y_ground if y_ground is not None and gr == n - 1 else top + gr * fl) + 0.5, bx1 - 3,
                           (by1 if measured and gr == n - 1 else top + (gr + 1) * fl) - 1),
        }
        if n == 2 and not measured:
            # 층이 하나뿐(난간 · 윗층 · 1층 그대로 그린 그림)이면 되풀이 간격을 지킬 것이 없다 — 옥상 턱 아래·1층 차양 위
            # 경계에 맞춰 자른다 (윗층·1층 띠 높이가 달라도 게임이 한 층 높이로 편다)
            top = snap_edge(day, blocks[name], top, 0.3 * fl)
            yg = snap_edge(day, blocks[name], by1 - fl, 0.3 * fl)
            info[name]["parapet"] = rect(bx0 + 3, by0, bx1 - 3, top - 0.5)
            info[name]["upper"] = rect(bx0 + 3, top + 0.5, bx1 - 3, yg - 0.5)
            info[name]["ground"] = rect(bx0 + 3, yg + 0.5, bx1 - 3, by1 - 1)
            print(f"  {name}: 층이 하나라 경계에 맞춰 자른다 — 난간 {top - by0:.0f}px · 윗층 {yg - top:.0f}px · 1층 {by1 - yg:.0f}px")
        if name in cuts:
            pb, u0, u1, g0 = cuts[name]
            info[name]["parapet"] = rect(bx0 + 3, by0, bx1 - 3, pb - 0.5)
            info[name]["upper"] = rect(bx0 + 3, u0 + 0.5, bx1 - 3, u1 - 0.5)
            info[name]["ground"] = rect(bx0 + 3, g0 + 0.5, bx1 - 3, by1 - 1)
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
    import_settings(DST / f"{tid.lower()}.png")
    if lit is not None:
        # 밝은 곳만 불빛으로 (밤 그림의 어두운 건물은 버린다). 알파 = 밝기, 색은 원래 불빛 색
        lum = lit.max(2).astype(float)
        a = np.clip((lum - 45.0) / 70.0, 0.0, 1.0)
        a[~keep] = 0.0
        la = np.dstack([lit, (a * 255).astype(np.uint8)])
        Image.fromarray(bleed(la, 3)).crop(crop).resize(size, Image.LANCZOS).save(DST / f"{tid.lower()}_lights.png")
        import_settings(DST / f"{tid.lower()}_lights.png")
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
