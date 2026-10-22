#!/usr/bin/env python3
"""제미나이가 회색 가이드 위에 덧칠한 건물 한 채를 게임 그림으로 다듬는다 (GEMINI_BUILDING_PROMPT.md 방식 B).

입력  output/imagegen/buildings/whole/<ID>_<부지>.png          낮 그림 (마젠타 배경)
      output/imagegen/buildings/whole/<ID>_<부지>_lights.png   밤 불빛 그림 (검정 배경. 어두운 밤 건물이 비쳐도 된다)
      output/imagegen/buildings/guides/<ID>_<부지>.json · _mass.png   tools/building_guide.tscn이 낸 가이드
출력  assets/buildings/whole/<id>_<부지>.png · _lights.png · .json   (BuildingSprite가 읽는다)

생성기는 캔버스 크기를 바꿔 그리곤 한다(교회: 가이드 1958×1146 → 1376×768). 그래서 그림을 가이드에 맞춰 다시 잡는다:
부지 바닥 마름모의 네 변(사선)을 그림과 가이드에서 찾아 배율·위치를 정한다. 변은 건물에 가려도 보이는 토막만 쓰고,
부지 모서리가 캔버스 밖으로 잘려도 남은 변으로 맞춘다(유흥 건물). 잘려 나간 부지는 가이드 색 참고(_ref.png)로 메운다.
불빛 그림이 낮 그림과 크기·구도가 다르면(소방서) 윤곽선을 겹쳐 보며 배율·위치를 찾아 낮 그림에 맞춘다.
.json에는 부지 가운데의 그림 좌표(origin)와 화면 1px당 그림 px(scale)를 적는다 — 게임은 월드 점마다 그 그림 좌표를 계산해 붙인다.

사용: python3 tools/prepare_building_sprites.py [ID_부지 ...] [--debug]
--debug 면 가이드 윤곽을 겹친 그림을 output/imagegen/buildings/whole/<ID>_<부지>_fit_debug.png 로 낸다.
"""

import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_building_textures import bleed, despill, grow, magenta, pinkish  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "output/imagegen/buildings/whole"
GUIDES = ROOT / "output/imagegen/buildings/guides"
DST = ROOT / "assets/buildings/whole"


def extremes(solid: np.ndarray) -> tuple:
    """덩어리의 왼쪽 끝 x · 오른쪽 끝 x · 아래 끝 y (작은 표식 점은 줄 단위 문턱으로 버린다)."""
    cols = np.where(solid.sum(0) > 3)[0]
    rows = np.where(solid.sum(1) > 20)[0]
    return float(cols[0]), float(cols[-1] + 1), float(rows[-1] + 1)


def largest(solid: np.ndarray) -> np.ndarray:
    """가장 큰 이어진 덩어리 (4방향). 줄마다 토막을 잡아 윗줄 토막과 겹치면 잇는다 — 제미나이 표식(✦) 같은 떨어진 점을 버린다."""
    h, w = solid.shape
    parent: list = []

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    rows = []
    for y in range(h):
        d = np.diff(np.concatenate([[0], solid[y].astype(np.int8), [0]]))
        st, en = np.where(d == 1)[0], np.where(d == -1)[0]
        ids = list(range(len(parent), len(parent) + len(st)))
        parent.extend(ids)
        if rows:
            pst, pen, pids = rows[-1]
            j = 0
            for a, b, i in zip(st, en, ids):
                while j < len(pst) and pen[j] <= a:
                    j += 1
                k = j
                while k < len(pst) and pst[k] < b:
                    ra, rb = find(i), find(pids[k])
                    if ra != rb:
                        parent[ra] = rb
                    k += 1
        rows.append((st, en, ids))
    area: dict = {}
    for st, en, ids in rows:
        for a, b, i in zip(st, en, ids):
            r = find(i)
            area[r] = area.get(r, 0) + int(b - a)
    if not area:
        return solid.copy()
    best = max(area, key=area.get)
    out = np.zeros_like(solid)
    for y, (st, en, ids) in enumerate(rows):
        for a, b, i in zip(st, en, ids):
            if find(i) == best:
                out[y, a:b] = True
    return out


EDGES = (("tl", -0.5, "top"), ("tr", 0.5, "top"), ("bl", 0.5, "bottom"), ("br", -0.5, "bottom"))


def _edge_peak(x: np.ndarray, y: np.ndarray, sl: float, need: int):
    """기울기 sl로 절편을 모아 가장 바깥(c가 가장 큰) 묶음의 (절편, 묶음 크기). 없으면 None."""
    c = y - sl * x
    lo = int(np.floor(c.min()))
    hist = np.bincount((np.round(c) - lo).astype(int))
    sm = np.convolve(hist, np.ones(5, int), mode="same")
    peaks = [i for i in range(len(sm)) if sm[i] >= need and sm[i] == sm[max(0, i - 3):i + 4].max()]
    if not peaks:
        return None
    return peaks[-1] + lo, int(sm[peaks[-1]])


def lot_edges(solid: np.ndarray, free_slope: bool = False) -> dict:
    """부지 마름모 네 변 위의 점: {변: (xs, ys, 기울기, 절편)}.
    칸마다 맨 위·맨 아래 점을 잡고, 변 기울기(±0.5)로 절편 c = y − s·x를 모아 한 값에 몰린 묶음을 변으로 본다.
    건물 지붕선도 같은 기울기라 묶음이 여럿 생기는데, 부지 변은 늘 가장 바깥(c가 가장 큰 묶음)이다.
    캔버스 끝에 닿은 칸(잘린 부지)은 쓰지 않는다. free_slope면 생성기가 마름모를 비틀어 그린 경우를 위해
    기울기를 ±15% 안에서 찾아 가장 곧게 몰리는 값을 쓴다."""
    h, w = solid.shape
    xs = np.where(solid.any(0))[0]
    top = solid.argmax(0)[xs]
    bot = h - 1 - solid[::-1].argmax(0)[xs]
    need = max(20, w // 40)
    out = {}
    for name, sl, side in EDGES:
        ys = top if side == "top" else bot
        ok = (ys > 0) if side == "top" else (ys < h - 1)
        x, y = xs[ok].astype(float), ys[ok].astype(float)
        if len(x) < need:
            continue
        best = None
        for f in (np.linspace(0.85, 1.15, 31) if free_slope else [1.0]):
            pk = _edge_peak(x, y, sl * f, need)
            if pk and (best is None or pk[1] > best[2]):
                best = (sl * f, pk[0], pk[1])
        if best is None:
            continue
        sel = np.abs(y - best[0] * x - best[1]) <= 2.5
        a, b = np.polyfit(x[sel], y[sel], 1)
        sel = np.abs(y - (a * x + b)) <= 2.0
        if sel.sum() < need:
            continue
        a, b = np.polyfit(x[sel], y[sel], 1)
        out[name] = (x[sel], y[sel], a, b)
    return out


def fit_affine(gedge: dict, iedge: dict):
    """비틀린 그림용: 그림 점 p'을 가이드 점 p = B·p' + u로 옮겨 가이드 변(−s·x + y = c) 위에 오게 하는 B·u.
    변 넷이 다 보일 때만 쓴다. (B, u, 가이드 px 잔차)"""
    used = [n for n, _, _ in EDGES if n in gedge and n in iedge]
    if len(used) < 4:
        return None
    rows, rhs, wts = [], [], []
    for n in used:
        s, c = gedge[n][2], gedge[n][3]
        x, y = iedge[n][0], iedge[n][1]
        wt = 1.0 / np.sqrt(len(x))
        nx, ny = -s, 1.0
        for xi, yi in zip(x, y):
            rows.append([nx * xi, nx * yi, ny * xi, ny * yi, nx, ny])
            rhs.append(c)
            wts.append(wt)
    A, bvec, W = np.array(rows), np.array(rhs), np.array(wts)
    sol, *_ = np.linalg.lstsq(A * W[:, None], bvec * W, rcond=None)
    res = (A @ sol - bvec) / np.sqrt(1.25)        # 법선 길이(√(s²+1))로 나눠 px 거리로
    B = np.array([[sol[0], sol[1]], [sol[2], sol[3]]])
    return B, np.array([sol[4], sol[5]]), float(np.sqrt(np.mean(res ** 2)))


def fit_lot(gedge: dict, iedge: dict):
    """가이드 변(정확한 2:1)에 그림 변 점들을 맞춘다: 그림 = 가이드 × k + (ox, oy).
    가이드 변 y = s·x + c는 그림에서 y' = s·x' + (k·c + oy − s·ox). 변마다 같은 무게로 최소제곱. (k, ox, oy, 잔차 px, 쓴 변)"""
    rows, rhs, wts = [], [], []
    used = [n for n, _, _ in EDGES if n in gedge and n in iedge]
    for n in used:
        s, c = gedge[n][2], gedge[n][3]
        x, y = iedge[n][0], iedge[n][1]
        wt = 1.0 / np.sqrt(len(x))
        for xi, yi in zip(x, y):
            rows.append([c, -s, 1.0])
            rhs.append(yi - s * xi)
            wts.append(wt)
    A, bvec, W = np.array(rows), np.array(rhs), np.array(wts)
    if len(used) < 3 or np.linalg.matrix_rank(A) < 3:
        return None
    sol, *_ = np.linalg.lstsq(A * W[:, None], bvec * W, rcond=None)
    res = A @ sol - bvec
    return float(sol[0]), float(sol[1]), float(sol[2]), float(np.sqrt(np.mean(res ** 2))), used


def edges_of(img: np.ndarray) -> np.ndarray:
    """윤곽선 세기 (밝기 기울기). 불빛·낮 그림을 겹쳐 맞출 때 쓴다."""
    g = img.astype(float).max(2) if img.ndim == 3 else img.astype(float)
    gx = np.abs(np.diff(g, axis=1, append=g[:, -1:]))
    gy = np.abs(np.diff(g, axis=0, append=g[-1:]))
    return np.sqrt(gx ** 2 + gy ** 2)


def register(day: np.ndarray, day_mask: np.ndarray, lit: np.ndarray):
    """불빛 그림을 낮 그림에 맞출 배율 s·이동 (tx, ty): 낮 = 불빛 × s + t. 창틀 윤곽을 겹쳐 가장 잘 맞는 곳을 찾는다."""
    D = 2   # 반으로 줄여 찾고, 찾은 뒤 원래 크기로
    def small(a, size):
        return np.asarray(Image.fromarray(a.astype(np.float32)).resize(size, Image.BILINEAR))
    dh, dw = day.shape[:2]
    de = edges_of(day) * day_mask
    de = small(de, (dw // D, dh // D))
    le_full = edges_of(lit)
    lh, lw = lit.shape[:2]
    H, W = de.shape[0] * 2, de.shape[1] * 2
    FD = np.fft.rfft2(de - de.mean(), s=(H, W))

    def score(sc):
        sz = (max(8, round(lw * sc / D)), max(8, round(lh * sc / D)))
        le = small(le_full, sz)
        if le.shape[0] >= H or le.shape[1] >= W:
            return -1, 0, 0
        FL = np.fft.rfft2(le - le.mean(), s=(H, W))
        cc = np.fft.irfft2(FD * np.conj(FL), s=(H, W))
        i = int(cc.argmax())
        py, px = divmod(i, W)
        if py > H // 2:
            py -= H
        if px > W // 2:
            px -= W
        return cc.flat[i] / (np.linalg.norm(le) + 1e-9), px * D, py * D

    best = (-1, 1.0, 0, 0)
    for sc in np.arange(0.70, 1.45, 0.01):
        v, tx, ty = score(sc)
        if v > best[0]:
            best = (v, sc, tx, ty)
    for sc in np.arange(best[1] - 0.01, best[1] + 0.011, 0.002):
        v, tx, ty = score(sc)
        if v > best[0]:
            best = (v, sc, tx, ty)
    ident = score(1.0) if lit.shape == day.shape else (0, 0, 0)
    return best[1], best[2], best[3], best[0], ident[0]


def warp(img: np.ndarray, size: tuple, sc: float, tx: float, ty: float) -> np.ndarray:
    """img를 낮 그림 캔버스(size)로 옮긴다: 낮 = img × sc + t."""
    im = Image.fromarray(img)
    return np.asarray(im.transform(size, Image.AFFINE, (1 / sc, 0, -tx / sc, 0, 1 / sc, -ty / sc), Image.BILINEAR))


def guide_key(name: str) -> str:
    """컨셉을 달리 그린 그림(<ID>_<부지>_<컨셉> — 공원)은 같은 부지 가이드 <ID>_<부지>를 쓴다."""
    m = re.match(r"^(.*_(?:full|half_x|half_y|quarter))_[a-z0-9]+$", name)
    return m.group(1) if m else name


def prepare(name: str, debug: bool) -> None:
    day_p = SRC / f"{name}.png"
    lit_p = SRC / f"{name}_lights.png"
    if not day_p.exists():
        sys.exit(f"받은 그림이 없다: {day_p.relative_to(ROOT)} — 제미나이 그림을 이 이름으로 저장한다")
    if not (GUIDES / f"{guide_key(name)}.json").exists():
        sys.exit(f"가이드가 없다: {name} — building_guide.tscn -- --ids=<ID>로 먼저 뽑는다 (부지 이름은 full·half_x·half_y·quarter)")
    guide = json.loads((GUIDES / f"{guide_key(name)}.json").read_text())
    mass = np.asarray(Image.open(GUIDES / f"{guide_key(name)}_mass.png").convert("RGB"))
    ref_p = GUIDES / f"{guide_key(name)}_ref.png"
    ref = np.asarray(Image.open(ref_p).convert("RGB")) if ref_p.exists() else None
    day = np.asarray(Image.open(day_p).convert("RGB"))
    lit = np.asarray(Image.open(lit_p).convert("RGB")) if lit_p.exists() else None
    if lit is not None and magenta(day).mean() < 0.05 and magenta(lit).mean() > 0.2:
        # 두 장 이름이 바뀌어 저장된 경우 (지하철): 마젠타 배경이 낮 그림, 검은 배경이 불빛 그림
        print("  낮·불빛 그림 이름이 바뀌어 있다 — 마젠타 배경 쪽을 낮 그림으로 쓴다")
        day, lit = lit, day

    solid = ~magenta(day)
    main = largest(solid)
    gsolid = ~magenta(mass)
    gedge = lot_edges(gsolid)
    fit = fit_lot(gedge, lot_edges(main))
    if fit:
        k, ox, oy, err, used = fit
        how = f"부지 변 {'·'.join(used)} · 잔차 {err:.1f}px"
    else:
        # 변이 셋 안 보이면 예전 방식: 좌·우·아래 끝
        gl, gr, gb = extremes(gsolid)
        il, ir, ib = extremes(main)
        k = (ir - il) / (gr - gl)
        ox, oy = il - gl * k, ib - gb * k
        err = 0.0
        how = "부지 끝점 (변을 셋 못 찾음)"
    print(f"{name}: 가이드 {mass.shape[1]}×{mass.shape[0]} → 그림 {day.shape[1]}×{day.shape[0]} · 배율 {k:.4f} · {how}")
    unskew = None
    if err > 3:
        aff = fit_affine(gedge, lot_edges(main, free_slope=True))
        if aff and aff[2] * k < err * 0.6:
            unskew = aff
    if unskew is None and err > 4:
        print("  ⚠ 부지 변이 가이드와 잘 안 맞는다 — 그림의 시점·비율이 가이드와 다를 수 있다. --debug로 겹쳐 본다")

    # 불빛 그림: 크기가 다르거나 어긋났으면 낮 그림에 맞춘다
    if lit is not None and lit.shape != day.shape and all(abs(a - b) <= 3 for a, b in zip(lit.shape[:2], day.shape[:2])):
        # 1~3px만 다르면 같은 캔버스에 그린 것이다 — 켜진 곳이 몇 점뿐인 불빛(창고 문 위 등)은 윤곽 맞추기가 엉뚱한 데 걸리니
        # 찾지 않고 낮 그림 크기로 늘린다
        print(f"  불빛 그림 {lit.shape[1]}×{lit.shape[0]} → 낮 그림 크기로 늘림")
        lit = np.asarray(Image.fromarray(lit).resize((day.shape[1], day.shape[0]), Image.BILINEAR))
    elif lit is not None:
        sc, tx, ty, v, v0 = register(day, solid, lit)
        # 같은 캔버스면 1.5배 넘게 더 잘 겹칠 때만 옮긴다 (창고 불빛은 1.2배 '더 잘 맞는' 지붕 쪽으로 잘못 옮겨졌다)
        moved = lit.shape != day.shape or (abs(sc - 1) > 0.004 or abs(tx) > 2 or abs(ty) > 2) and v > v0 * 1.5
        if moved:
            print(f"  불빛 그림을 낮 그림에 맞춤: {lit.shape[1]}×{lit.shape[0]} × {sc:.3f} + ({tx:+.0f}, {ty:+.0f})"
                  f" · 일치 {v / max(v0, 1e-9):.2f}배" if v0 > 0 else
                  f"  불빛 그림을 낮 그림에 맞춤: {lit.shape[1]}×{lit.shape[0]} × {sc:.3f} + ({tx:+.0f}, {ty:+.0f})")
            lit = warp(lit, (day.shape[1], day.shape[0]), sc, tx, ty)

    if unskew is not None:
        # 비틀린 그림을 가이드와 같은 2:1로 편다: 새 캔버스 점 q = k·p + (m, m) (p = 가이드 점) ← 그림 점 p' = B⁻¹(p − u)
        B, u, aerr = unskew
        Ainv = np.linalg.inv(B)
        m = 10
        size = (round(mass.shape[1] * k) + 2 * m, round(mass.shape[0] * k) + 2 * m)
        # 출력 q → 입력 p': p = (q − m)/k, p' = Ainv·(p − u)
        M = Ainv / k
        t = -Ainv @ (u + np.array([m, m]) / k)
        coef = (M[0, 0], M[0, 1], t[0], M[1, 0], M[1, 1], t[1])
        def unwarp(a, fill):
            return np.asarray(Image.fromarray(a).transform(size, Image.AFFINE, coef, Image.BICUBIC, fillcolor=fill))
        day = unwarp(day, (255, 0, 255))
        if lit is not None:
            lit = unwarp(lit, (0, 0, 0))
        solid = ~magenta(day)
        ox = oy = float(m)
        sh = np.degrees(np.arctan2(Ainv[1, 0], Ainv[0, 0]))
        print(f"  그림이 비틀려 있다 (잔차 {err:.1f}px) — 2:1로 펴서 맞춤 · 남은 잔차 {aerr * k:.1f}px")

    # 부지가 캔버스 밖으로 잘렸으면 캔버스를 넓힌다 (가이드 덩어리 전체가 들어가게)
    gys, gxs = np.where(gsolid)
    x0 = int(np.floor(gxs.min() * k + ox)) - 2
    y0 = int(np.floor(gys.min() * k + oy)) - 2
    x1 = int(np.ceil((gxs.max() + 1) * k + ox)) + 2
    y1 = int(np.ceil((gys.max() + 1) * k + oy)) + 2
    pl, pt = max(0, -x0), max(0, -y0)
    pr, pb = max(0, x1 - day.shape[1]), max(0, y1 - day.shape[0])
    h0, w0 = day.shape[:2]
    if pl or pt or pr or pb:
        print(f"  부지가 캔버스 밖으로 잘려 있다 — 좌{pl}·위{pt}·우{pr}·아래{pb}px 넓히고 가이드 색 참고로 메운다")
        padw = ((pt, pb), (pl, pr), (0, 0))
        day = np.pad(day, padw, constant_values=0)
        if lit is not None:
            lit = np.pad(lit, padw, constant_values=0)
        solid = np.pad(solid, padw[:2], constant_values=False)
        ox, oy = ox + pl, oy + pt
    h, w = solid.shape
    outside = np.ones((h, w), bool)
    outside[pt:pt + h0, pl:pl + w0] = False

    # 부지 바닥 마름모 (가이드 네 변을 그림으로 옮긴 것). 생성기가 부지를 좁게 그려 생긴 빈 틈을 찾는 데 쓴다
    yy, xx = np.mgrid[0:h, 0:w]
    lot = np.ones((h, w), bool)
    for n, _, side in EDGES:
        if n in gedge:
            s_, c_ = gedge[n][2], gedge[n][3]
            line = s_ * xx + (k * c_ + oy - s_ * ox)
            lot &= (yy >= line + 1) if side == "top" else (yy <= line - 1)
    gap = lot & ~solid & ~outside
    if (outside.any() or gap.any()) and ref is not None:
        # 잘린 부분과 부지 안 빈 틈: 가이드 색 참고를 같은 배율로 줄여 그 자리에 깐다
        rs = Image.fromarray(ref).resize((round(ref.shape[1] * k), round(ref.shape[0] * k)), Image.LANCZOS)
        canvas = Image.new("RGB", (w, h), (255, 0, 255))
        canvas.paste(rs, (round(ox), round(oy)))
        cv = np.asarray(canvas)
        fill = (outside | gap) & ~magenta(cv)
        if gap.sum() > 200:
            print(f"  부지 안 빈 틈 {int(gap.sum())}px — 가이드 색 참고로 메운다")
        day = np.where(fill[..., None], cv, day)
        solid = solid | fill

    origin = (guide["origin"][0] * k + ox, guide["origin"][1] * k + oy)
    scale = guide["scale"] * k

    bg = ~solid
    keep = solid & ~(grow(bg, 2) & pinkish(day))
    # 표식 점 지우기: 부지 마름모 아래 두 변 밑, 좌·우 끝 밖에 있는 것 (가이드 변을 그림으로 옮겨 쓴다)
    for n in ("bl", "br"):
        if n in gedge:
            s_, c_ = gedge[n][2], gedge[n][3]
            keep &= ~(yy > s_ * xx + (k * c_ + oy - s_ * ox) + 3)
    keep &= (xx >= gxs.min() * k + ox - 3) & (xx <= (gxs.max() + 1) * k + ox + 3)
    rgba = np.dstack([despill(day, grow(bg, 5)), np.where(keep, 255, 0).astype(np.uint8)])
    DST.mkdir(parents=True, exist_ok=True)
    base = name.lower()
    Image.fromarray(bleed(rgba)).save(DST / f"{base}.png")
    if lit is not None:
        lum = lit.max(2).astype(float)
        a = np.clip((lum - 45.0) / 70.0, 0.0, 1.0)
        a[~keep] = 0.0
        Image.fromarray(bleed(np.dstack([lit, (a * 255).astype(np.uint8)]), 3)).save(DST / f"{base}_lights.png")
    info = {"id": guide["id"], "lot": guide["lot"], "lot_size": guide["lot_size"], "seed": guide["seed"],
            "size": [w, h], "origin": [round(origin[0], 2), round(origin[1], 2)], "scale": round(scale, 5)}
    margin = piece_margins(name, guide, keep, origin, scale, rgba[..., :3])
    if margin is not None:
        margin = forced_margins(name, margin)
    if margin is None:
        margin = hull_margin(name, guide, keep, origin, scale)
        if margin:
            info["hull_lift"], info["hull_grow"] = margin
    elif margin:
        info["hull_pieces"] = {str(i): list(m) for i, m in sorted(margin.items())}
    (DST / f"{base}.json").write_text(json.dumps(info, ensure_ascii=False, indent=2))
    print(f"  → {DST.relative_to(ROOT)}/{base}.png (화면 1px = 그림 {scale:.2f}px)" + (" + 불빛" if lit is not None else ""))

    if debug:
        # 가이드 덩어리 윤곽(하늘색)을 낮 그림에, 불빛(노랑)을 반투명으로 겹친다
        g = Image.fromarray(mass).resize((round(mass.shape[1] * k), round(mass.shape[0] * k)), Image.NEAREST)
        gm = ~magenta(np.asarray(g))
        edge = gm ^ grow(gm, 1)
        ov = day.copy()
        if lit is not None:
            la = (np.clip((lit.max(2).astype(float) - 45.0) / 70.0, 0, 1) * 0.6)[..., None]
            ov = (ov * (1 - la) + np.array([255, 230, 60]) * la).astype(np.uint8)
        ys, xs = np.where(edge)
        ys = ys + round(oy)
        xs = xs + round(ox)
        ok = (ys >= 0) & (ys < h) & (xs >= 0) & (xs < w)
        ov[ys[ok], xs[ok]] = (0, 255, 255)
        lost = lost_pixels(name, guide, keep, origin, scale, margin, rgba[..., :3])
        if lost is not None:
            ov[lost] = (255, 40, 40)
            print(f"  윤곽을 넓히고도 잘리는 그림 {int(lost.sum())}px (빨강)")
        Image.fromarray(ov).save(SRC / f"{name}_fit_debug.png")


BASIS = np.array([[0.78, -0.78], [0.39, 0.39]])   # IsoView.BASIS (열 = x축·y축)


def _sweep(m: np.ndarray, up: int, side: int, down: int = 0) -> np.ndarray:
    """마스크를 위로 up px, 좌우로 side px, 아래로 down px까지 민 자국을 모두 더한다 (게임이 윤곽을 넓히는 것과 같다)."""
    out = m.copy()
    for d in range(1, side + 1):
        out[:, :-d] |= m[:, d:]
        out[:, d:] |= m[:, :-d]
    base = out.copy()
    for d in range(1, up + 1):
        out[:-d] |= base[d:]
    for d in range(1, down + 1):
        out[d:] |= base[:-d]
    return out


def hull_margin(name: str, guide: dict, keep: np.ndarray, origin, scale: float):
    """잘리는 그림이 거의 없어질 때까지 윤곽을 넓힐 몫 (화면 px: 위, 좌우). 윤곽 그림이 없으면 None.
    너무 넓히면 건물 바로 뒤를 지나는 사람이 일찍 가려지므로 위 32px·좌우 12px까지만."""
    cov = hull_cover(name, guide, keep.shape, origin, scale)
    if cov is None:
        return None
    hull, ground = cov
    lost0 = keep & ~hull & ~ground
    if lost0.sum() < 150:
        return None
    # 부지 테두리 밖 연석처럼 넓혀도 못 덮는 몫이 있다 — 가장 넓혔을 때 남는 양 + 조금을 목표로
    floor = (lost0 & ~_sweep(hull, round(32 * scale), round(12 * scale))).sum()
    goal = floor + max(150, (lost0.sum() - floor) * 0.04)
    best = None
    for side in (0, 2, 4, 6, 8, 10, 12):
        for up in range(0, 33, 2):
            left = (lost0 & ~_sweep(hull, round(up * scale), round(side * scale))).sum()
            if left <= goal:
                if best is None or up + side * 2 < best[0] + best[1] * 2:
                    best = (up, side)
                break
    best = best or (32, 12)
    print(f"  잘리는 그림 {int(lost0.sum())}px → 윤곽을 위 {best[0]}px·좌우 {best[1]}px 넓힌다")
    return best


def hull_cover(name: str, guide: dict, shape: tuple, origin, scale: float):
    """조각 윤곽(building_guide.tscn -- --hulls가 찍은 <이름>_hulls.png)과 부지 바닥 사각형(+인도)을 그림 좌표로.
    게임은 이 둘만 그리므로 그 밖의 그림은 잘려 안 보인다. 윤곽 그림이 없으면 None."""
    hp = GUIDES / f"{guide_key(name)}_hulls.png"
    if not hp.exists():
        return None
    hm = np.asarray(Image.open(hp).convert("RGBA"))[..., 3] > 0
    h, w = shape
    # 그림 px → 가이드 px: 가이드 = (그림 − origin) × (가이드 배율 / 그림 배율) + 가이드 origin
    f = guide["scale"] / scale
    yy, xx = np.mgrid[0:h, 0:w]
    gx = np.round((xx - origin[0]) * f + guide["origin"][0]).astype(int)
    gy = np.round((yy - origin[1]) * f + guide["origin"][1]).astype(int)
    inside = (gx >= 0) & (gy >= 0) & (gx < hm.shape[1]) & (gy < hm.shape[0])
    hull = np.zeros((h, w), bool)
    hull[inside] = hm[gy[inside], gx[inside]]
    # 부지 바닥: 그림 px → 월드 (부지 가운데 원점) 로 되돌려 사각형 안인가
    inv = np.linalg.inv(BASIS)
    sx = (xx - origin[0]) / scale
    sy = (yy - origin[1]) / scale
    wx = inv[0, 0] * sx + inv[0, 1] * sy
    wy = inv[1, 0] * sx + inv[1, 1] * sy
    hw, hh = guide["lot_size"][0] / 2 + 28.0, guide["lot_size"][1] / 2 + 28.0   # 인도(28)는 도시가 그린다
    return hull, (np.abs(wx) <= hw) & (np.abs(wy) <= hh)


def lost_pixels(name: str, guide: dict, keep: np.ndarray, origin, scale: float, margin=None, day=None):
    """윤곽(넓힌 몫 margin까지)에도 바닥에도 안 드는 그림 = 게임에서 잘려 안 보이는 곳. 윤곽 그림이 없으면 None.
    margin이 dict면 덩어리 번호마다의 몫 (piece_margins)."""
    if isinstance(margin, dict):
        pieces = hull_pieces(name, guide, keep.shape, origin, scale)
        hull = np.zeros(keep.shape, bool)
        for i, y0, x0, m in pieces:
            u, sd, dn = (list(margin.get(i, ())) + [0, 0, 0])[:3]
            _paste(hull, _sweep_win(m, y0, x0, keep.shape, round(u * scale), round(sd * scale), round(dn * scale)))
        band, below = curb_band(guide, hull, origin, scale, day)
        return keep & ~hull & ~lot_ground(guide, keep.shape, origin, scale, 28.0) & (~band | below)
    cov = hull_cover(name, guide, keep.shape, origin, scale)
    if cov is None:
        return None
    hull, ground = cov
    if margin:
        hull = _sweep(hull, round(margin[0] * scale), round(margin[1] * scale))
    return keep & ~hull & ~ground



# ── 덩어리마다 넓히기 ─────────────────────────────────────
# 접시·크레인·가로등처럼 한 덩어리만 모형보다 크게 그려진 곳은 그 덩어리 윤곽만 넓힌다 (BuildingSprite.piece_margins)
PIECE_LIFT, PIECE_GROW, PIECE_DROP = 48, 32, 32   # 덩어리 하나를 넓힐 최대 (화면 px: 위, 좌우, 아래)
CURB = 24.0                       # 부지+인도 밖 이만큼(월드)은 그림의 연석 — 도시 인도가 덮으니 넓혀 덮지 않는다


def lot_ground(guide: dict, shape: tuple, origin, scale: float, pad: float) -> np.ndarray:
    """부지 사각형 + pad(월드) 안인 그림 px."""
    h, w = shape
    yy, xx = np.mgrid[0:h, 0:w]
    inv = np.linalg.inv(BASIS)
    sx = (xx - origin[0]) / scale
    sy = (yy - origin[1]) / scale
    wx = inv[0, 0] * sx + inv[0, 1] * sy
    wy = inv[1, 0] * sx + inv[1, 1] * sy
    return (np.abs(wx) <= guide["lot_size"][0] / 2 + pad) & (np.abs(wy) <= guide["lot_size"][1] / 2 + pad)


def hull_pieces(name: str, guide: dict, shape: tuple, origin, scale: float):
    """덩어리마다 윤곽 (building_guide.tscn -- --hulls가 적은 <이름>_hulls.json) → [(번호, y0, x0, 마스크 조각)] 그림 좌표.
    없으면 None (예전 도구로 찍은 윤곽 — 건물 전체를 한 몫으로 넓힌다)."""
    jp = GUIDES / f"{guide_key(name)}_hulls.json"
    if not jp.exists():
        return None
    f = guide["scale"] / scale
    gx, gy = guide["origin"]
    by: dict = {}
    for d in json.loads(jp.read_text())["pieces"]:
        pts = [((x - gx) / f + origin[0], (y - gy) / f + origin[1]) for x, y in d["pts"]]
        if len(pts) >= 3:
            by.setdefault(d["index"], []).append(pts)
    h, w = shape
    out = []
    for i, polys in by.items():
        xs = [p[0] for ps in polys for p in ps]
        ys = [p[1] for ps in polys for p in ps]
        x0, y0 = max(0, int(min(xs)) - 1), max(0, int(min(ys)) - 1)
        x1, y1 = min(w, int(max(xs)) + 2), min(h, int(max(ys)) + 2)
        if x1 <= x0 or y1 <= y0:
            continue
        im = Image.new("1", (x1 - x0, y1 - y0), 0)
        dr = ImageDraw.Draw(im)
        for ps in polys:
            dr.polygon([(x - x0, y - y0) for x, y in ps], fill=1)
        out.append((i, y0, x0, np.asarray(im, bool)))
    return out


def _sweep_win(m: np.ndarray, y0: int, x0: int, shape: tuple, up: int, side: int, down: int = 0):
    """덩어리 마스크 조각을 위 up·좌우 side·아래 down px 넓힌 조각 (y0, x0, 마스크) — 그림 밖은 자른다."""
    h, w = shape
    wy0, wx0 = max(0, y0 - up), max(0, x0 - side)
    wy1, wx1 = min(h, y0 + m.shape[0] + down), min(w, x0 + m.shape[1] + side)
    big = np.zeros((wy1 - wy0, wx1 - wx0), bool)
    mh, mw = min(m.shape[0], wy1 - y0), min(m.shape[1], wx1 - x0)
    big[y0 - wy0:y0 - wy0 + mh, x0 - wx0:x0 - wx0 + mw] = m[:mh, :mw]
    return wy0, wx0, _sweep(big, up, side, down)


def _paste(dst: np.ndarray, win) -> None:
    y0, x0, m = win
    dst[y0:y0 + m.shape[0], x0:x0 + m.shape[1]] |= m


def curb_band(guide: dict, hull: np.ndarray, origin, scale: float, day=None):
    """부지+인도 둘레 띠(CURB)와, 그 띠 안에서도 덩어리 끝인 곳 (band, below).
    띠 안은 그림의 연석이라 도시 인도·차도가 덮는다 — 단, 바로 밑·옆(화면 8px 안)에 덩어리 윤곽이 있거나
    색이 있으면(회색 연석이 아니면) 덩어리 끝(처마·나무 끝·만국기)."""
    below = np.zeros(hull.shape, bool)
    for d in range(1, round(8 * scale) + 1):
        below[:-d] |= hull[d:]
        below[:, :-d] |= hull[:, d:]
        below[:, d:] |= hull[:, :-d]
    if day is not None:
        c = day.astype(int)
        below |= ((c.max(2) - c.min(2)) > 45) & ~pinkish(day)
    return lot_ground(guide, hull.shape, origin, scale, 28.0 + CURB), below


def forced_margins(name: str, margin: dict) -> dict:
    """<이름>.hull.txt의 줄마다 `덩어리번호 위 좌우 [아래]`(화면 px)를 자동 몫과 겹쳐 큰 쪽을 쓴다.
    회색 벽 끝이 부지 둘레 띠에 걸려 연석으로 보이는 곳(정비소 오른쪽 벽)처럼 자동으로 못 고르는 덩어리용."""
    p = SRC / f"{name}.hull.txt"
    if not p.exists():
        return margin
    out = dict(margin)
    for line in p.read_text().splitlines():
        v = line.split("#")[0].split()
        if len(v) < 3:
            continue
        i, want = int(v[0]), [int(x) for x in v[1:4]] + [0] * (4 - len(v))
        have = (list(out.get(i, ())) + [0, 0, 0])[:3]
        m = [max(a, b) for a, b in zip(have, want)]
        out[i] = tuple(m) if m[2] else tuple(m[:2])
    print(f"  {p.name}: 덩어리 몫을 손으로 정한다 → {dict(sorted(out.items()))}")
    return out


def piece_margins(name: str, guide: dict, keep: np.ndarray, origin, scale: float, day=None):
    """잘리는 그림마다 가장 적게 넓혀 덮는 덩어리를 골라, 덩어리마다 넓힐 몫 {번호: (위, 좌우, 아래)} (화면 px).
    아래로 넓히기는 모형보다 낮게 그려진 높은 덩어리(크레인 보)용이라 비싸게 친다. 덩어리별 윤곽(.json)이 없으면 None."""
    pieces = hull_pieces(name, guide, keep.shape, origin, scale)
    if pieces is None:
        return None
    h, w = keep.shape
    hull = np.zeros(keep.shape, bool)
    for i, y0, x0, m in pieces:
        hull[y0:y0 + m.shape[0], x0:x0 + m.shape[1]] |= m
    lost0 = keep & ~hull & ~lot_ground(guide, keep.shape, origin, scale, 28.0)
    band, below = curb_band(guide, hull, origin, scale, day)
    cand = lost0 & (~band | below)
    ly, lx = np.nonzero(cand)
    in_band = band[ly, lx]   # 띠 안은 아래로 넓혀 덮지 않는다 (바닥 덩어리가 앞 바닥을 덮게 된다)
    if len(ly) < 30:
        return {}
    sides = np.arange(0, PIECE_GROW + 1, 2)
    drops = np.arange(0, PIECE_DROP + 1, 4)
    U, S, Dn = round(PIECE_LIFT * scale), round(PIECE_GROW * scale), round(PIECE_DROP * scale)
    best = np.full(len(ly), np.inf)
    who = np.full(len(ly), -1)
    need = {}
    for i, y0, x0, m in pieces:
        wy0, wx0 = max(0, y0 - U), max(0, x0 - S)
        wy1, wx1 = min(h, y0 + m.shape[0] + Dn), min(w, x0 + m.shape[1] + S)
        sel = np.nonzero((ly >= wy0) & (ly < wy1) & (lx >= wx0) & (lx < wx1))[0]
        if len(sel) == 0:
            continue
        M = np.zeros((wy1 - wy0, wx1 - wx0), bool)
        M[y0 - wy0:y0 - wy0 + m.shape[0], x0 - wx0:x0 - wx0 + m.shape[1]] = m
        # 같은 열에서 아래(→ 위로 넓혀 덮는다)·위(→ 아래로 넓혀 덮는다)로 가장 가까운 윤곽까지 거리
        Db, Da = np.empty(M.shape), np.empty(M.shape)
        run = np.full(M.shape[1], np.inf)
        for r in range(M.shape[0] - 1, -1, -1):
            run = np.where(M[r], 0.0, run + 1.0)
            Db[r] = run
        run = np.full(M.shape[1], np.inf)
        for r in range(M.shape[0]):
            run = np.where(M[r], 0.0, run + 1.0)
            Da[r] = run
        ry, rx = ly[sel] - wy0, lx[sel] - wx0
        nu, nd = [], []
        for D, rows in ((Db, nu), (Da, nd)):
            Ds, prev = D.copy(), 0
            for sd in sides:
                si = round(sd * scale)
                for d in range(prev + 1, si + 1):
                    Ds[:, :-d] = np.minimum(Ds[:, :-d], D[:, d:])
                    Ds[:, d:] = np.minimum(Ds[:, d:], D[:, :-d])
                prev = max(prev, si)
                rows.append(Ds[ry, rx] / scale)
        nu, nd = np.array(nu), np.array(nd)
        nu[nu > PIECE_LIFT] = np.inf
        nd[nd > PIECE_DROP] = np.inf
        nd[:, in_band[sel]] = np.inf
        cost = (np.minimum(nu, 2.0 * nd) + 2.0 * sides[:, None]).min(0)
        better = cost < best[sel]
        best[sel[better]] = cost[better]
        who[sel[better]] = i
        need[i] = (sel, nu, nd)
    out = {}
    for i, (sel, nu, nd) in need.items():
        mine = who[sel] == i
        if mine.sum() < 6:
            continue
        su, sdn = nu[:, mine], nd[:, mine]
        pick = None
        for k, sd in enumerate(sides):
            for dr in drops:
                rest = su[k][sdn[k] > dr]          # 아래로 dr만큼 넓혀도 못 덮는 것은 위로
                n_ok = mine.sum() - len(rest)
                if len(rest) == 0:
                    u = 0
                else:
                    col = np.sort(rest)
                    allow = int(mine.sum() * 0.03)   # 3%는 남겨도 된다
                    if allow >= len(col):
                        u = 0
                    else:
                        u = col[len(col) - 1 - allow]
                        if not np.isfinite(u):
                            continue
                u = int(np.ceil(u / 2.0) * 2)
                c = u + 2 * sd + 2 * dr
                if pick is None or c < pick[0]:
                    pick = (c, (u, int(sd), int(dr)))
        if pick and pick[1] != (0, 0, 0):
            out[i] = pick[1] if pick[1][2] else pick[1][:2]
    covered = int(cand.sum()) - int((who >= 0).sum())
    if out:
        ups = max(m[0] for m in out.values())
        sds = max(m[1] for m in out.values())
        dns = max((m[2] if len(m) > 2 else 0) for m in out.values())
        print(f"  잘리는 그림 {int(lost0.sum())}px (연석 빼고 {len(ly)}px) → 덩어리 {len(out)}곳만 넓힌다 "
              f"(가장 큰 몫 위 {ups}·좌우 {sds}·아래 {dns}px)" + (f" · 덩어리로 못 덮는 {covered}px" if covered > 150 else ""))
    return out

def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    debug = "--debug" in sys.argv
    names = args or sorted(p.stem for p in SRC.glob("*.png")
                           if not p.stem.endswith(("_lights", "_fit_debug")))
    for name in names:
        prepare(name, debug)


if __name__ == "__main__":
    main()
