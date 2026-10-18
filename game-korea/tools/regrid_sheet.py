#!/usr/bin/env python3
"""줄 간격이 고르지 않은 생성 시트를 고른 칸으로 다시 짠다 (단색 초록 배경).

생성 그림은 칸을 꽉 채워 그려 모자가 윗줄 칸 안으로 넘어가곤 한다 — 고른 칸으로 자르면 머리가 잘린다.
그림 덩어리(이어진 조각)마다 가운데가 가장 가까운 줄·열 칸에 넣고, 줄마다 가장 아래 발끝을
새 칸의 같은 높이에 맞춰 넉넉한 칸(기본 160×240)에 옮겨 그린다. 줄 안의 위아래 들썩임은 그대로 남는다.
실행: python3 tools/regrid_sheet.py 원본.png 결과.png 열 줄 [칸가로 칸세로]
"""
import sys
from collections import deque

import numpy as np
from PIL import Image

KEY = (0, 255, 0)


def _fg(px: np.ndarray) -> np.ndarray:
    r, g, b = px[:, :, 0], px[:, :, 1], px[:, :, 2]
    return ~((g > 170) & (r < 130) & (b < 130))


def _label(mask: np.ndarray):
    """이어진 조각 (8방향 이웃) → [(넓이, 가운데 y, 가운데 x, 점 목록)]"""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    out = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)])
        seen[y0, x0] = True
        pts = []
        while q:
            y, x = q.popleft()
            pts.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
        a = np.array(pts)
        out.append((len(pts), a[:, 0].mean(), a[:, 1].mean(), a))
    return out


def regrid(src: str, dst: str, cols: int, rows: int, cw: int = 160, ch: int = 240) -> None:
    px = np.asarray(Image.open(src).convert("RGB"))
    h, w = px.shape[:2]
    mask = _fg(px)
    # 칸 테두리에 붙은 배경 섞인 가장자리까지 가져가게 1px 넓힌다
    grow = mask.copy()
    grow[1:] |= mask[:-1]; grow[:-1] |= mask[1:]; grow[:, 1:] |= mask[:, :-1]; grow[:, :-1] |= mask[:, 1:]
    parts = [p for p in _label(grow) if p[0] >= 12]
    # 줄 가운데: 큰 조각의 가운데 y를 줄 수만큼 묶는다 (고른 칸에서 시작해 몇 번 다듬는다)
    big = [p for p in parts if p[0] > 400]
    centers = np.array([(r + 0.5) * h / rows for r in range(rows)])
    for _ in range(10):
        groups = [[] for _ in range(rows)]
        for p in big:
            groups[int(np.argmin(abs(centers - p[1])))].append(p[1])
        centers = np.array([np.mean(g) if g else centers[i] for i, g in enumerate(groups)])
    cells = {}
    for p in parts:
        r = int(np.argmin(abs(centers - p[1])))
        c = min(cols - 1, int(p[2] // (w / cols)))
        cells.setdefault((r, c), []).append(p[3])
    foot = {r: max(a[:, 0].max() for (rr, _), ps in cells.items() if rr == r for a in ps) for r in range(rows)}
    out = np.zeros((ch * rows, cw * cols, 3), np.uint8)
    out[:, :] = KEY
    over = 0
    for (r, c), ps in cells.items():
        oy = r * ch + int(ch * 0.94) - foot[r]
        ox = c * cw + cw // 2 - int((c + 0.5) * w / cols)
        for a in ps:
            ys, xs = a[:, 0] + oy, a[:, 1] + ox
            ok = (ys >= r * ch) & (ys < (r + 1) * ch) & (xs >= c * cw) & (xs < (c + 1) * cw)
            over += int((~ok).sum())
            out[ys[ok], xs[ok]] = px[a[ok, 0], a[ok, 1]]
    Image.fromarray(out).save(dst)
    miss = [(r, c) for r in range(rows) for c in range(cols) if (r, c) not in cells]
    print(f"{dst}: {cols}×{rows}칸 {cw}×{ch}, 줄 가운데 {[int(v) for v in centers]}"
          + (f", 빈 칸 {miss}" if miss else "") + (f", 칸 밖으로 잘린 점 {over}" if over else ""))


if __name__ == "__main__":
    a = sys.argv[1:]
    regrid(a[0], a[1], int(a[2]), int(a[3]), *(int(v) for v in a[4:6]))
