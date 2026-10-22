#!/usr/bin/env python3
"""통째 낮 그림에서 창 유리를 찾아 불빛 그림(_lights.png)을 만든다 — 생성기가 불빛 그림을 못 그렸거나 낮 그림과 안 맞을 때.

창 = 둘레 벽보다 훨씬 어두운 작은 덩어리, 또는 어두운 청록 유리 빛깔 덩어리(1층 상가 유리). 둘레(덩어리 밖 몇 px 띠)가 밝은 벽이어야 하고,
얇은 선(옥상 이음·줄눈)은 열기(opening)로 지우며, 부지 바닥의 볼라드처럼 둘레가 어두운 회색 바닥인 것은 뺀다.
켜지는 색은 따뜻한 창 불빛, 큰 덩어리(1층 상가 유리)는 형광등 흰빛. 나머지는 순수 검정.
결과는 prepare_building_sprites.py가 그대로 읽는다 (같은 캔버스라 맞추기 없이 겹친다).

사용: python3 tools/derive_window_lights.py <ID_부지_컨셉> [...] [--mirror=<새 이름>] [--debug]
--mirror=<새 이름>  낮 그림과 만든 불빛 그림을 좌우로 뒤집어 <새 이름>.png · _lights.png로도 낸다
                   (half_x 가이드와 half_y 가이드가 거울상일 때 — 오피스텔)
--debug           찾은 창을 낮 그림 위에 빨갛게 칠한 <이름>_lights_debug.png
"""

import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_building_textures import grow  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "output/imagegen/buildings/whole"

DARK = 0.55          # 둘레 평균 밝기의 이 배보다 어두우면 유리 후보
DARK_MAX = 115.0     # 이보다 밝으면 유리가 아니다
AREA = (30, 6000)    # 창 한 칸 넓이 범위 (px)
RING = 5             # 둘레 띠 두께 (px)
WALL_MIN = 125.0     # 둘레 띠 평균 밝기가 이보다 낮으면 벽에 박힌 창이 아니다 (바닥)
TALL_MIN = 14        # 이보다 납작한 덩어리는 창이 아니다 (부지 바닥의 볼라드·턱)
TEAL = 35.0         # 파랑 − 빨강이 이보다 크고 어두우면 유리 빛깔 (둘레와 상관없이 — 1층 상가 큰 유리)
TEAL_LUM = 100.0
SHOP_AREA = 900      # 이보다 큰 덩어리는 1층 상가 유리 (형광등 흰빛)
WARM = np.array([255, 205, 120], np.float32)
COOL = np.array([235, 240, 225], np.float32)


def lum(a: np.ndarray) -> np.ndarray:
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def box_mean(a: np.ndarray, k: int) -> np.ndarray:
    """k×k 상자 평균 (가장자리는 안쪽 칸만)."""
    r = k // 2
    pad = np.pad(a, r + 1, mode="edge").cumsum(0).cumsum(1)
    h, w = a.shape
    s = pad[k:k + h, k:k + w] - pad[:h, k:k + w] - pad[k:k + h, :w] + pad[:h, :w]
    return s / (k * k)


def shrink(mask: np.ndarray) -> np.ndarray:
    return ~grow(~mask, 1)


def label(mask: np.ndarray) -> list:
    """4방향으로 이어진 덩어리마다 (ys, xs) 좌표 배열."""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    out = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        seen[y0, x0] = True
        q = deque([(y0, x0)])
        ys, xs = [], []
        while q:
            y, x = q.popleft()
            ys.append(y)
            xs.append(x)
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    q.append((ny, nx))
        out.append((np.array(ys), np.array(xs)))
    return out


def windows(day: np.ndarray) -> np.ndarray:
    """창 덩어리 이름표 그림 (0 = 창 아님, 1… = 창 번호)."""
    rgb = day[..., :3].astype(np.float32)
    key = (rgb[..., 0] > 180) & (rgb[..., 1] < 90) & (rgb[..., 2] > 180)   # 마젠타 배경
    y = lum(rgb)
    y[key] = 0.0
    local = box_mean(y, 41)
    dark = (y < local * DARK) | (y < 45.0)
    dark &= (y < DARK_MAX) & ~key
    dark = grow(shrink(dark), 1)   # 열기: 옥상 이음·줄눈 같은 1~2px 선을 지운다
    near_key = grow(key, RING + 2)
    labels = np.zeros(y.shape, np.int32)
    n = 0
    for ys, xs in label(dark):
        if not (AREA[0] <= len(ys) <= AREA[1]) or ys.max() - ys.min() + 1 < TALL_MIN or near_key[ys, xs].any():
            continue   # 너무 작거나 크다 · 건물 윤곽 바깥 선
        y0, y1 = max(ys.min() - RING, 0), ys.max() + RING + 1
        x0, x1 = max(xs.min() - RING, 0), xs.max() + RING + 1
        blob = np.zeros((y1 - y0, x1 - x0), bool)
        blob[ys - y0, xs - x0] = True
        ring = grow(blob, RING) & ~dark[y0:y1, x0:x1]
        if ring.sum() == 0 or y[y0:y1, x0:x1][ring].mean() < WALL_MIN:
            continue   # 둘레가 벽이 아니다 (바닥·볼라드)
        n += 1
        labels[ys, xs] = n
    # 1층 상가 유리는 둘레(간판·바닥)가 어둡고 넓어 위 검사에 안 걸린다 — 유리 빛깔로 따로 찾는다
    teal = (rgb[..., 2] - rgb[..., 0] > TEAL) & (y < TEAL_LUM) & ~key & (labels == 0)
    teal = grow(shrink(teal), 1)
    for ys, xs in label(teal):
        if len(ys) >= AREA[0] and ys.max() - ys.min() + 1 >= TALL_MIN and not near_key[ys, xs].any():
            n += 1
            labels[ys, xs] = n
    return labels


def lights(day: np.ndarray, labels: np.ndarray) -> np.ndarray:
    out = np.zeros(day.shape[:2] + (3,), np.float32)
    lit = labels > 0
    areas = np.bincount(labels.ravel())
    shop = lit & (areas[labels] > SHOP_AREA)
    # 유리의 밝고 어두운 결을 조금 남긴다 (반사 줄이 있는 창)
    shade = 0.8 + 0.2 * (lum(day[..., :3].astype(np.float32)) / 120.0).clip(0, 1)
    out[lit & ~shop] = WARM * shade[lit & ~shop, None]
    out[shop] = COOL * shade[shop, None]
    return out.clip(0, 255).astype(np.uint8)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    mirror = next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--mirror=")), None)
    debug = "--debug" in sys.argv
    if mirror and len(args) != 1:
        sys.exit("--mirror는 한 장씩")
    for name in args:
        day_img = Image.open(SRC / f"{name}.png").convert("RGBA")
        day = np.asarray(day_img)
        labels = windows(day)
        light = Image.fromarray(lights(day, labels))
        light.save(SRC / f"{name}_lights.png")
        print(f"{name}: 창 {len(np.unique(labels)) - 1}개 → {name}_lights.png")
        if debug:
            dbg = day[..., :3].copy()
            dbg[labels > 0] = (dbg[labels > 0] * 0.3 + np.array([255, 0, 0]) * 0.7).astype(np.uint8)
            Image.fromarray(dbg).save(SRC / f"{name}_lights_debug.png")
        if mirror:
            day_img.transpose(Image.FLIP_LEFT_RIGHT).save(SRC / f"{mirror}.png")
            light.transpose(Image.FLIP_LEFT_RIGHT).save(SRC / f"{mirror}_lights.png")
            print(f"  좌우 뒤집기 → {mirror}.png · _lights.png")


if __name__ == "__main__":
    main()
