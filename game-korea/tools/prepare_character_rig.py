#!/usr/bin/env python3
"""관절 인형용 몸 조각 그림(코덱스·제미나이 원본)을 게임용 조각판으로 다듬는다.

원본: output/imagegen/characters/rig/NN_<id>_rig.png — 1536×768, 6열×2행 (칸 256×384), 단색 배경(마젠타 권장)
  열: 0 머리 · 1 몸통 · 2 윗팔 · 3 아랫팔+손 · 4 허벅지 · 5 정강이+발
  행: 0 앞모습(화면 오른쪽 아래를 봄) · 1 뒷모습(오른쪽 위)
  조각은 모두 세워 그린다: 머리는 목이 아래, 나머지는 몸에 붙는 관절이 위이고 아래로 곧게 늘어진다.
  요청 규칙은 output/imagegen/characters/CODEX_RIG_PROMPT.md
결과: assets/characters/rig/<id>.png (조각을 모은 그림) + <id>.json (조각마다 그림 속 자리·관절 점·길이)
  - 배율은 몸통 길이가 TORSO_PX가 되게 한 장 전체에 같게 (조각끼리 크기 비율을 지킨다)
  - 관절 점(pivot)·길이(length): 머리는 아래 가운데(목)에서 위로, 몸통은 위 가운데(목)에서 아래(사타구니)로,
    팔다리는 위 끝에서 둥근 관절만큼 내려온 점에서 아래 관절까지
실행: python3 tools/prepare_character_rig.py [--debug] [id ...]
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_character_sprites import (background_mask, border_color, components, despill,  # noqa: E402
                                       edge_unmix, is_key_color)

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "output/imagegen/characters/rig"
DST = ROOT / "assets/characters/rig"
COLS, ROWS = 6, 2
PARTS = ["head", "torso", "upper_arm", "forearm", "thigh", "shin"]
TORSO_PX = 44.0      ## 조각판에서 몸통(목~사타구니) 길이 — 게임 화면 몸통(약 10px)의 4배쯤
PAD = 2


def key_out(rgb: np.ndarray) -> np.ndarray:
    bgm = background_mask(rgb)
    bg = border_color(rgb)
    if is_key_color(bg):
        bgm |= np.sqrt(((rgb - bg) ** 2).sum(axis=2)) < 90
        color, alpha = edge_unmix(rgb, bgm, bg)
        return np.dstack([despill(color), alpha]).astype(np.uint8)
    return np.dstack([rgb, np.where(bgm, 0, 255)]).astype(np.uint8)


def cut(rgba: np.ndarray):
    """칸 하나에서 가장 큰 덩어리(와 그에 붙은 큰 조각)만 남겨 꼭 맞게 자른다"""
    alpha = rgba[:, :, 3] > 0
    comps = components(alpha)
    if not comps:
        return None
    keep = np.zeros_like(alpha)
    for pts in comps:
        if len(pts) < len(comps[0]) * 0.05:
            break
        ys, xs = zip(*pts)
        keep[list(ys), list(xs)] = True
    rgba = rgba.copy()
    rgba[~keep, 3] = 0
    ys, xs = np.nonzero(keep)
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def joints(name: str, img: np.ndarray) -> tuple[list, float]:
    """조각 그림(잘린 것) 안 관절 점과 관절 사이 길이 (그림 px)"""
    h, w = img.shape[:2]
    a = img[:, :, 3] > 64
    # 위쪽 40% 줄들의 폭 가운데값 = 팔다리 굵기 (발·손처럼 끝이 넓어지는 것에 휘둘리지 않게)
    rows = [np.nonzero(a[y])[0] for y in range(int(h * 0.4))]
    widths = [r[-1] - r[0] + 1 for r in rows if r.size]
    thick = float(np.median(widths)) if widths else float(w)
    top_rows = [r for r in rows[:max(3, int(h * 0.15))] if r.size]
    cx = float(np.median([(r[0] + r[-1]) / 2 for r in top_rows])) if top_rows else w / 2
    if name == "head":
        bottom = [np.nonzero(a[y])[0] for y in range(int(h * 0.8), h)]
        bottom = [r for r in bottom if r.size]
        bx = float(np.median([(r[0] + r[-1]) / 2 for r in bottom])) if bottom else w / 2
        return [bx, float(h)], float(h)
    if name == "torso":
        return [cx, 0.0], float(h)
    top = thick * 0.3
    if name == "shin":
        end = h - thick * 0.9          # 발목: 발 높이만큼 위
    elif name == "forearm":
        end = h - thick * 1.1          # 손목: 손 길이만큼 위
    else:
        end = h - thick * 0.3
    return [cx, top], max(end - top, 1.0)


def process(src: Path, cid: str, debug: bool) -> None:
    rgb = np.array(Image.open(src).convert("RGB")).astype(np.int32)
    rgba = key_out(rgb)
    h, w = rgba.shape[:2]
    cw, ch = w // COLS, h // ROWS
    cut_parts = {}
    for r in range(ROWS):
        for c, name in enumerate(PARTS):
            cut_parts[(r, name)] = cut(rgba[r * ch:(r + 1) * ch, c * cw:(c + 1) * cw])
    torso = cut_parts[(0, "torso")]
    scale = TORSO_PX / torso.shape[0]
    # 한 줄씩 왼쪽부터 늘어놓는다 (행 = 앞·뒤)
    placed = {}
    x = PAD
    row_h = [0, 0]
    images = {}
    for (r, name), img in cut_parts.items():
        if img is None:
            continue
        im = Image.fromarray(img).convert("RGBa")
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS).convert("RGBA")
        images[(r, name)] = im
        row_h[r] = max(row_h[r], im.height)
    atlas_w = max(sum(images[(r, n)].width + PAD for n in PARTS if (r, n) in images) for r in range(ROWS)) + PAD
    atlas = Image.new("RGBA", (atlas_w, row_h[0] + row_h[1] + PAD * 3), (0, 0, 0, 0))
    meta = {"rows": ["front", "back"], "torso_px": TORSO_PX, "parts": {}}
    for r in range(ROWS):
        x = PAD
        y = PAD + (row_h[0] + PAD if r == 1 else 0)
        for name in PARTS:
            im = images.get((r, name))
            if im is None:
                continue
            atlas.paste(im, (x, y))
            pivot, length = joints(name, np.array(im))
            meta["parts"].setdefault(name, [None, None])[r] = {
                "rect": [x, y, im.width, im.height], "pivot": pivot, "length": length}
            x += im.width + PAD
    DST.mkdir(parents=True, exist_ok=True)
    atlas.save(DST / f"{cid}.png")
    (DST / f"{cid}.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    if debug:
        dbg = Image.new("RGBA", atlas.size, (110, 150, 110, 255))
        dbg.alpha_composite(atlas)
        dbg.resize((atlas.width * 3, atlas.height * 3), Image.NEAREST).save(ROOT / ".screenshots" / f"rig_parts_{cid}.png")
    print(f"{cid}: 조각 {len(images)}개, 배율 {scale:.3f}")


def main() -> None:
    debug = "--debug" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    for src in sorted(SRC.glob("[0-9][0-9]_*_rig.png")):
        cid = src.stem[3:-4]
        if not only or cid in only:
            process(src, cid, debug)


if __name__ == "__main__":
    main()
