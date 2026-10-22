#!/usr/bin/env python3
"""제자리에서 걷는(달리는) 인물 영상에서 방향마다 걸음 한 바퀴를 골라 8방향 시트로 만든다.

영상은 단색 배경(초록 등)에 인물이 제자리걸음을 하며 천천히 방향을 바꾸는 것이다 (생성 영상).
배경은 여기서 지워 투명 PNG로 낸다 (key_out). 결과는 prepare_character_sprites.py가 읽는 한 장짜리 시트 NN_<id>_walk<N>_dir8.png / _run<N>_dir8.png
(N열 × 줄, 줄마다 한 바퀴 N장) + 줄 방향을 적은 .rows.txt.

1) 고를 곳 찾기 — 구간 안에서 처음과 끝이 가장 닮은 한 바퀴 (몸통 가운데·발끝을 맞춰 비교):
   python3 tools/video_cycle_sheet.py find 영상.mp4 --crop 405,0,470,720 --range 300-480 --period 24-32 [--mirror 11-18]
   --mirror는 반걸음을 좌우로 뒤집어 나머지 반을 만드는 경우 (앞·뒷모습처럼 좌우가 같은 방향만 — 영상이 계속 돌아 한 바퀴가 안 이어질 때)
2) 시트 만들기 — 줄마다 "방향:시작+길이" (영상 장 번호는 1부터, 24fps면 n번 = (n−1)/24초). 끝에 m을 붙이면 반걸음 + 뒤집은 반걸음:
   python3 tools/video_cycle_sheet.py sheet 영상.mp4 --crop 405,0,470,720 --frames 24 \\
       --out output/imagegen/characters/00_player_walk24_dir8.png s:256+34 se:431+28 e:144+29 n:107+15m
   길이가 N과 다르면 한 바퀴를 N장으로 고르게 뽑는다. 그 뒤 python3 tools/prepare_character_sprites.py --debug
"""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps


SPILL = 4.0


def extract(video: str, crop: str, lo: int, hi: int) -> dict:
    """영상의 lo~hi번 장(1부터)을 crop(x,y,w,h)으로 잘라 {번호: RGB 그림}"""
    x, y, w, h = (int(v) for v in crop.split(","))
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ffmpeg", "-v", "error", "-i", video, "-vf",
                        f"select='between(n\\,{lo - 1}\\,{hi - 1})',crop={w}:{h}:{x}:{y}", "-vsync", "0",
                        f"{tmp}/%05d.png"], check=True)
        files = sorted(Path(tmp).glob("*.png"))
        return {lo + k: Image.open(f).convert("RGB").copy() for k, f in enumerate(files)}


def figure_mask(img: Image.Image) -> np.ndarray:
    """배경(테두리 가운데값 색)과 먼 곳 — 인물"""
    a = np.asarray(img).astype(np.int32)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)
    return np.sqrt(((a - bg) ** 2).sum(axis=2)) > 90


def key_out(img: Image.Image, flood: float = 55.0, hole: float = 45.0, solid: float = 100.0) -> Image.Image:
    """배경을 지운 RGBA. 테두리와 이어진 배경색 가까운 곳(flood 안)과 어디든 아주 가까운 곳(hole 안, 팔과 몸 사이 틈)을 지우고,
    배경에서 2px 안 가장자리는 배경색과 먼 만큼만 남기며 색에서 배경을 뺀다.
    prepare_character_sprites.py의 원색 배경 문턱(90)은 쓰지 않는다 — 생성 영상의 초록이 덜 진해(55,181,102)
    청바지 밝은 곳(배경과 75~90)까지 구멍이 난다"""
    a = np.asarray(img).astype(np.float64)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)
    d = np.sqrt(((a - bg) ** 2).sum(axis=2))
    passable = d < flood
    seen = np.zeros_like(passable)
    seen[0], seen[-1], seen[:, 0], seen[:, -1] = passable[0], passable[-1], passable[:, 0], passable[:, -1]
    while True:
        grown = seen.copy()
        grown[1:] |= seen[:-1]
        grown[:-1] |= seen[1:]
        grown[:, 1:] |= seen[:, :-1]
        grown[:, :-1] |= seen[:, 1:]
        grown &= passable
        if (grown == seen).all():
            break
        seen = grown
    bgm = seen | (d < hole)
    near = bgm.copy()
    for _ in range(2):
        grown = near.copy()
        grown[1:] |= near[:-1]
        grown[:-1] |= near[1:]
        grown[:, 1:] |= near[:, :-1]
        grown[:, :-1] |= near[:, 1:]
        near = grown
    alpha = np.where(bgm, 0.0, 1.0)
    ring = near & ~bgm
    alpha[ring] = np.clip((d[ring] - 20.0) / (solid - 20.0), 0.0, 1.0)
    k = np.maximum(alpha, 0.05)[..., None]
    color = np.clip((a - (1.0 - k) * bg) / k, 0, 255)
    # 생성 영상은 전체가 초록빛으로 물들어 있다 — 초록이 빨강·파랑 중 큰 쪽을 SPILL 넘게 넘지 않게 (살색·청바지는 그대로)
    color[:, :, 1] = np.minimum(color[:, :, 1], np.maximum(color[:, :, 0], color[:, :, 2]) + SPILL)
    rgba = np.dstack([color, alpha * 255.0]).astype(np.uint8)
    rgba[alpha <= 0.02] = 0
    return Image.fromarray(rgba)


def signature(img: Image.Image) -> np.ndarray:
    """비교용 작은 회색 그림 — 몸통 가운데(위쪽 반 무게중심)·발끝을 맞춘다 (제자리걸음도 조금씩 흔들린다)"""
    fg = figure_mask(img)
    ys, xs = np.nonzero(fg)
    top, bot = ys.min(), ys.max()
    up = ys < top + (bot - top) // 2
    cx = int(xs[up].mean())
    gray = np.where(fg, np.asarray(img).mean(axis=2), 255.0)
    h, w = gray.shape
    can = np.full((h + 40, w), 255.0)
    dx, dy = w // 2 - cx, h + 20 - bot
    src = gray[max(0, -dy):, max(0, -dx):]
    sub = src[:can.shape[0] - max(0, dy), :w - max(0, dx)]
    can[max(0, dy):max(0, dy) + sub.shape[0], max(0, dx):max(0, dx) + sub.shape[1]] = sub
    return np.asarray(Image.fromarray(can.astype(np.uint8)).resize((70, 95), Image.BILINEAR)).astype(float)


def cmd_find(args) -> None:
    lo, hi = (int(v) for v in args.range.split("-"))
    frames = extract(args.video, args.crop, lo, hi)
    sig = {i: signature(im) for i, im in frames.items()}
    if args.period:
        pmin, pmax = (int(v) for v in args.period.split("-"))
        best = sorted((np.abs(sig[a] - sig[a + p]).mean(), a, p) for a in sig for p in range(pmin, pmax + 1) if a + p in sig)
        print("한 바퀴 (시작+길이 차이):", " ".join(f"{a}+{p} {v:.1f}" for v, a, p in best[:args.top]))
    if args.mirror:
        hmin, hmax = (int(v) for v in args.mirror.split("-"))
        best = sorted((np.abs(np.fliplr(sig[a]) - sig[a + p]).mean(), a, p) for a in sig for p in range(hmin, hmax + 1) if a + p in sig)
        print("반걸음+뒤집기 (시작+길이m 차이):", " ".join(f"{a}+{p}m {v:.1f}" for v, a, p in best[:args.top]))
    print("차이가 3 아래면 이음매가 거의 안 보인다, 8 넘으면 튄다")


def cmd_sheet(args) -> None:
    specs = []
    for s in args.rows:
        d, _, rest = s.partition(":")
        mirror = rest.endswith("m")
        a, _, p = rest.rstrip("m").partition("+")
        specs.append((d, int(a), int(p), mirror))
    lo = min(a for _, a, _, _ in specs)
    hi = max(a + p for _, a, p, _ in specs)
    frames = extract(args.video, args.crop, lo, hi)
    used = {a + k for _, a, p, _ in specs for k in range(p)}
    frames = {i: key_out(im) for i, im in frames.items() if i in used}
    if args.scale != 1.0:
        w0, h0 = next(iter(frames.values())).size
        size = (round(w0 * args.scale), round(h0 * args.scale))
        frames = {i: im.resize(size, Image.LANCZOS) for i, im in frames.items()}
    w, h = next(iter(frames.values())).size
    n = args.frames
    out = Image.new("RGBA", (w * n, h * len(specs)), (0, 0, 0, 0))
    for r, (d, a, p, mirror) in enumerate(specs):
        cycle = [frames[a + k] for k in range(p)]
        if mirror:
            cycle += [ImageOps.mirror(im) for im in cycle]
        for k in range(n):
            out.paste(cycle[round(k * len(cycle) / n) % len(cycle)], (k * w, r * h))
    dst = Path(args.out)
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst)
    rows = dst.with_name(dst.stem + ".rows.txt")
    rows.write_text(f"# {Path(args.video).name} 에서 뽑음 (video_cycle_sheet.py) — 줄마다 방향\n"
                    + "".join(f"{d}  # {a}+{p}{'m' if m else ''}\n" for d, a, p, m in specs))
    print(f"{dst} ({n}열 × {len(specs)}줄, 칸 {w}×{h}) + {rows.name}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("find")
    f.add_argument("video")
    f.add_argument("--crop", required=True, help="x,y,w,h — 옆 인물 조각이 들어오지 않게")
    f.add_argument("--range", required=True, help="찾을 장 번호 구간 (예: 300-480)")
    f.add_argument("--period", help="한 바퀴 길이 범위 (예: 24-32)")
    f.add_argument("--mirror", help="반걸음 길이 범위 (예: 11-18)")
    f.add_argument("--top", type=int, default=5)
    s = sub.add_parser("sheet")
    s.add_argument("video")
    s.add_argument("--crop", required=True)
    s.add_argument("--frames", type=int, required=True, help="줄마다 장 수 N (파일 이름의 walk<N>·run<N>과 같게)")
    s.add_argument("--out", required=True)
    s.add_argument("--scale", type=float, default=0.5, help="칸을 줄이는 배율 (게임 키는 96px — 다듬기 도구가 큰 시트에서 느리다)")
    s.add_argument("rows", nargs="+", help="방향:시작+길이[m]")
    args = ap.parse_args()
    {"find": cmd_find, "sheet": cmd_sheet}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
