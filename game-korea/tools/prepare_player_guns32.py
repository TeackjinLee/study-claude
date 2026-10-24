#!/usr/bin/env python3
"""승인된 주인공 32방향 사격 시트를 게임 칸으로 변환한다. 기존 보행·총 시트는 건드리지 않는다."""
import json
import math
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output/imagegen/characters/etc/player_shoot360"
DEST = ROOT / "assets/characters"
WEAPONS = {"pistol": "pistol", "smg": "smg", "shotgun": "shotgun", "rifle": "assault_rifle"}


def main():
    preview = Image.new("RGB", (128 * 8, 140 * 16), (43, 48, 56))
    labels = ImageDraw.Draw(preview)
    for wi, (pose, source) in enumerate(WEAPONS.items()):
        prefix = "00_player_" + source
        info = json.loads((SOURCE / (prefix + "_shoot32.json")).read_text())
        aim = Image.open(SOURCE / (prefix + "_aim32.png")).convert("RGBA")
        fire = [Image.open(SOURCE / (prefix + "_fire32_" + side + ".png")).convert("RGBA") for side in "ab"]
        cells = [aim.crop((k % 8 * 320, k // 8 * 320, k % 8 * 320 + 320, k // 8 * 320 + 320)) for k in range(32)]
        boxes = [im.getbbox() for im in cells]
        heights = [304 - b[1] for b in boxes]
        reach = max(max(160 - b[0], b[2] - 160) for b in boxes)
        scale = min(96 / float(np.median(heights)), 100 / max(heights), 60 / reach)
        shift = (round(64 - 160 * scale), round(108 - 304 * scale))
        atlas = Image.new("RGBA", (128 * 7, 112 * 32))
        points = []
        for k, cell in enumerate(cells):
            a = np.asarray(cell)[:, :, 3]
            top = boxes[k][1]
            # 옆·사선은 팔 높이에서 가장 앞으로 나온 총열 끝을 찾는다. 정면·뒷면은 가려져 수동 기준점을 쓴다.
            band = a[max(0, top + 17):min(320, top + 105)] > 100
            yy, xx = np.nonzero(band)
            right = math.sin(k * math.tau / 32) > 0
            edge = int(xx.max() if right else xx.min())
            at_edge = xx >= edge - 2 if right else xx <= edge + 2
            muzzle = [float(edge), float(np.median(yy[at_edge]) + max(0, top + 17))]
            if k in (0, 1, 31):
                muzzle = [160., float(top + (32 if pose == "pistol" else 46 if pose == "smg" else 70))]
                if pose == "shotgun":
                    muzzle = [235., float(top + 43)]
            elif k in (15, 16, 17):
                muzzle = [160., float(top + (40 if pose == "pistol" else 58 if pose in ("smg", "shotgun") else 75))]
            row_points = []
            for col in range(7):
                frame = cell if col == 0 else fire[k // 16].crop(((col - 1) * 320, k % 16 * 320, col * 320, (k % 16 + 1) * 320))
                small = frame.resize((round(320 * scale), round(320 * scale)), Image.Resampling.LANCZOS)
                normalized = Image.new("RGBA", (128, 112))
                normalized.alpha_composite(small, shift)
                b = normalized.getbbox()
                if not b or b[0] == 0 or b[1] == 0 or b[2] == 128 or b[3] == 112:
                    raise ValueError((pose, k, col, "칸 잘림", b))
                atlas.paste(normalized, (col * 128, k * 112))
                amount = 0 if col == 0 else info["fire"]["weights"][col - 1]
                angle = k * math.tau / 32
                weight = 1 if muzzle[1] <= 140 else max(0, (235 - muzzle[1]) / 95)
                dx = -math.sin(angle) * info["fire"]["upper_body_kick_pixels"] * amount * weight
                dy = (math.cos(angle) * info["fire"]["upper_body_kick_pixels"] * .32 - info["fire"]["lift_pixels"]) * amount * weight
                row_points.append([round((muzzle[0] + dx) * scale + shift[0] - 64, 3),
                                   round((muzzle[1] + dy) * scale + shift[1] - 108, 3)])
            points.append(row_points)
            # 총구와 발 기준점을 게임 규격에서 직접 확인하는 보드.
            x, y = k % 8 * 128, (wi * 4 + k // 8) * 140 + 22
            preview.paste(atlas.crop((0, k * 112, 128, (k + 1) * 112)), (x, y), atlas.crop((0, k * 112, 128, (k + 1) * 112)))
            mx, my = x + row_points[0][0] + 64, y + row_points[0][1] + 108
            labels.line((mx - 3, my, mx + 3, my), fill="#ffad61")
            labels.line((mx, my - 3, mx, my + 3), fill="#ffad61")
            labels.text((x + 4, y - 18), f"{pose} {k:02d}", fill="white")
        interval = float(re.search(r"fire_interval = ([\d.]+)", (ROOT / f"data/weapons/{pose}.tres").read_text())[1])
        data = {"pose": pose, "directions": 32, "cell": [128, 112], "foot": [64, 108],
                "aim_col": 0, "fire_col": 1, "fire_frames": 6,
                "fire_duration": min(info["fire"]["duration"], interval), "source_scale": scale,
                "angle_note": info["angle_convention"], "muzzle_note": "총열 윤곽 추정. 정면·뒷면 가림은 수동 기준점.",
                "muzzles": points}
        atlas.save(DEST / f"player_{pose}_dir32.png")
        (DEST / f"player_{pose}_dir32.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
        print(pose, atlas.size, "배율", round(scale, 4), "발사", data["fire_duration"])
    preview.save(SOURCE / "game_muzzles_preview.png")


if __name__ == "__main__":
    main()
