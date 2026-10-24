#!/usr/bin/env python3
"""코덱스가 그린 대기 동작(서 있는 동안 되풀이 — 상인 손뼉 호객·뮤지션 기타·DJ 춤) → 영상 동작 시트 형식(<NN>_<id>_idle_dir8.png + .json)

받은 그림: reference/<id>_motion/<NN>_<id>_idle<N>_right.png (N열 × 5행 ↓ ↘ → ↗ ↑, 칸 160×240 — 걷기 12장과 같은 꼴, 참고 동작 없음).
칸마다 배경을 지우고(unmix_key) 옆 칸 조각을 버린다. 줄마다 발 기준점 하나: 발(덩어리 아래 6% 띠) 가운데의 줄 가운데값을 칸 가운데로,
장마다 덩어리 아래를 같은 바닥 높이로 — 제자리 동작이라 발이 미끄러지지 않게(DJ 옆 스텝은 줄 안에서 그대로 남는다). 키는 1번 칸(똑바로 선 기본 자세).
그 다음 `python3 tools/prepare_character_sprites.py <id> --attacks-only`가 assets/characters/<id>_idle_dir8.png를 낸다 (크기·옷 색은 걷기 서 있기에 맞춘다).

  python3 tools/idle_pose_sheet.py 04_merchant --duration=1.2 [--debug]
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from ko_pose_sheet import CHARS, _bbox, _cells  # noqa: E402

DIRS = ["s", "se", "e", "ne", "n"]
FOOT_BAND = 0.06   ## 덩어리 아래 이만큼(키 비율)을 발로 본다
FLOOR = 0.93       ## 칸 높이에서 바닥(발바닥) 자리


def main() -> None:
    stem = sys.argv[1]
    cid = stem[3:]
    dur = float(next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--duration=")), "1.2"))
    srcs = sorted((CHARS / f"reference/{cid}_motion").glob(f"{stem}_idle*_right.png"))
    if not srcs:
        sys.exit(f"{stem}_idle<N>_right.png 없음")
    src = srcs[-1]
    n = int(re.search(r"_idle(\d+)_right", src.stem).group(1))
    got = _cells(src, n, len(DIRS))
    W = max(c.shape[1] for row in got for c in row)
    H = max(c.shape[0] for row in got for c in row)
    fy = round(H * FLOOR)
    out = np.zeros((H * len(DIRS), W * n, 4), np.uint8)
    rows = []
    for r, d in enumerate(DIRS):
        boxes = [_bbox(c[:, :, 3]) for c in got[r]]
        feet = []
        for c, b in zip(got[r], boxes):
            if not b:
                continue
            band = c[max(b[1], round(b[3] - (b[3] - b[1]) * FOOT_BAND)):b[3], :, 3] > 40
            xs = np.nonzero(band.any(0))[0]
            feet.append((xs.min() + xs.max() + 1) / 2)
        fx = float(np.median(feet))
        for i, (c, b) in enumerate(zip(got[r], boxes)):
            if not b:
                continue
            dx = round(W / 2 - fx)
            dy = fy - b[3]
            cell = Image.new("RGBA", (W, H))
            cell.alpha_composite(Image.fromarray(c), (max(0, dx), max(0, dy)), (max(0, -dx), max(0, -dy)))
            out[r * H:(r + 1) * H, i * W:(i + 1) * W] = np.array(cell)
        h0 = boxes[0][3] - boxes[0][1]
        rows.append({"dir": d, "foot": [W // 2, fy], "stance_h": int(h0)})
        print(f"  {d}: 키 {h0}, 발 가운데 {fx:.1f} (장마다 ±{np.ptp(feet) / 2:.1f})")
    dst = CHARS / f"{stem}_idle_dir8.png"
    Image.fromarray(out).save(dst)
    meta = {"source": f"{src.relative_to(CHARS)} (코덱스 대기 동작)", "kind": "idle", "cell": [W, H], "rows": rows,
            "attacks": [{"name": "idle", "col": 0, "frames": n, "hit_frame": 0, "duration": dur, "loop": True}]}
    dst.with_suffix(".json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    if "--debug" in sys.argv:
        dbg = Image.new("RGBA", (out.shape[1], out.shape[0]), (110, 110, 110, 255))
        dbg.alpha_composite(Image.fromarray(out))
        dbg.save(CHARS.parent.parent.parent / ".screenshots" / f"idle_pose_{cid}.png")
    print(f"{dst.name}: {n}장 × {len(DIRS)}줄, {dur}초 되풀이")


if __name__ == "__main__":
    main()
