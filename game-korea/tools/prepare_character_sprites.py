#!/usr/bin/env python3
"""인물 4×2 스프라이트 시트(제미나이 원본)를 게임용으로 다듬는다.

원본: output/imagegen/characters/NN_<id>.png (1376×768, 단색 배경, 4열×2행 — 요청 규칙은 같은 폴더 GEMINI_PROMPT_v2.md)
  열: 0 서 있기 · 1 걷기(왼발) · 2 걷기(오른발) · 3 달리기 / 행: 0 앞모습(화면 오른쪽 아래를 봄) · 1 뒷모습(오른쪽 위)
달리기 두 장(반대 다리)은 NN_<id>_run.png (2열×2행)로 따로 받으면 5·6열에 붙는다.
걷기 두 장은 NN_<id>_walk.png (2열×2행)로 따로 받으면 2·3열을 바꾼다.
결과: assets/characters/<id>.png — 칸 CELL_W×CELL_H, 8열×2행:
  0 서 있기 · 1 걷기 A · 2 걷기 B · 3 달리기 · 4 걷기 모음 · 5 달리기 A · 6 달리기 B · 7 달리기 모음
  (모음 칸은 걷기 A·달리기 A의 팔·다리를 가운데로 모아 만든다. 달리기 두 장이 없으면 5·6열은 3열과 같다)
  한 바퀴 시트(NN_<id>_walk_front/back, _run_front/back — 4열×2행 8장 또는 4열×4행 16장)가 있으면 8~23열 걷기, 24~39열 달리기 (16장씩). 칸마다 발끝이 FOOT_Y, 몸통 가운데가 칸 가운데.
  - 배경: 테두리에서 시작한 플러드필로만 지운다 (옷 안쪽 어두운 색이 뚫리지 않게). 발밑 그림자도 같이 지운다.
  - 크기: 한 시트 안에서 같은 배율 (서 있기 앞모습 키가 BODY_H). 프레임마다 키가 달라도 키우지 않는다.
  - 작은 부스러기(다른 칸에서 넘어온 조각·점)는 버린다.
실행: python3 tools/prepare_character_sprites.py [--debug] [--check-legs] [id ...]
  --check-legs: 한 바퀴 시트의 오른쪽 다리 발목 초록(#00FF00) 띠가 1번 칸에서 앞, 5번 칸에서 뒤인지 검사 (아니면 끝 코드 1).
  초록 띠는 다듬을 때 신발 색으로 칠해 지운다.
  --attacks-only: 영상 동작 시트(00_<id>_attacks_dir8.png 주먹·_rifle_dir8.png 소총·…·_jump_dir8.png 점프 — tools/punch_video_sheet.py)만
  assets/characters/<id>_attacks_dir8.png·_rifle_dir8.png로 다시 내고 .json의 그 항목만 바꾼다 (걷기 시트는 그대로 — 손으로 다듬은 줄이 있다).
"""
import re
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "output/imagegen/characters"
DST = ROOT / "assets/characters"
COLS, ROWS = 4, 2
CELL_W, CELL_H = 96, 112
FOOT_Y = 108
BODY_H = 96
HIP_Y = FOOT_Y - 46          ## 엉덩이 높이 (칸 안 y)
SHOULDER_Y = FOOT_Y - 78     ## 어깨 높이 — 팔 모으기는 이 아래부터
TORSO_HALF = 11              ## 몸통 반폭 (px) — 이 안은 팔을 모아도 그대로
PASS_SQUEEZE = 0.42          ## 발끝에서 다리 벌어짐을 이만큼으로
ARM_SQUEEZE = 0.4            ## 손 높이에서 몸통 밖으로 흔든 팔을 이만큼으로
OUT_COLS = 8                 ## 서 있기·걷기 A·걷기 B·달리기·걷기 모음·달리기 A·달리기 B·달리기 모음
MARKER_FILL = (34, 33, 36)   ## 다리 표시(초록)를 지울 때 칠하는 색 (검은 신발·바지 끝)
FAR_LEG = 0.62               ## 먼 다리 밝기 (초록 띠가 있는 한 바퀴 시트만)
LEG_TOL = 0.04               ## 표시가 몸통 가운데에서 키의 이만큼 넘게 벗어나야 앞·뒤로 친다
LEG_MARKS: dict = {}
CYCLE = 16                   ## 게임 시트의 한 바퀴 장 수 (있으면 9열부터 걷기 16장, 그다음 달리기 16장). 8장 원본은 두 번씩
CELL_ASPECT = 0.75           ## 한 바퀴 원본 칸의 가로:세로
EXTRA = ("_run", "_walk", "_walk_front", "_walk_back", "_run_front", "_run_back", "_walk_dir4", "_run_dir4", "_walk12_dir4")
DIR4_FRAMES = 8              ## 정방향 4방향 시트의 한 줄 장 수
DIR4_OUT = 24                ## 정방향 4방향 게임 시트의 동작 한 바퀴 장 수 (12장 원본은 두 번씩, 8장 원본은 세 번씩 — 고르게 늘어난다)
DIR4_CELL_W = 128            ## 정방향 4방향 게임 시트 칸 가로 (옆으로 달리는 큰 보폭이 잘리지 않게, 발끝 x = 64)


def border_color(rgb: np.ndarray) -> np.ndarray:
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    return np.median(border, axis=0)


def is_key_color(bg: np.ndarray) -> bool:
    """채도가 높은 단색 배경(마젠타·초록)인가"""
    return bg.max() - bg.min() > 120


def edge_unmix(rgb: np.ndarray, bgm: np.ndarray, bg: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """배경과 맞닿은 3px 테두리: 배경색이 섞인 만큼 반투명으로 하고 색에서 배경을 뺀다 (분홍 테두리 제거)"""
    near = bgm.copy()
    for _ in range(3):
        grown = near.copy()
        grown[1:] |= near[:-1]
        grown[:-1] |= near[1:]
        grown[:, 1:] |= near[:, :-1]
        grown[:, :-1] |= near[:, 1:]
        near = grown
    ring = near & ~bgm
    alpha = np.where(bgm, 0.0, 1.0)
    out = rgb.astype(np.float64)
    dist = np.sqrt(((rgb - bg) ** 2).sum(axis=2))
    a = np.clip(dist / 260.0, 0.0, 1.0)
    alpha[ring] = a[ring]
    safe = np.maximum(a, 0.05)[..., None]
    unmixed = np.clip((out - (1.0 - safe) * bg) / safe, 0, 255)
    out[ring] = unmixed[ring]
    return out.astype(np.uint8), (alpha * 255).astype(np.uint8)


def despill(rgb: np.ndarray) -> np.ndarray:
    """배경 마젠타가 번진 보라 기운(빨강·파랑이 같이 높고 초록만 낮다)을 초록 쪽으로 눌러 무채색에 가깝게"""
    c = rgb.astype(np.int32)
    r, g, b = c[:, :, 0], c[:, :, 1], c[:, :, 2]
    lo = np.minimum(r, b)
    spill = (lo - g > 40) & (np.abs(r - b) < 70)
    keep = g + (lo - g) * 0.25
    for ch in (0, 2):
        c[:, :, ch] = np.where(spill, np.minimum(c[:, :, ch], keep + (c[:, :, ch] - lo)), c[:, :, ch])
    return np.clip(c, 0, 255).astype(np.uint8)


def background_mask(rgb: np.ndarray) -> np.ndarray:
    """테두리와 이어진 배경·그림자 칸을 True로"""
    h, w, _ = rgb.shape
    bg = border_color(rgb)
    dist = np.sqrt(((rgb - bg) ** 2).sum(axis=2))
    lum = rgb.mean(axis=2)
    bg_lum = bg.mean()
    # 배경: 배경색에 아주 가깝다. 그림자: 배경보다 조금 어둡고 색조(푸른 기)가 같다
    if is_key_color(bg):
        # 마젠타 같은 원색 배경: 캐릭터 색과 멀어서 넉넉히 지운다 (가장자리 섞인 색은 edge_unmix가 푼다)
        passable = dist < 90
    else:
        # v1의 어두운 배경: 배경색에 아주 가까운 것 + 발밑 그림자(배경보다 조금 어둡고 색조가 같다)
        hue_ok = (rgb[:, :, 2] - rgb[:, :, 0]) >= (bg[2] - bg[0]) * 0.5
        passable = (dist < 13) | ((dist < 24) & (lum < bg_lum) & (lum > bg_lum - 12) & hue_ok)
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if passable[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if passable[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and passable[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def components(mask: np.ndarray):
    """True 칸의 연결 덩어리들 (크기, 좌표 목록)"""
    h, w = mask.shape
    label = np.zeros((h, w), np.int32)
    out = []
    n = 0
    for sy, sx in zip(*np.nonzero(mask)):
        if label[sy, sx]:
            continue
        n += 1
        label[sy, sx] = n
        q = deque([(sy, sx)])
        pts = []
        while q:
            y, x = q.popleft()
            pts.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not label[ny, nx]:
                        label[ny, nx] = n
                        q.append((ny, nx))
        out.append(pts)
    out.sort(key=len, reverse=True)
    return out


def cut_cell(rgba: np.ndarray, drop_edge: bool = False):
    """칸 하나: 큰 덩어리만 남기고 (그림, 발끝 y, 몸통 가운데 x, 키).
    drop_edge면 칸 테두리에 닿은 떨어진 조각(옆 칸 인물이 넘어온 것)을 버린다 — 정방향 4방향 시트(주인공)만 쓴다"""
    alpha = rgba[:, :, 3] > 0
    comps = components(alpha)
    keep = np.zeros_like(alpha)
    if not comps:
        return None
    biggest = len(comps[0])
    h, w = alpha.shape
    for k, pts in enumerate(comps):
        if len(pts) < biggest * 0.02:
            break
        ys, xs = zip(*pts)
        # 떨어진 조각이 칸 테두리에 닿아 있으면 옆 칸 인물이 넘어온 것이다 (발끝 기준이 틀어진다) — 버린다
        if drop_edge and k > 0 and (min(ys) == 0 or max(ys) == h - 1 or min(xs) == 0 or max(xs) == w - 1):
            continue
        keep[list(ys), list(xs)] = True
    rgba = rgba.copy()
    rgba[~keep, 3] = 0
    ys, xs = np.nonzero(keep)
    top, bottom = ys.min(), ys.max()
    # 몸통 가운데: 위쪽 55%(머리·어깨·몸통)의 무게중심 — 다리를 벌려도 흔들리지 않게
    upper = ys < top + (bottom - top) * 0.55
    cx = xs[upper].mean()
    return rgba, bottom, cx, bottom - top + 1


def marker_mask(rgb: np.ndarray) -> np.ndarray:
    """다리 구분 표시(밝은 초록 #00FF00 띠)와 그 번진 가장자리"""
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    core = (g > 150) & (r < 120) & (b < 120)
    halo = (g - np.maximum(r, b) > 50)
    return core | halo


def shade_far_leg(cell: np.ndarray, mark: np.ndarray) -> None:
    """먼 쪽 다리를 어둡게 칠한다 (칸 하나, 제자리에서). 두 다리가 같은 색·같은 모양이라 어느 다리가 나갔는지 안 보이기 때문이다.
    초록 띠(인물 오른쪽 발목)는 앞·뒷모습 모두 화면 쪽(가까운) 다리다. 엉덩이 가운데에서 두 발목으로 선을 긋고,
    다리 줄의 점마다 더 가까운 선의 다리로 나눠 먼 다리 쪽만 FAR_LEG배로 어둡게."""
    alpha = cell[:, :, 3] > 40
    ys, xs = np.nonzero(alpha)
    my, mx = np.nonzero(mark)
    if ys.size == 0 or mx.size < 20:
        return
    top, bottom = ys.min(), ys.max()
    height = bottom - top + 1
    hip_y = int(bottom - height * 0.47)
    near = (mx.mean(), my.mean())
    # 먼 발목: 발 높이(아래 14%) 점 가운데 초록 띠에서 떨어진 것들
    foot = (ys > bottom - height * 0.14) & (np.abs(xs - near[0]) > height * 0.07)
    if foot.sum() < 20:
        return                      # 두 발이 겹친 칸 — 먼 다리는 가려져 있다
    far = (xs[foot].mean(), ys[foot].mean())
    row = np.nonzero(alpha[hip_y])[0]
    if row.size == 0:
        return
    hx = float(np.median(row))
    for y in range(hip_y, bottom + 1):
        xs_row = np.nonzero(alpha[y])[0]
        if xs_row.size == 0:
            continue
        tn = min(1.0, (y - hip_y) / max(near[1] - hip_y, 1.0))
        tf = min(1.0, (y - hip_y) / max(far[1] - hip_y, 1.0))
        xn = hx + (near[0] - hx) * tn
        xf = hx + (far[0] - hx) * tf
        # 엉덩이 바로 아래는 두 다리가 붙어 있어 나누지 않는다
        if abs(xn - xf) < height * 0.025:
            continue
        sel = xs_row[(np.abs(xs_row - xf) < np.abs(xs_row - xn)) & (np.abs(xs_row - xf) < height * 0.11)]
        # 엉덩이 쪽은 서서히 어두워지게 (경계선이 보이지 않게)
        k = 1.0 - (1.0 - FAR_LEG) * min(1.0, (y - hip_y) / (height * 0.12))
        cell[y, sel, :3] = (cell[y, sel, :3].astype(np.float64) * k).astype(np.uint8)


def unmix_key(rgb: np.ndarray, alpha: np.ndarray, bg: np.ndarray, bgm: "np.ndarray | None" = None) -> tuple[np.ndarray, np.ndarray]:
    """그림 전체에서 배경색이 섞인 만큼(배경의 밝은 채널이 나머지 채널보다 높은 만큼) 반투명으로 풀고 색에서 배경을 뺀다.
    마젠타 배경이면 빨강·파랑이 초록보다 높은 만큼, 초록 배경이면 초록이 빨강·파랑 평균보다 높은 만큼이다.
    팔·다리 사이 틈을 어두운 배경색으로 칠한 압축 그림용 — 검은 옷에 번진 배경 기운도 무채색으로 돌아온다.
    bgm(배경 자리)을 주면 옷이 배경과 같은 계열(초록 배경에 국방색 재킷)인 인물로 보고, 배경에서 3px 안과
    거의 배경색 그대로인 곳(배경 채널 말고는 거의 0인 짙은 틈)만 푼다 — 옷의 옅은 초록 기운은 그대로 둔다"""
    c = rgb.astype(np.float64)
    hi = [k for k in range(3) if bg[k] > 128]
    lo = [k for k in range(3) if bg[k] <= 128]
    top = c[:, :, hi].min(axis=2)
    # 나머지 채널은 평균으로 — 초록 배경에서 최댓값(대개 빨강)을 쓰면 살색 가장자리에 초록이 덜 빠져 노랗게 남는다
    bot = c[:, :, lo].mean(axis=2)
    span = max(float(min(bg[k] for k in hi) - np.mean([bg[k] for k in lo])), 1.0)
    e = np.clip((top - bot) / span, 0.0, 1.0)
    if len(hi) == 2:
        # 두 채널이 밝은 배경(마젠타)은 두 채널이 비슷할 때만 — 빨강 옷·파랑 옷은 섞인 것으로 보지 않는다
        e = np.where(np.abs(c[:, :, hi[0]] - c[:, :, hi[1]]) < 70, e, 0.0)
    if bgm is not None:
        near = bgm.copy()
        for _ in range(3):
            grown = near.copy()
            grown[1:] |= near[:-1]
            grown[:-1] |= near[1:]
            grown[:, 1:] |= near[:, :-1]
            grown[:, :-1] |= near[:, 1:]
            near = grown
        pure = (top - bot) > 0.6 * np.maximum(top, 1.0)
        e = np.where(near | pure, e, 0.0)
    keep = np.maximum(1.0 - e, 0.05)[..., None]
    c = np.clip((c - e[..., None] * bg) / keep, 0, 255)
    a = alpha * (1.0 - e)
    a = np.where(a < 30, 0, a)
    return c.astype(np.uint8), a.astype(np.uint8)


def _key_background(rgb: np.ndarray, unmix: bool = False, keep_tint: bool = False) -> np.ndarray:
    """단색 배경을 지운 RGBA. unmix면 테두리만이 아니라 그림 전체에서 배경색 섞임을 푼다(unmix_key)"""
    bgm = background_mask(rgb)
    bg = border_color(rgb)
    if is_key_color(bg):
        # 원색 배경은 캐릭터에 없는 색이라, 팔과 몸 사이처럼 테두리와 안 이어진 구멍도 지운다
        bgm |= np.sqrt(((rgb - bg) ** 2).sum(axis=2)) < 90
        if unmix:
            color, alpha = unmix_key(rgb, np.where(bgm, 0.0, 255.0), bg, bgm if keep_tint else None)
        else:
            color, alpha = edge_unmix(rgb, bgm, bg)
            color = despill(color)
        return np.dstack([color, alpha]).astype(np.uint8)
    return np.dstack([rgb, np.where(bgm, 0, 255)]).astype(np.uint8)


def load_cells(src: Path, cols: int, rows: int, markers: "dict | None" = None, drop_edge: bool = False,
               pad: float = 0.0, shade: bool = True, unmix: bool = False, keep_tint: bool = False,
               hpad: float = 0.0) -> dict:
    """시트 한 장: 배경을 지우고 칸마다 (그림, 발끝 y, 몸통 가운데 x, 키).
    markers에 사전을 넘기면 초록 다리 표시를 찾아 칸마다 (표시 가운데 x − 몸통 가운데 x) / 키를 적고, 표시는 신발 색으로 칠해 지운다"""
    img = Image.open(src)
    rgb = np.array(img.convert("RGB")).astype(np.int32)
    h, w, _ = rgb.shape
    # 처음부터 투명한 그림(배경 없는 PNG)이면 그 투명도를 그대로 쓴다 — 검은 옷이 검은 배경에 먹히지 않게
    own_alpha = None
    if img.mode in ("RGBA", "LA") or "transparency" in img.info:
        a = np.array(img.convert("RGBA"))[:, :, 3]
        if (a < 10).mean() > 0.05:
            own_alpha = a
    mark = None
    if markers is not None:
        mark = marker_mask(rgb)
        rgb = rgb.copy()
        rgb[mark] = MARKER_FILL
    if own_alpha is not None:
        rgba = np.dstack([rgb, own_alpha]).astype(np.uint8)
        rgba[own_alpha < 10] = 0
    else:
        rgba = _key_background(rgb, unmix, keep_tint)
    ch = h // rows
    cells = {}
    for r in range(rows):
        for c in range(cols):
            # 칸 경계는 비율로 (가로가 열 수로 나눠떨어지지 않는 그림에서 오른쪽 칸이 밀리지 않게)
            y0, y1 = r * h // rows, (r + 1) * h // rows
            x0, x1 = c * w // cols, (c + 1) * w // cols
            if mark is not None and shade:
                shade_far_leg(rgba[y0:y1, x0:x1], mark[y0:y1, x0:x1])
            # pad: 위·아래로 칸 높이의 이만큼 더 읽는다 (머리가 윗칸으로 넘어간 그림). 넘어온 이웃 조각은 drop_edge가 버린다
            # hpad: 좌우로도 칸 너비의 이만큼 더 읽는다 (보폭이 넓어 발끝이 옆 칸 경계를 넘은 그림)
            p = int(ch * pad)
            q = int((x1 - x0) * hpad)
            cell = cut_cell(rgba[max(0, y0 - p):min(h, y1 + p), max(0, x0 - q):min(w, x1 + q)], drop_edge)
            cells[(r, c)] = cell
            if mark is not None:
                m = mark[max(0, y0 - p):min(h, y1 + p), max(0, x0 - q):min(w, x1 + q)]
                ys, xs = np.nonzero(m)
                found = cell is not None and xs.size >= 20
                markers[(r, c)] = (xs.mean() - cell[2]) / cell[3] if found else None
                # (가로, 발끝에서 올라온 높이) — 키에 대한 비율. 8방향 열쇠 장면 검사용
                markers[("xy", r, c)] = ((xs.mean() - cell[2]) / cell[3], (cell[1] - ys.mean()) / cell[3]) if found else None
                # 띠 덩어리 수 (두 발목에 다 두르면 2 — 다리 구분이 안 된다)
                blobs = [b for b in components(m) if len(b) >= 15] if found else []
                markers[("n", r, c)] = len(blobs)
    return cells


def place(out: Image.Image, cell, r: int, c: int, scale: float, cw: int = CELL_W) -> None:
    """칸 (r, c)에 발끝·몸통 가운데를 맞춰 붙인다 (칸 가로 cw)"""
    if cell is None:
        return
    img, foot, cx, _ = cell
    im = Image.fromarray(img).convert("RGBa")
    im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS).convert("RGBA")
    ox = round(c * cw + cw / 2 - cx * scale)
    oy = round(r * CELL_H + FOOT_Y - foot * scale)
    tile = Image.new("RGBA", out.size, (0, 0, 0, 0))
    tile.paste(im, (ox, oy))
    # 옆 칸으로 넘친 부분은 자른다
    box = (c * cw, r * CELL_H, (c + 1) * cw, (r + 1) * CELL_H)
    out.paste(tile.crop(box), box[:2])


def _smooth(a: float, b: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def gather_limbs(cell: Image.Image) -> Image.Image:
    """두 발 모음 칸: 팔·다리를 몸 가운데로 모은다 (걷기 A 그림 한 장에서 만든다).
    줄마다 가운데에서 TORSO_HALF 안(몸통·다리 안쪽)은 k_in배, 그 바깥(흔든 팔·벌린 다리)은 k_out배로 좁힌다.
      어깨 위: 그대로 · 어깨~엉덩이: 몸통은 그대로, 팔만 손 쪽으로 갈수록 ARM_SQUEEZE까지
      엉덩이 아래: 다리를 발끝으로 갈수록 PASS_SQUEEZE까지 (손 높이까지는 팔도 계속 모은다)"""
    a = np.array(cell.convert("RGBa")).astype(np.float64)
    h, w, _ = a.shape
    ys, xs = np.nonzero(a[SHOULDER_Y:HIP_Y, :, 3] > 32)
    if xs.size == 0:
        return cell
    cx = np.median(xs)
    out = a.copy()
    grid = np.arange(w, dtype=np.float64)
    T = TORSO_HALF
    for y in range(SHOULDER_Y, h):
        if y < HIP_Y:
            k_in = 1.0
            k_out = 1.0 - (1.0 - ARM_SQUEEZE) * _smooth(SHOULDER_Y, HIP_Y, y)
        else:
            k_in = 1.0 - (1.0 - PASS_SQUEEZE) * min(1.0, (y - HIP_Y) / max(FOOT_Y - HIP_Y, 1))
            # 손 높이까지는 팔을 모으고, 그 아래는 다리와 같이
            k_out = ARM_SQUEEZE + (k_in - ARM_SQUEEZE) * _smooth(HIP_Y + 8, HIP_Y + 22, y)
        d = np.abs(grid - cx)
        sgn = np.sign(grid - cx)
        inner = T * k_in
        # 받는 자리 d → 가져올 자리 (안쪽은 /k_in, 바깥은 T + (d - inner)/k_out)
        src_d = np.where(d <= inner, d / k_in, T + (d - inner) / k_out)
        src_x = cx + sgn * src_d
        for ch in range(4):
            out[y, :, ch] = np.interp(src_x, grid, a[y, :, ch], left=0.0, right=0.0)
    arr = np.clip(out, 0, 255).astype(np.uint8)
    return Image.frombytes("RGBa", (arr.shape[1], arr.shape[0]), arr.tobytes()).convert("RGBA")


def cycle_grid(src: Path) -> tuple[int, int]:
    """한 바퀴 시트의 칸 수: 4열 고정, 칸 가로:세로가 약 3:4라 행 수는 캔버스 비율로 정한다
    (1536×1024 → 4×2 = 8장, 896×1200 → 4×4 = 16장)"""
    w, h = Image.open(src).size
    rows = max(1, round(h / ((w / 4) / CELL_ASPECT)))
    return 4, rows


def load_cycle(src: Path) -> list:
    """한 바퀴 시트 → CYCLE장 (왼쪽 위부터 읽는 순서). 8장 시트는 한 장씩 두 번 써서 CYCLE장으로 맞춘다.
    <시트 이름>.skip.txt가 있으면 거기 적힌 칸(1부터)을 빼고 남은 장으로 채운다.
    초록 다리 표시가 있으면 지우고 check_legs용으로 위치를 남긴다"""
    cols, rows = cycle_grid(src)
    n = cols * rows
    marks: dict = {}
    cells = load_cells(src, cols, rows, marks)
    LEG_MARKS[src.name] = [marks.get((i // cols, i % cols)) for i in range(n)]
    frames = [cells[(i // cols, i % cols)] for i in range(n)]
    # 튀는 장 빼기: 같은 이름의 .skip.txt에 1부터 센 칸 번호 (예: "2 3 9"). 남은 장을 고르게 늘려 CYCLE장으로
    skip_file = src.with_name(src.stem + ".skip.txt")
    if skip_file.exists():
        skip = {int(t) - 1 for t in skip_file.read_text().replace(",", " ").split() if t.isdigit()}
        kept = [f for i, f in enumerate(frames) if i not in skip]
        if kept:
            print(f"  {src.name}: {sorted(i + 1 for i in skip)}번 칸 뺌 → {len(kept)}장")
            frames = kept
    m = len(frames)
    return [frames[i * m // CYCLE] for i in range(CYCLE)]


def check_legs() -> bool:
    """초록 표시 다리가 1번에서 앞, 5번에서 뒤인가 (모든 한 바퀴 시트). 화면 오른쪽(+x)이 앞이다"""
    ok = True
    for name, marks in LEG_MARKS.items():
        def word(v):
            if v is None:
                return "없음"
            return "앞" if v > LEG_TOL else ("뒤" if v < -LEG_TOL else "가운데")
        line = " ".join(f"{i + 1}:{word(v)}" for i, v in enumerate(marks))
        half = len(marks) // 2
        good = word(marks[0]) == "앞" and word(marks[half]) == "뒤" and all(v is not None for v in marks)
        ok &= good
        print(f"  {name} 초록 다리 — {line} → {'반대 다리 OK' if good else f'실패 (1번 앞·{half + 1}번 뒤여야 한다, 모든 칸에 표시가 있어야 한다)'}")
    return ok


def process(src: Path, cid: str, debug: bool) -> None:
    cells = load_cells(src, COLS, ROWS)
    scale = BODY_H / cells[(0, 0)][3]
    # 달리기 두 장(반대 다리) 시트가 따로 있으면 5·6열로 붙인다: NN_<id>_run.png (2열 달리기 A·B × 2행 앞·뒤)
    run_src = src.with_name(src.stem + "_run.png")
    run_cells = load_cells(run_src, 2, ROWS) if run_src.exists() else None
    # 걷기·달리기 8장 한 바퀴 시트: NN_<id>_walk_front.png · _walk_back.png · _run_front.png · _run_back.png
    # (4열×2행 8장 또는 4열×4행 16장, 왼쪽 위부터). 앞·뒤 둘 다 있으면 9열부터 걷기 16장, 그다음 달리기 16장
    cycles = []
    for motion in ("walk", "run"):
        front = src.with_name(f"{src.stem}_{motion}_front.png")
        back = src.with_name(f"{src.stem}_{motion}_back.png")
        if front.exists() and back.exists():
            cycles.append((motion, [load_cycle(front), load_cycle(back)]))
        elif motion == "walk":
            break           # 달리기만 있으면 열 번호가 어긋난다 — 걷기가 있어야 달리기도 붙인다
    out = Image.new("RGBA", (CELL_W * (OUT_COLS + CYCLE * len(cycles)), CELL_H * ROWS), (0, 0, 0, 0))
    # 걷기 두 장 시트가 따로 있으면 2·3열을 그것으로 바꾼다: NN_<id>_walk.png (2열 걷기 A·B × 2행 앞·뒤)
    walk_src = src.with_name(src.stem + "_walk.png")
    walk_scale = scale
    if walk_src.exists():
        walk_cells = load_cells(walk_src, 2, ROWS)
        ref = cells[(0, 1)] or cells[(0, 0)]
        if walk_cells[(0, 0)]:
            walk_scale = ref[3] * scale / max(walk_cells[(0, 0)][3], 1)
        for (r, c), cell in walk_cells.items():
            cells[(r, 1 + c)] = cell
    for (r, c), cell in cells.items():
        place(out, cell, r, c, walk_scale if walk_src.exists() and c in (1, 2) else scale)
    if run_cells:
        # 달리기 시트는 그린 크기가 다를 수 있다 — 본 시트 달리기 칸(3열)과 키를 맞춘다
        ref = cells[(0, 3)] or cells[(0, 0)]
        run_scale = ref[3] * scale / max(run_cells[(0, 0)][3], 1) if run_cells[(0, 0)] else scale
        for (r, c), cell in run_cells.items():
            place(out, cell, r, 5 + c, run_scale)
    else:
        # 달리기 두 장이 없으면 4열 달리기를 5·6열에 그대로
        for r in range(ROWS):
            box = (3 * CELL_W, r * CELL_H, 4 * CELL_W, (r + 1) * CELL_H)
            for c in (5, 6):
                out.paste(out.crop(box), (c * CELL_W, r * CELL_H))
    # 모음 칸: 걷기 A(2열)·달리기 A(6열)의 팔·다리를 몸 가운데로 모아 만든다 → 5열·8열.
    # 서 있기 칸을 쓰면 옷·방향이 걷기 그림과 달라(다른 그림에서 온 칸) 걸음마다 몸이 휙 돈다
    for r in range(ROWS):
        for src_c, dst_c in ((1, 4), (5, 7)):
            cell = out.crop((src_c * CELL_W, r * CELL_H, (src_c + 1) * CELL_W, (r + 1) * CELL_H))
            out.paste(gather_limbs(cell), (dst_c * CELL_W, r * CELL_H))
    for k, (motion, rows) in enumerate(cycles):
        # 키 맞추기: 한 바퀴 그림들의 키 가운데값을 본 시트 걷기 A(·달리기) 칸 키(앞모습)와 같게
        ref = cells[(0, 1 if motion == "walk" else 3)] or cells[(0, 0)]
        for r in range(ROWS):
            # 앞·뒤 그림은 따로 그려 크기가 다를 수 있다 — 장마다(행마다) 따로 맞춘다
            heights = [c[3] for c in rows[r] if c]
            cyc_scale = ref[3] * (walk_scale if motion == "walk" else scale) / max(float(np.median(heights)), 1.0)
            for i, cell in enumerate(rows[r]):
                place(out, cell, r, OUT_COLS + k * CYCLE + i, cyc_scale)
    DST.mkdir(parents=True, exist_ok=True)
    out.save(DST / f"{cid}.png")
    if debug:
        dbg = Image.new("RGBA", out.size, (110, 150, 110, 255))
        dbg.alpha_composite(out)
        dbg.resize((out.width * 2, out.height * 2), Image.NEAREST).save(DST.parent.parent / ".screenshots" / f"sprite_{cid}.png")
    print(f"{cid}: 배율 {scale:.3f}" + (" · 걷기 2장" if walk_src.exists() else "") + (" · 달리기 2장" if run_cells else "")
          + "".join(f" · {m} {CYCLE}장" for m, _ in cycles))


def process_dir4(src: Path, cid: str, debug: bool) -> None:
    """정방향 4방향 걷기 시트 NN_<id>_walk_dir4.png (8열 × 4행: 0 앞·화면 쪽으로 · 1 뒤·화면 안쪽으로 · 2 오른쪽 · 3 왼쪽)
    → assets/characters/<id>_dir4.png (3행: 앞·뒤·옆(오른쪽), 0열 서 있기 + 1~24열 걷기 한 바퀴 [+ 25~48열 달리기], 칸 128×112).
    줄마다 NN_<id>_walk_dir4_<s|n|e>.png(4×4 16장)가 있으면 그 줄 걷기를 그것으로 바꾼다.
    NN_<id>_walk12_dir4.png(12열 × 4행: 앞 · 왼쪽 · 오른쪽 · 뒤, 한 바퀴 12장)가 있으면 앞·뒤·옆 걷기를 모두 그것으로 바꾼다 (줄마다 바꾼 것보다 먼저).
    왼쪽 줄은 쓰지 않는다 — 생성 그림이 얼굴만 왼쪽이고 몸·발은 오른쪽으로 걷는 경우가 있어, 게임이 오른쪽 줄을 뒤집어 쓴다.
    서 있기 칸은 줄마다 다리가 가장 덜 벌어진 걷기 칸을 쓴다. 키는 줄마다 걷기 칸 키 가운데값을 BODY_H×0.97에 맞춘다."""
    motions = [load_cells(src, DIR4_FRAMES, 4, drop_edge=True)]
    run_src = src.with_name(src.stem.replace("_walk_dir4", "_run_dir4") + ".png")
    if run_src.exists():
        motions.append(load_cells(run_src, DIR4_FRAMES, 4, drop_edge=True))
    # 줄마다 16장 한 바퀴로 바꿔 끼우기: NN_<id>_walk_dir4_<s|n|e>.png (4열×4행 16장, 투명 PNG도 된다)
    override = {}
    for r, d in enumerate(("s", "n", "e")):
        o = src.with_name(f"{src.stem}_{d}.png")
        if o.exists():
            cells = load_cells(o, 4, 4, drop_edge=True, pad=0.06)
            override[r] = [cells[(i // 4, i % 4)] for i in range(16)]
            print(f"  {o.name}: 16장 → {('앞', '뒤', '옆')[r]} 줄 걷기")
    w12 = src.with_name(src.stem.replace("_walk_dir4", "_walk12_dir4") + ".png")
    if w12.exists():
        # 팔·다리 사이 틈이 어두운 마젠타로 칠해져 있다 — 그림 전체에서 배경색 섞임을 푼다
        cells = load_cells(w12, 12, 4, drop_edge=True, pad=0.06, unmix=True)
        for r, row in ((0, 0), (1, 3), (2, 2)):      # 앞 ← 1행, 뒤 ← 4행, 옆(오른쪽) ← 3행 (2행 왼쪽은 쓰지 않는다)
            override[r] = [cells[(row, c)] for c in range(12)]
        print(f"  {w12.name}: 12장 → 앞·뒤·옆 줄 걷기")
    n = DIR4_OUT
    cols = 1 + n * len(motions)
    out = Image.new("RGBA", (DIR4_CELL_W * cols, CELL_H * 3), (0, 0, 0, 0))
    for r in range(3):
        walk = override.get(r) or [motions[0][(r, c)] for c in range(DIR4_FRAMES)]
        walk = [c for c in walk if c]
        heights = [c[3] for c in walk]
        scale = BODY_H * 0.97 / max(float(np.median(heights)), 1.0)
        # 바꿔 끼운 걷기는 그린 크기가 달라 달리기는 달리기 그림 키로 따로 맞춘다
        run_scale = scale
        if r in override and len(motions) > 1:
            run_h = [c[3] for c in (motions[1][(r, k)] for k in range(DIR4_FRAMES)) if c]
            run_scale = BODY_H * 0.97 / max(float(np.median(run_h)), 1.0)
        place(out, min(walk, key=_spread), r, 0, scale, DIR4_CELL_W)
        for k in range(n):
            place(out, walk[k * len(walk) // n], r, 1 + k, scale, DIR4_CELL_W)
        if len(motions) > 1:
            run = [motions[1][(r, c)] for c in range(DIR4_FRAMES)]
            for k in range(n):
                place(out, run[k * len(run) // n], r, 1 + n + k, run_scale, DIR4_CELL_W)
    DST.mkdir(parents=True, exist_ok=True)
    out.save(DST / f"{cid}_dir4.png")
    if debug:
        dbg = Image.new("RGBA", out.size, (110, 150, 110, 255))
        dbg.alpha_composite(out)
        dbg.resize((out.width * 2, out.height * 2), Image.NEAREST).save(DST.parent.parent / ".screenshots" / f"sprite_{cid}_dir4.png")
    print(f"{cid}: 정방향 4방향 걷기 {DIR4_OUT}장" + (" · 달리기" if len(motions) > 1 else ""))


DIR8 = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]   ## 화면 각도 순서 (0°=오른쪽, 90°=아래)
DIR8_GRID = (4, 4)           ## 8방향 시트 칸 (4열×4행 = 16장). 생성 그림은 머리카락이 윗줄에 닿아 틈으로 세면 틀린다


DIR8_CHECKS: list = []
KEY8_TOL = 0.06              ## 1번 칸 띠 다리는 몸통 가운데보다 키의 6% 넘게 앞, 5번 칸은 6% 넘게 뒤
DIR8_SIGN = {"e": 1, "se": 1, "ne": 1, "w": -1, "sw": -1, "nw": -1}


def _spread(cell) -> float:
    """발 쪽(발끝에서 키의 25% 위까지) 가로 폭 = 보폭"""
    a = cell[0][:, :, 3] > 40
    foot, height = cell[1], cell[3]
    xs = np.nonzero(a[int(foot - height * 0.25):foot + 1])[1]
    return float(xs.max() - xs.min()) if xs.size else 0.0


def check_key8(name: str, d: str, walk: list, xy: list, blobs: list) -> bool:
    """8방향 열쇠 장면 시트 검사: 초록 띠(인물 오른쪽 발목) 다리가 1번 칸에서 앞, 5번 칸에서 뒤인가.
    앞의 기준: 옆·사선은 진행 방향 쪽 가로(→·↘·↗는 화면 오른쪽, ←·↙·↖는 왼쪽), ↓는 화면 아래(발이 낮다), ↑는 화면 위.
    옆·사선은 3·7번(지나감)의 보폭이 1·5번(딛기)보다 확실히 좁은지도 본다."""
    def metric(v):
        if v is None:
            return None
        dx, dy = v
        if d in DIR8_SIGN:
            return dx * DIR8_SIGN[d]
        return -dy if d == "s" else dy
    ms = [metric(v) for v in xy]
    if d in DIR8_SIGN:
        one_band = all(n == 1 for n in blobs)
        legs = all(m is not None for m in ms) and ms[0] > KEY8_TOL and ms[4] < -KEY8_TOL
    else:
        # 정면·뒷모습: 띠 높이는 앞발일 때도 발목이라 0이 기준이 아니다 — 1번과 5번의 차이로 본다. 띠가 다리에 가린 칸 하나는 봐 준다
        one_band = all(n <= 1 for n in blobs) and sum(n == 0 for n in blobs) <= 1
        legs = ms[0] is not None and ms[4] is not None and ms[0] - ms[4] > KEY8_TOL * 1.5
    ok = one_band and legs
    line = " ".join("없음" if m is None else f"{m:+.2f}" for m in ms)
    stride = ""
    if d in DIR8_SIGN and all(walk):
        sp = [_spread(c) for c in walk]
        narrow = max(sp[2], sp[6]) < 0.72 * min(sp[0], sp[4])
        ok &= narrow
        stride = f" | 보폭 {' '.join(f'{v:.0f}' for v in sp)} → {'지나감 OK' if narrow else '지나감 실패(3·7번이 1·5번보다 좁아야)'}"
    band = "" if one_band else f" | 띠 실패: 칸마다 띠가 하나여야 한다 (띠 덩어리 {' '.join(map(str, blobs))})"
    verdict = "반대 다리 OK" if legs else ("반대 다리 실패(1번은 +{0}보다 앞, 5번은 -{0}보다 뒤여야 한다)".format(KEY8_TOL)
                                       if d in DIR8_SIGN else "반대 다리 실패(1번이 5번보다 확실히 앞이어야 한다)")
    print(f"  {name} [{d}] 초록 다리 앞쪽 정도 {line} → {verdict}{band}{stride}")
    return ok


def process_dir8(cid: str, sources: dict, debug: bool) -> None:
    """8방향 걷기 시트 NN_<id>_walk8_<방향>.png (방향: e·se·s·sw·w·nw·n·ne, 4열×4행 16장)
    또는 열쇠 장면 시트 NN_<id>_key8_<방향>.png (4열×2행 8장, 초록 띠 검사 — 있으면 walk8보다 먼저 쓴다)
    → assets/characters/<id>_dir8.png (8행 = DIR8 순서, 0열 서 있기 + 1~16열 걷기 한 바퀴, 칸 128×112)
      + <id>_dir8.json (있는 방향 목록). 없는 방향은 게임이 가까운 방향이나 좌우 짝을 뒤집어 쓴다."""
    frames = 16
    out = Image.new("RGBA", (DIR4_CELL_W * (1 + frames), CELL_H * len(DIR8)), (0, 0, 0, 0))
    present = []
    for r, d in enumerate(DIR8):
        src = sources.get(d)
        if src is None:
            continue
        key = "_key8_" in src.stem
        cols, rows = (4, 2) if key else DIR8_GRID
        marks: dict = {}
        cells = load_cells(src, cols, rows, marks if key else None, drop_edge=True, pad=0.08 if key else 0.12,
                           shade=False)
        walk = [cells[(i // cols, i % cols)] for i in range(cols * rows)]
        if key:
            DIR8_CHECKS.append(check_key8(src.name, d, walk, [marks.get(("xy", i // cols, i % cols)) for i in range(8)],
                                          [marks.get(("n", i // cols, i % cols), 0) for i in range(8)]))
        walk = [c for c in walk if c]
        heights = [c[3] for c in walk]
        scale = BODY_H * 0.97 / max(float(np.median(heights)), 1.0)
        place(out, min(walk, key=_spread), r, 0, scale, DIR4_CELL_W)
        for k in range(frames):
            place(out, walk[k * len(walk) // frames], r, 1 + k, scale, DIR4_CELL_W)
        present.append(d)
        print(f"  {src.name}: {cols}×{rows} = {len(walk)}장 → {d}")
    DST.mkdir(parents=True, exist_ok=True)
    out.save(DST / f"{cid}_dir8.png")
    import json
    (DST / f"{cid}_dir8.json").write_text(json.dumps({"dirs": present, "frames": frames}))
    if debug:
        dbg = Image.new("RGBA", out.size, (110, 150, 110, 255))
        dbg.alpha_composite(out)
        dbg.save(DST.parent.parent / ".screenshots" / f"sprite_{cid}_dir8.png")
    print(f"{cid}: 8방향 걷기 {len(present)}방향 ({', '.join(present)})")


DIR8_SHEET_ROWS = ["s", "sw", "w", "nw", "n"]   ## 한 장짜리 8방향 시트의 줄 (나머지 ↘ → ↗는 게임이 좌우를 뒤집어 쓴다)
PUNCH_H = 0.95   ## 주먹 칸 키 / 걷기 키 — 무릎을 굽힌 싸움 자세
RUN_H_OF = {"office": 0.92}   ## 달리기 키 / 걷기 키를 머리 폭 대신 이 값으로 (걷기·달리기를 같은 키로 그린 시트 — 주인공 비율)
RUN_H_RANGE = (0.85, 0.92)   ## 달리기 키 / 걷기 키 — 머리 폭으로 맞춘 크기가 이 밖이면 끝으로 당긴다
RUN_ROW_K = (0.85, 1.25)     ## 달리기 줄마다 키를 시트 가운데값에 맞출 때 배율 한도 (튀는 줄만 당긴다)
NEON = {"firefighter"}   ## 형광 반사띠가 초록 기운이라 _despill로 걷지 않는다
KEEP_TINT = {"civ_f", "merchant", "firefighter", "foreigner", "traffic_cop", "soldier", "police_heli"}   ## 옷이 배경과 같은 계열인 인물 (초록 배경에 국방색 재킷·카키 바지·형광 반사띠·초록 티셔츠·형광 조끼·얼룩무늬·올리브 조끼) — 옷 안쪽의 배경 기운은 지우지 않는다


def _sheet_rows(src: Path, frames: int) -> list:
    """한 장짜리 시트의 줄 → [(줄 번호, 방향, 쓸 칸 번호들, 도는 장면)]. 기본은 DIR8_SHEET_ROWS 순서로 모든 칸.
    같은 이름의 .rows.txt가 있으면 한 줄에 하나씩 "방향 [칸]"(칸은 1부터, 예: "s 1-7", "n 1-12,14"), 안 쓰는 줄은 "-".
    뒤에 ">방향 칸"을 붙이면 그 칸들은 이 방향에서 그 방향으로 도는 장면이다 (예: "s 1-7 >se 8-12") — 도는 장면은 (방향, 칸들)"""
    rows_file = src.with_name(src.stem + ".rows.txt")
    if not rows_file.exists():
        return [(i, d, list(range(frames)), None) for i, d in enumerate(DIR8_SHEET_ROWS)]
    out = []
    lines = [ln.split("#")[0].split() for ln in rows_file.read_text().splitlines()]
    for i, words in enumerate(w for w in lines if w):
        if words[0] == "-" or words[0] not in DIR8:
            continue
        def cols(spec: str) -> list:
            got = []
            for part in spec.split(","):
                a, _, b = part.partition("-")
                got += range(int(a) - 1, int(b or a))
            return [k for k in got if 0 <= k < frames]
        turn = None
        if len(words) >= 4 and words[2].startswith(">") and words[2][1:] in DIR8:
            turn = (words[2][1:], cols(words[3]))
        keep = cols(words[1]) if len(words) > 1 and not words[1].startswith(">") else list(range(frames))
        out.append((i, words[0], keep, turn))
    return out


def _sheet_nrows(src: Path) -> int:
    """한 장짜리 시트의 줄 수 — .rows.txt가 있으면 그 줄 수(8방향을 다 그린 8행 시트 등), 없으면 5"""
    rows_file = src.with_name(src.stem + ".rows.txt")
    if not rows_file.exists():
        return len(DIR8_SHEET_ROWS)
    return sum(1 for ln in rows_file.read_text().splitlines() if ln.split("#")[0].split())


def _despill(cell, over: int = 30):
    """짙은 초록 기운을 걷는다 — G가 R·B 중 큰 쪽보다 over 넘게 크면 그 값까지 내린다.
    KEEP_TINT 인물은 옷 안쪽을 풀지 않아 다리 틈 같은 좁은 곳에 어두운 초록 줄이 남는다
    (civ_f 국방색 재킷은 이 차이가 99%가 9 아래라 안 걸린다)"""
    if cell is None:
        return None
    img = cell[0].copy()
    rgb = img[:, :, :3].astype(np.int32)
    top = np.maximum(rgb[:, :, 0], rgb[:, :, 2])
    hit = (img[:, :, 3] > 0) & (rgb[:, :, 1] - top > over)
    img[:, :, 1][hit] = top[hit]
    return (img,) + tuple(cell[1:])


def _head_w(cell) -> float:
    """머리 폭 (꼭대기에서 키의 6~10% 아래 가로 폭) — 따로 그린 시트끼리 크기를 맞출 때 쓴다 (달리기는 몸을 숙여 키로는 못 맞춘다)"""
    a = cell[0][:, :, 3] > 40
    top = int(np.nonzero(a)[0].min())
    band = a[top + int(cell[3] * 0.06):top + int(cell[3] * 0.10) + 1]
    ws = [np.ptp(np.nonzero(r)[0]) for r in band if r.any()]
    return float(np.median(ws)) if ws else 1.0


def _place_fall(out: Image.Image, meta: dict, cid: str, src: Path, n: int, col: int) -> None:
    """넘어짐 시트를 col열부터 붙인다. 누운 자세는 칸을 넘어 옆 칸까지 길게 그려져 있어 좌우로 넉넉히 읽고(옆 인물 조각은 버린다),
    가로는 그림 덩어리 가운데를 칸 가운데에 맞춘다 (누우면 몸통 무게중심이 한쪽으로 쏠린다 — 몸 가운데가 노드 자리).
    크기는 첫 칸(서 있기)의 키를 걷기 키에 맞춘다."""
    rows = _sheet_rows(src, n)
    cells = load_cells(src, n, _sheet_nrows(src), drop_edge=True, pad=0.06, unmix=True,
                       keep_tint=cid in KEEP_TINT, hpad=0.3)
    if cid in KEEP_TINT and cid not in NEON:
        cells = {k: _despill(c) for k, c in cells.items()}
    falls = {d: [c for c in (cells[(i, k)] for k in keep) if c] for i, d, keep, _ in rows}
    scale = BODY_H * 0.97 / max(float(np.median([cs[0][3] for cs in falls.values() if cs])), 1.0)
    for d, cs in falls.items():
        r = DIR8.index(d)
        for k in range(n):
            img, foot, _, h = cs[k * len(cs) // n]
            xs = np.nonzero((img[:, :, 3] > 40).any(0))[0]
            place(out, (img, foot, (xs.min() + xs.max()) / 2.0, h), r, col + k, scale, DIR4_CELL_W)
            w = (xs.max() - xs.min() + 1) * scale
            if w > DIR4_CELL_W:
                print(f"  넘어짐 {d} {k + 1}번 칸: 폭 {w:.0f}px > 칸 {DIR4_CELL_W}px (잘린다)")
    meta.update(fall_dirs=list(falls), fall_frames=n, fall_col=col)
    print(f"  {src.name}: 넘어짐 {n}장 ({', '.join(falls)}), 배율 {scale:.3f}")


def _place_punch(out: Image.Image, meta: dict, cid: str, src: Path, n: int, col: int) -> None:
    """주먹 콤보 시트를 col열부터 붙인다. 뻗은 팔이 옆 칸 경계를 넘어 그려지기도 해 좌우로 조금 더 읽고,
    가로는 몸통 가운데(위쪽 무게중심)를 칸 가운데에 맞춘다 (뻗은 팔 쪽으로 몸이 밀리지 않게).
    크기는 칸들의 가운데 키를 걷기 키의 PUNCH_H배로 (무릎을 굽힌 싸움 자세)."""
    rows = _sheet_rows(src, n)
    cells = load_cells(src, n, _sheet_nrows(src), drop_edge=True, pad=0.06, unmix=True,
                       keep_tint=cid in KEEP_TINT, hpad=0.2)
    if cid in KEEP_TINT and cid not in NEON:
        cells = {k: _despill(c) for k, c in cells.items()}
    punches = {d: [cells[(i, k)] for k in keep] for i, d, keep, _ in rows}
    hs = [c[3] for cs in punches.values() for c in cs if c]
    scale = BODY_H * 0.97 * PUNCH_H / max(float(np.median(hs)), 1.0)
    for d, cs in punches.items():
        r = DIR8.index(d)
        for k in range(n):
            cell = cs[k * len(cs) // n]
            place(out, cell, r, col + k, scale, DIR4_CELL_W)
            if cell is not None:
                xs = np.nonzero((cell[0][:, :, 3] > 40).any(0))[0]
                half = max(cell[2] - xs.min(), xs.max() - cell[2]) * scale
                if half > DIR4_CELL_W / 2:
                    print(f"  주먹 {d} {k + 1}번 칸: 몸 가운데에서 {half:.0f}px > 칸 반 {DIR4_CELL_W // 2}px (잘린다)")
    meta.update(punch_dirs=list(punches), punch_frames=n, punch_col=col)
    print(f"  {src.name}: 주먹 {n}장 ({', '.join(punches)}), 배율 {scale:.3f}")


MIRROR = {"e": "w", "w": "e", "se": "sw", "sw": "se", "ne": "nw", "nw": "ne", "s": "s", "n": "n"}
TONE_K = (0.8, 1.25)   ## 공격 그림 색을 걷기 그림에 맞출 때 채널마다 퍼짐 비율 한도
KO_CELL_W = 256       ## 넘어짐·기절 시트(kind ko) 칸 가로 — 누운 몸이 발끝에서 옆으로 뻗는다
ATTACK_H = 0.98        ## 공격 영상 첫 장(싸움 자세) 키 / 걷기 서 있기 키 — 무릎을 조금 굽힌다


def _tone_stats(rgba: np.ndarray) -> tuple:
    """불투명한 곳의 채널별 (평균, 퍼짐)"""
    px = rgba[rgba[:, :, 3] > 200][:, :3].astype(np.float64)
    return px.mean(0), px.std(0) + 1.0


def _video_sheets(cid: str) -> list:
    """영상에서 뽑은 동작 시트 (tools/punch_video_sheet.py): 주먹 공격·소총·권총·로켓포"""
    return [p for kind in ("attacks", "rifle", "pistol", "rocket", "jump", "ko") for p in sorted(SRC.glob(f"[0-9][0-9]_{cid}_{kind}_dir8.png"))]


def _place_attacks(walk: Image.Image, meta: dict, cid: str, src: Path, debug: bool) -> None:
    """영상에서 뽑은 공격 시트(tools/punch_video_sheet.py — 00_<id>_attacks_dir8.png + .json, 배경을 지운 투명 그림)를
    따로 한 장 assets/characters/<id>_attacks_dir8.png(8행 = DIR8 순서, 칸 128×112)로 낸다 — 걷기 시트 옆에 붙이면
    가로가 GPU 텍스처 한도(16384px)를 넘는다. 영상이 제자리라 모든 장을 줄마다 같은 발 기준점에 맞춘다(발이 미끄러지지 않게).
    크기·색은 같은 방향(없으면 좌우 짝) 걷기 서 있기 칸에 맞춘다 (첫 장 싸움 자세 키 = 걷기 키의 ATTACK_H배) —
    영상은 청바지가 회색이고 걷기 그림은 청록이라, 걷다 주먹을 지르면 옷 색이 바뀌어 보인다.
    .json에 attack_dirs·punch_attacks [{name, col, frames, hit_frame, duration}].
    소총·권총·로켓포 시트(kind rifle·pistol·rocket — 00_<id>_<kind>_dir8.png)도 같은 방식으로 <id>_<kind>_dir8.png를 내고
    <kind>_dirs·<kind>_clips [{name, col, frames, duration, loop}]·<kind>_muzzle(로켓포는 + _breech 발사관 뒤끝)을 적는다"""
    import json
    info = json.loads(src.with_suffix(".json").read_text())
    sheet = np.array(Image.open(src).convert("RGBA"))
    w, h = info["cell"]
    cols = sum(a["frames"] for a in info["attacks"])
    kind = info.get("kind", "attacks")
    cw = KO_CELL_W if kind == "ko" else DIR4_CELL_W   # 넘어져 누운 몸은 옆으로 길다 — 칸을 넓게 (발끝 x = cw / 2)
    out = Image.new("RGBA", (cw * cols, CELL_H * len(DIR8)), (0, 0, 0, 0))
    clipped = 0
    points = {}   ## 로켓포: 방향 → {tip, rear} 발끝 기준 게임 칸 px (위가 −)
    lifts = {}    ## 점프: 동작 번호 → {방향: 장마다 떠오른 높이 (게임 칸 px)}
    for i, row in enumerate(info["rows"]):
        r = DIR8.index(row["dir"])
        scale = BODY_H * 0.97 * PUNCH_H / row["stance_h"]
        fx, fy = row["foot"]
        tone = None
        for d in (row["dir"], MIRROR[row["dir"]]):
            if d in meta.get("dirs", []):
                k = DIR8.index(d)
                stand = np.asarray(walk.crop((0, k * CELL_H, DIR4_CELL_W, (k + 1) * CELL_H)))
                tone = (_tone_stats(sheet[i * h:(i + 1) * h, 0:w]), _tone_stats(stand))
                # 크기도 같은 방향 걷기 서 있기 키에 맞춘다 — 걷다 주먹을 지르는 순간 몸이 줄어 보이지 않게
                ys = np.nonzero((stand[:, :, 3] > 40).any(1))[0]
                scale = (ys.max() - ys.min() + 1) * ATTACK_H / row["stance_h"]
                break
        for n, a in enumerate(info["attacks"]):
            if "lift" in a:
                lifts.setdefault(n, {})[row["dir"]] = [round(v * scale, 2) for v in a["lift"][i]]
        if "points" in row:
            points[row["dir"]] = {k: [round((x - fx) * scale, 1), round((y - fy) * scale, 1)] for k, (x, y) in row["points"].items()}
        for c in range(cols):
            img = sheet[i * h:(i + 1) * h, c * w:(c + 1) * w]
            if tone:
                (sm, ss), (dm, ds) = tone
                img = img.copy()
                img[:, :, :3] = np.clip((img[:, :, :3] - sm) * np.clip(ds / ss, *TONE_K) + dm, 0, 255).astype(np.uint8)
            place(out, (img, fy, fx, row["stance_h"]), r, c, scale, cw)
            ys, xs = np.nonzero(img[:, :, 3] > 40)
            if xs.size and (max(fx - xs.min(), xs.max() - fx) * scale > cw / 2 or (fy - ys.min()) * scale > FOOT_Y):
                clipped += 1
                print(f"  공격 {row['dir']} {c}번 칸: 칸 밖으로 나간다 (잘린다)")
    out.save(DST / f"{cid}_{kind}_dir8.png")
    dirs = [row["dir"] for row in info["rows"]]
    if kind == "attacks":
        meta.update(attack_dirs=dirs, punch_attacks=[{k: a[k] for k in ("name", "col", "frames", "hit_frame", "duration")}
                                                     for a in info["attacks"]])
    else:
        meta[f"{kind}_dirs"] = dirs
        meta[f"{kind}_clips"] = [{k: a.get(k, False) for k in ("name", "col", "frames", "duration", "loop")} for a in info["attacks"]]
        for n, clip in enumerate(meta[f"{kind}_clips"]):
            if n in lifts:   # 점프: 발이 떨어지는·닿는 장 차례와 장마다 떠오른 높이 (게임이 그만큼 올려 그린다)
                clip.update(takeoff=info["attacks"][n]["takeoff"], land=info["attacks"][n]["land"], lift=lifts[n])
        if kind in ("rifle", "pistol"):
            meta[f"{kind}_muzzle"] = _gun_muzzles(np.asarray(out), dirs, info["attacks"][0], info.get("muzzle", {}))
        elif kind == "ko":
            meta[f"{kind}_head"] = _ko_heads(np.asarray(out), info, cw)
        elif points:
            # 로켓포: 탄두 끝(로켓이 나가는 곳)·발사관 뒤끝(후폭풍)을 영상에서 적은 점으로 (탄두를 지운 발사 장면이라 잴 수 없다)
            meta[f"{kind}_muzzle"] = {d: p["tip"] for d, p in points.items()}
            meta[f"{kind}_breech"] = {d: p["rear"] for d, p in points.items()}
    if debug:
        dbg = Image.new("RGBA", out.size, (110, 110, 110, 255))
        dbg.alpha_composite(out)
        dbg.save(DST.parent.parent / ".screenshots" / f"sprite_{cid}_{kind}_dir8.png")
    print(f"  {src.name}: {kind} {len(info['attacks'])}가지 {cols}장 ({', '.join(dirs)}), 잘린 칸 {clipped}")


def _ko_heads(sheet: np.ndarray, info: dict, cw: int) -> dict:
    """넘어짐 시트의 기절 머리 자리 {방향: [x, y]} — 쓰러짐(첫 동작) 마지막 장에서 머리 쪽(rows[].head) 끝 30% 안의 가장 높은 점.
    발끝 기준 칸 px(위가 −). 게임은 다 누운 뒤 그 위에 노란 별을 돌린다(Player._draw_out_stars)"""
    last = info["attacks"][0]["frames"] - 1
    heads = {}
    for row in info["rows"]:
        if "head" not in row:
            continue
        r = DIR8.index(row["dir"])
        a = sheet[r * CELL_H:(r + 1) * CELL_H, last * cw:(last + 1) * cw, 3] > 40
        ys, xs = np.nonzero(a)
        if not xs.size:
            continue
        span = xs.max() - xs.min()
        pick = xs <= xs.min() + span * 0.3 if row["head"] == "left" else xs >= xs.max() - span * 0.3
        hx = float(np.median(xs[pick]))
        heads[row["dir"]] = [round(hx - cw / 2, 1), float(ys[pick].min() - FOOT_Y)]
    return heads


def _gun_muzzles(sheet: np.ndarray, dirs: list, aim: dict, fixed: dict) -> dict:
    """총구 자리 {방향: [x, y]} — 조준 장면 칸마다 가슴 높이 띠(발끝 위 48~93px)에서 총 쪽으로 가장 나간 점의 평균.
    발끝 기준 칸 px(위가 −)이고 게임이 총알 궤적·총구 불꽃을 여기서 시작한다(PersonRig.gun_muzzle).
    화면 쪽·화면 위로 겨눈 ↓·↑는 총이 몸 앞뒤에 겹쳐 잴 수 없어 매니페스트 muzzle {방향: [x, y]}(같은 단위)로 적는다"""
    out = {d: list(v) for d, v in fixed.items() if d in dirs}
    for d in dirs:
        if d in out:
            continue
        r = DIR8.index(d)
        side = 1 if "e" in d else -1 if "w" in d else 0
        pts = []
        for c in range(aim["col"], aim["col"] + aim["frames"]):
            cell = sheet[r * CELL_H + FOOT_Y - 93:r * CELL_H + FOOT_Y - 48, c * DIR4_CELL_W:(c + 1) * DIR4_CELL_W, 3] > 100
            ys, xs = np.nonzero(cell)
            if xs.size == 0:
                continue
            i = np.argmax(xs * side) if side else (np.argmin(ys) if d == "n" else np.argmax(ys))
            pts.append((xs[i] - DIR4_CELL_W // 2, ys[i] - 93))
        if pts:
            out[d] = [round(float(v), 1) for v in np.mean(pts, 0)]
    return out


def process_dir8_sheet(cid: str, walk_src: "Path | None", frames: int, run_src: "Path | None", run_frames: int, debug: bool,
                       fall_src: "Path | None" = None, fall_frames: int = 0,
                       punch_src: "Path | None" = None, punch_frames: int = 0) -> None:
    """한 장짜리 8방향 걷기 시트 NN_<id>_walk<N>_dir8.png (N열 × 5행: ↓ · ↙ · ← · ↖ · ↑, 줄마다 한 바퀴 N장 — 예: walk24, walk12)
    [+ 달리기 시트 NN_<id>_run<M>_dir8.png (M열, 줄 배치·줄 수가 다르면 .rows.txt — 8행이면 8방향 모두 그림대로)]
    [+ 넘어짐 시트 NN_<id>_fall<K>_dir8.png (K열: 서 있기에서 바닥에 엎드리기까지, 마지막 칸이 누운 자세 — 달리기·도는 장면 다음 칸)]
    [+ 주먹 콤보 시트 NN_<id>_combo<P>_dir8.png (P열: 싸움 자세 → 잽 → 스트레이트 → 훅 → 싸움 자세 — 넘어짐 다음 칸)]
    → assets/characters/<id>_dir8.png (8행 = DIR8 순서, 0열 서 있기 + 1~N열 걷기 [+ N+1~N+M열 달리기], 칸 128×112)
      + .json (dirs·frames [+ run_dirs·run_frames]). 방향별 시트(walk8·key8)가 있어도 이것으로 모두 바꾼다.
    배경(초록·마젠타)은 그림 전체에서 섞인 만큼 푼다(unmix_key) — 팔·다리 틈이 어두운 배경색으로 칠해진 압축 그림이다.
    달리기 크기는 머리 폭 비율로 걷기에 맞춘다(몸을 숙여 키가 줄어든다).
    걷기 시트 없이 달리기만 있으면(walk_src None) 걷기 칸 없이 달리기만 넣는다(.json dirs [] · frames 0) —
    게임은 서 있기·걷기를 예전 그림으로, 달리기만 이것으로 그린다. 키는 걷기 키의 RUN_H_RANGE 가운데로."""
    opts = dict(drop_edge=True, pad=0.06, unmix=True, keep_tint=cid in KEEP_TINT, hpad=0.15)
    walk_rows = _sheet_rows(walk_src, frames) if walk_src else []
    cells = load_cells(walk_src, frames, _sheet_nrows(walk_src), **opts) if walk_src else {}
    run_rows = _sheet_rows(run_src, run_frames) if run_src else []
    turns = [(d, t) for _, d, _, t in run_rows if t]
    cols = 1 + frames + (run_frames if run_src else 0) + sum(len(t[1]) for _, t in turns) + (fall_frames if fall_src else 0) + (punch_frames if punch_src else 0)
    out = Image.new("RGBA", (DIR4_CELL_W * cols, CELL_H * len(DIR8)), (0, 0, 0, 0))
    present, scales, heads = [], {}, []
    for i, d, keep, _ in walk_rows:
        r = DIR8.index(d)
        walk = [c for c in (cells[(i, k)] for k in keep) if c]
        heights = [c[3] for c in walk]
        scale = BODY_H * 0.97 / max(float(np.median(heights)), 1.0)
        scales[d] = scale
        heads += [_head_w(c) * scale for c in walk]
        place(out, min(walk, key=_spread), r, 0, scale, DIR4_CELL_W)
        for k in range(frames):
            place(out, walk[k * len(walk) // frames], r, 1 + k, scale, DIR4_CELL_W)
        present.append(d)
    meta = {"dirs": present, "frames": frames}
    if run_src:
        rcells = load_cells(run_src, run_frames, _sheet_nrows(run_src), **opts)
        if cid in KEEP_TINT and cid not in NEON:
            rcells = {k: _despill(c) for k, c in rcells.items()}
        runs = {d: [c for c in (rcells[(i, k)] for k in keep) if c] for i, d, keep, _ in run_rows}
        # 걷기 그림의 머리 폭(게임 크기)과 같아지게
        run_head = float(np.median([_head_w(c) for cs in runs.values() for c in cs]))
        run_h = float(np.median([c[3] for cs in runs.values() for c in cs]))
        if heads:
            scale = float(np.median(heads)) / max(run_head, 1.0)
            # 머리를 크게 그린 그림이면 몸이 작아진다 — 달리기 키가 걷기 키의 85~92% 안에 들게 (숙인 만큼만 작게)
            scale = min(max(scale, BODY_H * 0.97 * RUN_H_RANGE[0] / run_h), BODY_H * 0.97 * RUN_H_RANGE[1] / run_h)
            if cid in RUN_H_OF:
                scale = BODY_H * 0.97 * RUN_H_OF[cid] / run_h
        else:
            scale = BODY_H * 0.97 * sum(RUN_H_RANGE) / 2 / run_h
        for d, run in runs.items():
            r = DIR8.index(d)
            # 줄마다 키를 맞춘다 — 생성 그림은 ↓ 줄을 다른 줄보다 20%쯤 작게 그리곤 한다 (걷기는 줄마다 같은 키로 맞춘다)
            row_k = min(max(run_h / max(float(np.median([c[3] for c in run])), 1.0), RUN_ROW_K[0]), RUN_ROW_K[1])
            for k in range(run_frames):
                place(out, run[k * len(run) // run_frames], r, 1 + frames + k, scale * row_k, DIR4_CELL_W)
        meta.update(run_dirs=list(runs), run_frames=run_frames)
        # 도는 장면: 달리기 다음 칸에 (도는 장면이 시작하는 방향) 행으로 붙인다. 게임은 그 두 방향 사이를 오갈 때 넘긴다
        col = 1 + frames + run_frames
        meta["turns"] = []
        for i, d, _, turn in run_rows:
            if not turn:
                continue
            clip = [c for c in (rcells[(i, k)] for k in turn[1]) if c]
            for k, cell in enumerate(clip):
                place(out, cell, DIR8.index(d), col + k, scale, DIR4_CELL_W)
            meta["turns"].append({"from": d, "to": turn[0], "col": col, "n": len(clip)})
            print(f"  도는 장면 {d}→{turn[0]} {len(clip)}장")
            col += len(clip)
        print(f"  {run_src.name}: 달리기 {run_frames}장 ({', '.join(f'{d} {len(c)}장' for d, c in runs.items())}), 배율 {scale:.3f}")
    after_run = 1 + frames + (run_frames if run_src else 0) + sum(t["n"] for t in meta.get("turns", []))
    if fall_src:
        _place_fall(out, meta, cid, fall_src, fall_frames, after_run)
    if punch_src:
        _place_punch(out, meta, cid, punch_src, punch_frames, after_run + (fall_frames if fall_src else 0))
    DST.mkdir(parents=True, exist_ok=True)
    for attacks in _video_sheets(cid):
        _place_attacks(out, meta, cid, attacks, debug)
    out.save(DST / f"{cid}_dir8.png")
    import json
    (DST / f"{cid}_dir8.json").write_text(json.dumps(meta))
    if debug:
        dbg = Image.new("RGBA", out.size, (110, 150, 110, 255))
        dbg.alpha_composite(out)
        dbg.save(DST.parent.parent / ".screenshots" / f"sprite_{cid}_dir8.png")
    print(f"{cid}: " + (f"8방향 걷기 한 장 시트 {frames}장 ({', '.join(present)})" if walk_src else "걷기 시트 없음 (서 있기·걷기는 예전 그림)")
          + (f" · 달리기 {run_frames}장" if run_src else ""))

def main() -> None:
    debug = "--debug" in sys.argv
    # NN_<id>.png 전부 (NN은 순서일 뿐, id가 data/npc 파일 이름과 같아야 한다). 인자로 id를 주면 그것만
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--attacks-only" in sys.argv:
        # 공격 시트만 다시: 지금 걷기 시트(assets/characters/<id>_dir8.png)는 그대로 두고 크기·색 기준으로만 읽는다
        import json
        for src in [p for kind in ("attacks", "rifle", "pistol", "rocket", "jump", "ko") for p in sorted(SRC.glob(f"[0-9][0-9]_*_{kind}_dir8.png"))]:
            cid = re.sub(r"_(attacks|rifle|pistol|rocket|jump|ko)_dir8$", "", src.stem[3:])
            if only and cid not in only:
                continue
            meta = json.loads((DST / f"{cid}_dir8.json").read_text())
            _place_attacks(Image.open(DST / f"{cid}_dir8.png").convert("RGBA"), meta, cid, src, debug)
            (DST / f"{cid}_dir8.json").write_text(json.dumps(meta))
        return
    for src in sorted(SRC.glob("[0-9][0-9]_*.png")):
        if src.stem.endswith(EXTRA) or any(t in src.stem for t in ("_walk8_", "_key8_", "_walk_dir4_", "_run_dir4_")) or src.stem.endswith("_dir8"):
            continue
        cid = src.stem[3:]
        if not only or cid in only:
            process(src, cid, debug)
    dir8: dict = {}
    for kind in ("_walk8_", "_key8_"):          # 나중 것(key8)이 덮어쓴다
        for src in sorted(SRC.glob(f"[0-9][0-9]_*{kind}*.png")):
            cid, d = src.stem[3:].rsplit(kind, 1)
            if d in DIR8:
                dir8.setdefault(cid, {})[d] = src
    for cid, sources in dir8.items():
        if not only or cid in only:
            process_dir8(cid, sources, debug)
    walked = set()
    for src in sorted(SRC.glob("[0-9][0-9]_*_walk*_dir8.png")):      # 한 장짜리 시트가 있으면 방향별 시트를 덮어쓴다
        m = re.fullmatch(r"\d\d_(.+)_walk(\d+)_dir8", src.stem)
        if m and (not only or m[1] in only):
            runs = [(r, int(rm[1])) for r in sorted(SRC.glob(f"{src.stem[:2]}_{m[1]}_run*_dir8.png"))
                    if (rm := re.fullmatch(rf"\d\d_{re.escape(m[1])}_run(\d+)_dir8", r.stem))]
            run_src, run_n = runs[0] if runs else (None, 0)
            falls = [(f, int(fm[1])) for f in sorted(SRC.glob(f"{src.stem[:2]}_{m[1]}_fall*_dir8.png"))
                     if (fm := re.fullmatch(rf"\d\d_{re.escape(m[1])}_fall(\d+)_dir8", f.stem))]
            fall_src, fall_n = falls[0] if falls else (None, 0)
            combos = [(f, int(cm[1])) for f in sorted(SRC.glob(f"{src.stem[:2]}_{m[1]}_combo*_dir8.png"))
                      if (cm := re.fullmatch(rf"\d\d_{re.escape(m[1])}_combo(\d+)_dir8", f.stem))]
            punch_src, punch_n = combos[0] if combos else (None, 0)
            process_dir8_sheet(m[1], src, int(m[2]), run_src, run_n, debug, fall_src, fall_n, punch_src, punch_n)
        if m:
            walked.add(m[1])
    for src in sorted(SRC.glob("[0-9][0-9]_*_run*_dir8.png")):       # 걷기 시트 없이 달리기만 받은 인물 (걷기 시트가 오면 위에서 같이 붙는다)
        m = re.fullmatch(r"\d\d_(.+)_run(\d+)_dir8", src.stem)
        if m and m[1] not in walked and m[1] not in dir8 and (not only or m[1] in only):
            process_dir8_sheet(m[1], None, 0, src, int(m[2]), debug)
    for src in sorted(SRC.glob("[0-9][0-9]_*_walk_dir4.png")):
        cid = src.stem[3:-len("_walk_dir4")]
        if not only or cid in only:
            process_dir4(src, cid, debug)
    if "--check-legs" in sys.argv:
        # 한 바퀴 시트의 초록 다리 표시 검사 (코덱스·제미나이가 반대 다리를 제대로 그렸는지)
        if not LEG_MARKS and not DIR8_CHECKS:
            print("검사할 한 바퀴 시트가 없다")
            sys.exit(2)
        ok = check_legs() if LEG_MARKS else True
        if DIR8_CHECKS:
            print(f"  8방향 열쇠 장면: {sum(DIR8_CHECKS)}/{len(DIR8_CHECKS)} 통과")
            ok &= all(DIR8_CHECKS)
        if not ok:
            sys.exit(1)
    from gen_motion_index import write_index   # 모션 편집기 "게임 그림" 탭 목록
    write_index()


if __name__ == "__main__":
    main()
