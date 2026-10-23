#!/usr/bin/env python3
"""포즈 옮기기로 받은 넘어짐 그림 → 영상 동작 시트 형식(00_<id>_ko_dir8.png + .json, tools/punch_video_sheet.py와 같은 꼴)

주인공 넘어짐 영상 시트(00_player_ko_dir8.png)에서 10장을 골라 동작 참고(reference/ko_motion/fall10_motion_ref_a·b.png,
5열 × 6행, 줄은 영상 시트 줄 순서)를 만들고, 코덱스가 인물만 바꿔 그린 두 장(<NN>_<id>_fall10_a·b.png)을 받는다.
칸마다 배경을 지우고(unmix_key), 줄마다 한 배율로 주인공 참고 칸 크기에 맞춘 뒤 덩어리 아래 가운데를 참고 칸의 그 자리에 둔다 —
생성 그림은 칸 안 자리가 조금씩 흔들려, 그대로 쓰면 쓰러지는 동안 몸이 미끄러진다. 발 기준점·키·누운 머리 쪽은 주인공 줄 그대로.
그 다음 `python3 tools/prepare_character_sprites.py <id> --attacks-only`가 assets/characters/<id>_ko_dir8.png를 낸다.

  python3 tools/ko_pose_sheet.py 01_civ_f [--debug]
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from prepare_character_sprites import _key_background  # noqa: E402

CHARS = Path(__file__).resolve().parent.parent / "output/imagegen/characters"
REF = CHARS / "00_player_ko_dir8.png"
PICK = [0, 3, 6, 9, 12, 15, 18, 21, 23, 32]   ## 참고에 쓴 주인공 장 (fall 24장 중 9장 + 숨쉬기 1장) — 참고 그림과 같아야 한다
COLS, ROWS = 5, 6
FALL_N = 9          ## 앞 9장 = 쓰러짐, 9·10장 = 누워 숨쉬기 (9장째를 두 동작이 함께 쓴다)
FALL_TIME = 1.2
OUT_TIME = 1.6


def _bbox(a: np.ndarray):
    ys, xs = np.nonzero(a > 40)
    if not xs.size:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def _main_blobs(rgba: np.ndarray) -> np.ndarray:
    """옆 칸에서 넘어온 조각·얼룩을 버린다: 가장 큰 덩어리의 4% 넘는 덩어리만"""
    from collections import deque
    m = rgba[:, :, 3] > 40
    h, w = m.shape
    lab = np.zeros((h, w), np.int32)
    sizes = []
    for y0, x0 in zip(*np.nonzero(m)):
        if lab[y0, x0]:
            continue
        sizes.append(0)
        n = len(sizes)
        lab[y0, x0] = n
        q = deque([(y0, x0)])
        while q:
            y, x = q.popleft()
            sizes[-1] += 1
            for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= yy < h and 0 <= xx < w and m[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n
                    q.append((yy, xx))
    if len(sizes) <= 1:
        return rgba
    # 몸(가장 큰 덩어리) 둘레의 것만 — 떨어뜨린 가방은 남기고, 칸 테두리에 닿은 옆 칸 조각은 버린다
    big = int(np.argmax(sizes)) + 1
    by, bx = np.nonzero(lab == big)
    pad = 0.08 * max(h, w)
    ok = [big]
    for i, n in enumerate(sizes):
        if i + 1 == big or n < max(sizes) * 0.02:
            continue
        ys, xs = np.nonzero(lab == i + 1)
        edge = ys.min() == 0 or xs.min() == 0 or ys.max() == h - 1 or xs.max() == w - 1
        near = xs.max() >= bx.min() - pad and xs.min() <= bx.max() + pad and ys.max() >= by.min() - pad and ys.min() <= by.max() + pad
        if near and not edge:
            ok.append(i + 1)
    keep = np.isin(lab, ok)
    for _ in range(2):   # 반투명 가장자리까지
        g = keep.copy()
        g[1:] |= keep[:-1]
        g[:-1] |= keep[1:]
        g[:, 1:] |= keep[:, :-1]
        g[:, :-1] |= keep[:, 1:]
        keep = g
    out = rgba.copy()
    out[:, :, 3] = np.where(keep, out[:, :, 3], 0)
    return out


def _cells(path: Path) -> list:
    rgb = np.array(Image.open(path).convert("RGB")).astype(np.int32)
    rgba = _key_background(rgb, unmix=True)
    h, w = rgba.shape[:2]
    cw, ch = w / COLS, h / ROWS
    return [[_main_blobs(rgba[round(r * ch):round((r + 1) * ch), round(c * cw):round((c + 1) * cw)]) for c in range(COLS)]
            for r in range(ROWS)]


def main() -> None:
    stem = sys.argv[1]
    info = json.loads(REF.with_suffix(".json").read_text())
    W, H = info["cell"]
    ref = np.array(Image.open(REF).convert("RGBA"))
    got = [a + b for a, b in zip(_cells(CHARS / f"reference/ko_motion/{stem}_fall10_a.png"),
                                 _cells(CHARS / f"reference/ko_motion/{stem}_fall10_b.png"))]
    cols = PICK[:FALL_N] + PICK[FALL_N - 1:]
    out = np.zeros((H * ROWS, W * len(cols), 4), np.uint8)
    for r in range(ROWS):
        refs = [_bbox(ref[r * H:(r + 1) * H, c * W:(c + 1) * W, 3]) for c in PICK]
        boxes = [_bbox(g[:, :, 3]) for g in got[r]]
        # 줄마다 한 배율: 서 있는 앞 장은 키, 누운 뒷 장은 몸 길이로 잰 비율의 가운데값
        ks = []
        for i, (rb, gb) in enumerate(zip(refs, boxes)):
            if rb and gb:
                ks.append((rb[3] - rb[1]) / (gb[3] - gb[1]) if i < 4 else (rb[2] - rb[0]) / (gb[2] - gb[0]))
        k = float(np.median(ks))
        for j, i in enumerate(list(range(FALL_N)) + list(range(FALL_N - 1, 10))):
            rb, gb = refs[i], boxes[i]
            if not (rb and gb):
                continue
            g = got[r][i][gb[1]:gb[3], gb[0]:gb[2]]
            im = Image.fromarray(g).resize((max(1, round(g.shape[1] * k)), max(1, round(g.shape[0] * k))), Image.LANCZOS)
            # 덩어리 아래 가운데를 주인공 참고 칸의 그 자리에
            x = round((rb[0] + rb[2]) / 2 - im.width / 2)
            y = rb[3] - im.height
            cell = Image.new("RGBA", (W, H))
            cell.alpha_composite(im, (max(0, x), max(0, y)), (max(0, -x), max(0, -y)))
            out[r * H:(r + 1) * H, j * W:(j + 1) * W] = np.array(cell)
        print(f"  {info['rows'][r]['dir']}: 배율 {k:.3f}")
    cid = stem[3:]
    dst = CHARS / f"{stem}_ko_dir8.png"
    Image.fromarray(out).save(dst)
    meta = {"source": f"reference/ko_motion/{stem}_fall10_a·b.png (주인공 넘어짐에서 포즈 옮기기)", "kind": "ko",
            "cell": [W, H], "rows": info["rows"],
            "attacks": [{"name": "fall", "col": 0, "frames": FALL_N, "hit_frame": 0, "duration": FALL_TIME, "loop": False},
                        {"name": "out", "col": FALL_N, "frames": 2, "hit_frame": 0, "duration": OUT_TIME, "loop": True}],
            "muzzle": {}}
    dst.with_suffix(".json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    if "--debug" in sys.argv:
        dbg = Image.new("RGBA", (out.shape[1], out.shape[0]), (110, 110, 110, 255))
        dbg.alpha_composite(Image.fromarray(out))
        dbg.save(CHARS.parent.parent.parent / ".screenshots" / f"ko_pose_{cid}.png")
    print(f"{dst.name}: {len(cols)}장 × {ROWS}줄")


if __name__ == "__main__":
    main()
