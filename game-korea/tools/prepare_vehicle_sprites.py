#!/usr/bin/env python3
"""헬기 방향 그림 다듬기 (output/imagegen/vehicles/GPT_HELI_PROMPT.md).

받은 시트 output/imagegen/vehicles/<id>_A.png · _B.png (3×3 칸) · _C.png (뒷모습 2×2 칸, 마젠타 배경)를
가이드(tools/vehicle_guide.tscn이 낸 guides/<id>_<시트>_guide.png · <id>.json)에 칸마다 맞춰
assets/vehicles/sprites/<id>.png (반 바퀴 17방향 한 줄) · <id>.json 으로 낸다. 게임은 VehicleSprite가 읽는다.

  python3 tools/prepare_vehicle_sprites.py sp_heli [--debug]

칸마다 하는 일
  0. 생성기 워터마크(반투명 흰 별 ✦)를 지운다 — 마젠타 위 별의 초록 채널로 불투명도를 재고, 별이 상하좌우 대칭이라
     헬기 위에 겹친 쪽도 그 불투명도로 원래 색을 되돌린다 (remove_sparkle).
  1. 마젠타 배경을 지운다 (가장자리 섞임까지 unmix_key로 풀어 반투명으로).
  2. 그림 윤곽을 가이드 윤곽에 배율·위치로 맞춘다 (생성기가 캔버스 크기·칸 안 위치를 조금씩 바꿔 그린다).
  3. 맞춘 윤곽을 17방향 가이드(좌우로 뒤집은 것 포함)와 모두 견줘 가장 닮은 방향을 찾는다.
     제 방향이 아니면(옆 칸을 베껴 그렸으면) 버린다.
  4. 기수 방향 축으로 본 윤곽 치우침(굵은 동체 = 코 쪽)이 가이드와 같은 쪽인지 본다 — 반대면 코·꼬리를 바꿔 그린 것이라 버린다
     (↑·↓ 칸은 앞뒤 윤곽이 비슷해 3으로는 못 가린다. 유리 색으로 보려 했지만 그림체마다 유리·동체 색이 달라 못 쓴다).
  5. 앞 시트의 칸과 그림이 거의 같으면(윤곽이 90% 넘게 겹치고 헬기 픽셀 평균 차이 12 미만) 베낀 칸이라 버린다
     (B를 A 그대로 낸 적이 있다).
  버린 방향은 게임이 가까운 방향 그림을 비틀어 쓰고, 11.25°보다 멀면 코드 모형으로 그린다.
  같은 이름의 .skip.txt(예: sp_heli_A.skip.txt에 "1 2", 칸 번호는 1부터)에 적은 칸은 검사와 상관없이 버리고,
  .keep.txt에 적은 칸은 앞뒤 검사를 넘긴다.
  --debug: output/imagegen/vehicles/<id>_fit_debug.png — 칸마다 맞춘 그림 위에 가이드 윤곽(하늘색)과 판정.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "output/imagegen/vehicles"
GUIDES = SRC / "guides"
OUT = ROOT / "assets/vehicles/sprites"
MAGENTA = np.array([255, 0, 255])
OUT_SCALE = 2.0          ## 게임 그림 배율: 화면(줌 1) 1px당 그림 px (카메라 줌은 1.1까지라 이 정도면 줄여 그린다)
SCALES = np.arange(0.84, 1.17, 0.01)
MIN_IOU = 0.62           ## 가이드와 이만큼은 겹쳐야 쓴다
MARGIN = 0.02            ## 제 방향이 다른 방향보다 이만큼 덜 닮으면 버린다


def unmix_magenta(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """마젠타가 섞인 만큼(빨강·파랑이 초록보다 높은 만큼, 두 채널이 비슷할 때만) 반투명으로 풀고 색에서 마젠타를 뺀다.
    남색 동체(파랑 > 빨강)는 두 채널 차이가 커서 건드리지 않는다"""
    c = rgb.astype(np.float64)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    top = np.minimum(r, b)
    e = np.clip((top - g) / 255.0, 0.0, 1.0)
    e = np.where(np.abs(r - b) < 70, e, 0.0)
    keep = np.maximum(1.0 - e, 0.05)[..., None]
    out = np.clip((c - e[..., None] * MAGENTA) / keep, 0, 255)
    a = 255.0 * (1.0 - e)
    a = np.where(a < 40, 0, a)
    return out.astype(np.uint8), a.astype(np.uint8)


def _blobs(mask: np.ndarray, min_size: int) -> list:
    """4방향으로 이어진 덩어리들 (좌표 배열 목록). 별 후보처럼 점이 적은 마스크용"""
    seen = np.zeros_like(mask)
    out = []
    h, w = mask.shape
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        stack = [(y0, x0)]
        seen[y0, x0] = True
        pts = []
        while stack:
            y, x = stack.pop()
            pts.append((y, x))
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(pts) >= min_size:
            out.append(np.array(pts))
    return out


def remove_sparkle(rgb: np.ndarray) -> tuple[np.ndarray, int]:
    """생성기 워터마크 별(✦, 반투명 흰색)을 지운다. 마젠타 위의 별은 분홍(빨강·파랑 255, 초록 = 불투명도 × 255)이라
    거기서 불투명도를 재고, 별은 상하좌우 대칭이니 거울 자리 중 마젠타 위에서 잰 값으로 헬기 위 불투명도를 채운다.
    원래 색 = (보이는 색 − 불투명도 × 흰색) / (1 − 불투명도). 가운데가 반 픽셀만 어긋나도 별 테두리가 선으로 남아서,
    가운데를 0.5px씩 옮겨 보며 되돌린 헬기 쪽이 가장 매끄러운(이웃 차이가 가장 작은) 곳을 쓴다. 지운 별 수를 함께 돌려준다"""
    c = rgb.astype(np.float64)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    over_bg = (r > 200) & (b > 200)
    pink = over_bg & (g > 40)
    found = 0
    for pts in _blobs(pink, 40):
        ys, xs = pts[:, 0], pts[:, 1]
        top, bot = pts[ys.argmin()], pts[ys.argmax()]
        cx0 = (top[1] + bot[1]) / 2.0
        cy0 = (top[0] + bot[0]) / 2.0
        half = int(max(ys.max() - cy0, cy0 - ys.min(), xs.max() - cx0, cx0 - xs.min())) + 4
        y0, y1 = int(cy0) - half, int(cy0) + half + 1
        x0, x1 = int(cx0) - half, int(cx0) + half + 1
        if y0 < 0 or x0 < 0 or y1 > c.shape[0] or x1 > c.shape[1]:
            continue
        patch = c[y0:y1, x0:x1]
        meas = over_bg[y0:y1, x0:x1]
        alpha = np.where(meas, g[y0:y1, x0:x1] / 255.0, 0.0)
        yy, xx = np.mgrid[0:y1 - y0, 0:x1 - x0]
        best = None
        for dcy in np.arange(-2.0, 2.01, 0.5):
            for dcx in np.arange(-2.0, 2.01, 0.5):
                cy, cx = cy0 - y0 + dcy, cx0 - x0 + dcx
                full = alpha.copy()
                cand = []
                for my, mx in ((yy, 2 * cx - xx), (2 * cy - yy, xx), (2 * cy - yy, 2 * cx - xx)):
                    my = np.clip(np.round(my).astype(int), 0, alpha.shape[0] - 1)
                    mx = np.clip(np.round(mx).astype(int), 0, alpha.shape[1] - 1)
                    cand.append(np.where(meas[my, mx], alpha[my, mx], np.inf))
                m = np.min(cand, axis=0)
                full = np.where(meas, alpha, np.where(np.isfinite(m), m, 0.0))
                a = np.clip(full, 0.0, 0.9)[..., None]
                out = np.clip((patch - a * 255.0) / (1.0 - a), 0, 255)
                body = ~meas
                rough = (np.abs(np.diff(out, axis=0)).sum(axis=2)[body[1:]].sum()
                         + np.abs(np.diff(out, axis=1)).sum(axis=2)[body[:, 1:]].sum())
                if best is None or rough < best[0]:
                    best = (rough, out)
        c[y0:y1, x0:x1] = best[1]
        found += 1
    return c.astype(np.uint8), found


def guide_mask(img: np.ndarray) -> np.ndarray:
    d = np.abs(img[..., :3].astype(int) - MAGENTA).sum(axis=2)
    return d > 60


def iou(a: np.ndarray, b: np.ndarray) -> float:
    u = np.logical_or(a, b).sum()
    return float(np.logical_and(a, b).sum() / u) if u else 0.0


def resize_mask(m: np.ndarray, s: float) -> np.ndarray:
    h, w = m.shape
    im = Image.fromarray((m * 255).astype(np.uint8)).resize((max(1, round(w * s)), max(1, round(h * s))), Image.BILINEAR)
    return np.asarray(im) > 127


def place(m: np.ndarray, shape: tuple, dx: int, dy: int) -> np.ndarray:
    """m을 (dx, dy)만큼 옮겨 shape 크기 판에 놓는다 (넘치는 곳은 자른다)"""
    out = np.zeros(shape, bool)
    h, w = m.shape
    y0, x0 = max(dy, 0), max(dx, 0)
    y1, x1 = min(dy + h, shape[0]), min(dx + w, shape[1])
    if y1 > y0 and x1 > x0:
        out[y0:y1, x0:x1] = m[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
    return out


def fit(mask: np.ndarray, guide: np.ndarray) -> tuple[float, int, int, float]:
    """mask(칸 그림 윤곽)를 배율 s·이동 (dx, dy)로 guide에 맞춘다. 무게중심으로 이동을 정하고 주변을 조금 더 찾는다"""
    gy, gx = np.nonzero(guide)
    gc = np.array([gx.mean(), gy.mean()])
    best = (0.0, 0, 0, 1.0)
    for s in SCALES:
        m = resize_mask(mask, s)
        my, mx = np.nonzero(m)
        if len(mx) == 0:
            continue
        base = np.round(gc - np.array([mx.mean(), my.mean()])).astype(int)
        for ddy in range(-6, 7, 2):
            for ddx in range(-6, 7, 2):
                v = iou(place(m, guide.shape, base[0] + ddx, base[1] + ddy), guide)
                if v > best[0]:
                    best = (v, base[0] + ddx, base[1] + ddy, s)
    v, dx, dy, s = best
    m = resize_mask(mask, s)
    for ddy in (-1, 0, 1):
        for ddx in (-1, 0, 1):
            w = iou(place(m, guide.shape, dx + ddx, dy + ddy), guide)
            if w > v:
                v, best = w, (w, dx + ddx, dy + ddy, s)
    return best


def mirror_guide(gm: np.ndarray, origin_x: float) -> np.ndarray:
    """가이드 칸을 원점 세로줄을 축으로 좌우로 뒤집는다 (게임이 왼쪽 반을 그리는 방법)"""
    h, w = gm.shape
    out = np.zeros_like(gm)
    xs = np.arange(w)
    src = np.round(2 * origin_x - xs).astype(int)
    ok = (src >= 0) & (src < w)
    out[:, xs[ok]] = gm[:, src[ok]]
    return out


def nose_bias(mask: np.ndarray, fwd: np.ndarray) -> float:
    """윤곽이 기수 쪽으로 얼마나 치우쳤나: 화면 기수 방향 축으로 본 무게중심 − 양 끝 가운데 (윤곽 길이로 나눈 값).
    헬기는 코 쪽이 굵은 동체, 꼬리 쪽이 가는 붐이라 +로 나온다. 코·꼬리를 바꿔 그린 그림은 −로 나온다"""
    ys, xs = np.nonzero(mask)
    if len(xs) < 50:
        return 0.0
    t = xs * fwd[0] + ys * fwd[1]
    span = t.max() - t.min()
    return float((t.mean() - (t.max() + t.min()) / 2.0) / span) if span > 1e-6 else 0.0


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    debug = "--debug" in sys.argv
    vid = args[0] if args else "sp_heli"
    info = json.loads((GUIDES / f"{vid}.json").read_text())
    cell = info["cell"]
    grids = info["sheets"]
    gscale = info["scale"]
    cells = {(c["sheet"], c["index"]): c for c in info["cells"]}
    # 17방향 가이드 칸 (같은 칸 좌표계) + 좌우로 뒤집은 것 — 방향 판정용
    guide_cells = {}
    basis = np.array(info["basis"])   # 열 = 월드 x·y 축의 화면 방향
    for c in info["cells"]:
        g = np.asarray(Image.open(GUIDES / f"{vid}_{c['sheet']}_guide.png").convert("RGB"))
        x0, y0 = c["col"] * cell, c["row"] * cell
        gc = g[y0:y0 + cell, x0:x0 + cell]
        gm = guide_mask(gc)
        ox = c["origin"][0] - x0
        guide_cells[c["k"]] = (gm, mirror_guide(gm, ox))
    k_n = len(guide_cells)
    out_scale = OUT_SCALE / gscale
    out_cell = int(np.ceil(cell * out_scale))
    sheet = Image.new("RGBA", (out_cell * k_n, out_cell), (0, 0, 0, 0))
    found = {}
    debug_tiles = []
    seen_cells = []   # 앞 시트들의 칸 그림 — 생성기가 앞 시트를 그대로 베껴 낸 칸을 가린다
    for sheet_name in grids:
        path = SRC / f"{vid}_{sheet_name}.png"
        if not path.exists():
            continue
        skip_path = SRC / f"{vid}_{sheet_name}.skip.txt"
        skip = {int(t) for t in skip_path.read_text().split()} if skip_path.exists() else set()
        keep_path = SRC / f"{vid}_{sheet_name}.keep.txt"
        keep = {int(t) for t in keep_path.read_text().split()} if keep_path.exists() else set()
        src = Image.open(path).convert("RGB")
        clean, stars = remove_sparkle(np.asarray(src))
        if stars:
            print(f"{sheet_name}: 워터마크 별 {stars}개 지움")
            src = Image.fromarray(clean)
        # 생성기가 캔버스 크기를 바꿔도 칸 배치는 지킨다 — 가이드 시트 크기로 늘이고 줄인다
        cols, rows = grids[sheet_name]
        src = src.resize((cols * cell, rows * cell), Image.LANCZOS)
        raw_all = np.asarray(src).astype(int)
        rgb_all, a_all = unmix_magenta(np.asarray(src))
        for (sh, idx), c in sorted(cells.items(), key=lambda t: (t[0][0], t[0][1])):
            if sh != sheet_name:
                continue
            x0, y0 = c["col"] * cell, c["row"] * cell
            rgb = rgb_all[y0:y0 + cell, x0:x0 + cell]
            a = a_all[y0:y0 + cell, x0:x0 + cell]
            mask = a > 127
            gm = guide_cells[c["k"]][0]
            v, dx, dy, s = fit(mask, gm)
            placed = place(resize_mask(mask, s), gm.shape, dx, dy)
            scores = []
            for k, (g0, g1) in guide_cells.items():
                scores.append((iou(placed, g0), k, False))
                if k not in (0, k_n - 1):
                    scores.append((iou(placed, g1), k, True))
            scores.sort(reverse=True)
            own = max(t[0] for t in scores if t[1] == c["k"] and not t[2])
            rival = next(t for t in scores if not (t[1] == c["k"] and not t[2]))
            # 칸 그림을 가이드 좌표로 옮긴다 (배율 s, 이동 dx·dy)
            tile = Image.fromarray(np.dstack([rgb, a]))
            tile = tile.resize((round(cell * s), round(cell * s)), Image.LANCZOS)
            fitted = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
            fitted.paste(tile, (dx, dy), tile)
            # 앞뒤: 기수 방향 축으로 본 윤곽 치우침이 가이드와 같은 쪽인가 (헬기 앞 = 차 기준 −y)
            r = c["rotation"]
            fwd = basis[:, 0] * np.sin(r) + basis[:, 1] * -np.cos(r)
            fwd = fwd / np.linalg.norm(fwd)
            want = nose_bias(gm, fwd)
            got = nose_bias(np.asarray(fitted)[..., 3] > 127, fwd)
            agree = got / want if abs(want) > 0.02 else 1.0
            # (배경을 지운 색은 마젠타 근처 잡음을 키우므로 받은 그림 그대로 견준다)
            raw = raw_all[y0:y0 + cell, x0:x0 + cell]
            # 헬기가 있는 픽셀(두 칸 윤곽을 합친 곳)만 견준다 — 칸 대부분이 배경이라 칸 전체 평균은 다른 그림도 작게 나온다
            def same(d):
                both = d[2] | mask
                return both.any() and iou(d[2], mask) > 0.9 and np.abs(d[1] - raw)[both].mean() < 12
            dup = next((d[0] for d in seen_cells if same(d)), None)
            ok = False
            why = "ok"
            if (idx + 1) in skip:
                why = "skip.txt"
            elif v < MIN_IOU:
                why = f"low overlap {v:.2f}"
            elif own + MARGIN < rival[0]:
                why = f"copy of k{rival[1]}{'m' if rival[2] else ''} {rival[0]:.2f}"
            elif dup:
                why = f"same picture as {dup}"
            elif agree < 0.0 and (idx + 1) not in keep:
                why = f"reversed (nose {got:+.2f} vs {want:+.2f})"
            else:
                ok = True
            print(f"{sheet_name}{idx + 1} k{c['k']:2d}  겹침 {v:.3f}  배율 {s:.2f}  이동 ({dx:+d},{dy:+d})  "
                  f"가장 닮은 k{rival[1]}{'뒤' if rival[2] else ''} {rival[0]:.3f}  앞쏠림 {got:+.2f}/{want:+.2f}  → {why}")
            seen_cells.append((f"{sheet_name}{idx + 1}", raw, mask))
            if debug:
                debug_tiles.append((sheet_name, idx, c["k"], fitted.copy(), gm, ok, why))
            if not ok:
                continue
            small = fitted.resize((out_cell, out_cell), Image.LANCZOS)
            # 같은 방향을 두 시트가 그렸으면 더 잘 겹치는 것
            if c["k"] in found and found[c["k"]]["iou"] >= v:
                continue
            sheet.paste((0, 0, 0, 0), (c["k"] * out_cell, 0, (c["k"] + 1) * out_cell, out_cell))
            sheet.paste(small, (c["k"] * out_cell, 0))
            ox = (c["origin"][0] - x0) * out_scale
            oy = (c["origin"][1] - y0) * out_scale
            found[c["k"]] = {"k": c["k"], "rotation": c["rotation"], "origin": [ox, oy], "iou": round(v, 3),
                             "source": f"{sheet_name}{idx + 1}"}
    if not found:
        print("쓸 칸이 없다")
        sys.exit(1)
    OUT.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT / f"{vid}.png")
    meta = {
        "id": vid, "dirs": info["dirs"], "cell": out_cell, "scale": OUT_SCALE,
        "rotor_z": info["rotor_z"], "bank_pivot": info["bank_pivot"],
        # k번째 칸 = 회전 −45° + k × 11.25° (화면 ↑ → → → ↓). 왼쪽 반은 좌우로 뒤집어 쓴다 (회전 r ↔ −90° − r)
        "frames": [found[k] for k in sorted(found)],
    }
    (OUT / f"{vid}.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))
    missing = [k for k in range(k_n) if k not in found]
    # 빠진 방향은 한 칸 옆 그림이 있으면 게임이 비틀어 쓰고, 없으면 코드 모형으로 그린다
    near = lambda k: any(n in found for n in (k - 1, k + 1))
    twisted = [k for k in missing if near(k)]
    code = [k for k in missing if not near(k)]
    print(f"저장: assets/vehicles/sprites/{vid}.png ({len(found)}/{k_n}방향, 칸 {out_cell}px)"
          + (f" · 옆 칸을 비틀어 메움 k{twisted}" if twisted else "")
          + (f" · 코드 모형 k{code}" if code else ""))
    # 게임은 가져온(.import) 그림을 먼저 읽는다 — 다시 가져오지 않으면 예전 그림과 새 칸 목록이 섞여 빈 칸이 그려진다
    print("다음: godot --headless --path . --import  (가져온 그림을 새로 고친다)")
    if debug:
        _debug_sheet(vid, debug_tiles, cell)


def _debug_sheet(vid: str, tiles: list, cell: int) -> None:
    n = len(tiles)
    cols = 6
    rows = (n + cols - 1) // cols
    out = Image.new("RGB", (cols * cell, rows * cell), (40, 40, 44))
    for i, (sh, idx, k, img, gm, ok, why) in enumerate(tiles):
        x0, y0 = (i % cols) * cell, (i // cols) * cell
        bg = Image.new("RGBA", (cell, cell), (70, 70, 76, 255) if ok else (110, 40, 40, 255))
        bg.alpha_composite(img)
        # 가이드 윤곽(하늘색)
        edge = gm & ~(np.roll(gm, 1, 0) & np.roll(gm, -1, 0) & np.roll(gm, 1, 1) & np.roll(gm, -1, 1))
        px = np.asarray(bg).copy()
        px[edge] = [80, 220, 255, 255]
        tile = Image.fromarray(px)
        d = ImageDraw.Draw(tile)
        d.text((8, 8), f"{sh}{idx + 1} k{k}  {why}", fill=(255, 255, 255, 255))
        out.paste(tile.convert("RGB"), (x0, y0))
    p = SRC / f"{vid}_fit_debug.png"
    out.save(p)
    print(f"확인 그림: {p.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
