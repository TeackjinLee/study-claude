#!/usr/bin/env python3
"""타이틀 화면 이미지(output/imagegen/title_screen/parts)를 게임에 쓸 수 있게 다듬는다.
검은 배경 PNG를 투명하게 바꾸고(배경과 이어진 어두운 곳만 — 인물의 검은 옷처럼 안쪽에 갇힌 검정은 그대로, 네온 번짐은 반투명으로 부드럽게),
내용만 오려 assets/title/에 넣는다. 사용: python3 tools/prepare_title_assets.py
"""
import json
import sys
import numpy as np
from pathlib import Path
from PIL import Image, ImageDraw

SRC = Path("output/imagegen/title_screen/parts")
# 차 경광등 위치: [왼쪽 등, 오른쪽 등] (원본 1200×896 그림 좌표)
BARS = {"veh_police_front.png": [(421, 192), (624, 192)], "veh_police_rear.png": [(545, 226), (708, 226)],
	"veh_swat.png": [(498, 207), (668, 207)]}
OUT = Path("assets/title")


def key_black(im: Image.Image, flood=60, lo=4, hi=48) -> Image.Image:
    a = np.asarray(im.convert("RGB")).astype(np.float32)
    mx = a.max(axis=2)
    mask = Image.fromarray(((mx < flood) * 255).astype(np.uint8)).copy()   # copy: fromarray는 읽기 전용이라 floodfill이 아무것도 안 한다
    w, h = mask.size
    px = mask.load()
    seeds = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    for p in seeds:
        if px[p] == 255:
            ImageDraw.floodfill(mask, p, 128)
    bg = np.asarray(mask) == 128
    ramp = np.clip((mx - lo) / (hi - lo), 0.0, 1.0)
    alpha = np.where(bg, ramp * ramp * (3 - 2 * ramp), 1.0)
    rgb = np.where(alpha[..., None] > 0.02, np.clip(a / np.maximum(alpha[..., None], 0.02), 0, 255), 0)
    out = np.dstack([rgb, alpha * 255]).astype(np.uint8)
    return Image.fromarray(out)


def content_box(im: Image.Image, pad=4, min_run=6):
    """잡티(작은 점)를 무시한 내용 범위: 불투명한 점이 min_run개 넘는 행·열만 센다"""
    solid = np.asarray(im)[..., 3] > 128
    cols = np.where(solid.sum(axis=0) >= min_run)[0]
    rows = np.where(solid.sum(axis=1) >= min_run)[0]
    return (max(int(cols.min()) - pad, 0), max(int(rows.min()) - pad, 0),
            min(int(cols.max()) + pad + 1, im.width), min(int(rows.max()) + pad + 1, im.height))


def crop_content(im: Image.Image, pad=4) -> Image.Image:
    return im.crop(content_box(im, pad))


def save(im: Image.Image, name: str, max_w=0) -> None:
    """max_w > 0이면 그 폭까지 줄여 저장한다 — 게임에서 쓰는 크기에 가깝게 미리 줄여 두면 축소해도 자글거리지 않는다"""
    OUT.mkdir(parents=True, exist_ok=True)
    if max_w > 0 and im.width > max_w:
        im = im.resize((max_w, round(im.height * max_w / im.width)), Image.LANCZOS)
    im.save(OUT / name, optimize=True)
    print("  %-22s %dx%d" % (name, im.width, im.height))


def main() -> int:
    if not SRC.exists():
        print("없음:", SRC)
        return 1
    print("타이틀 이미지 → assets/title/")
    # 배경은 그대로 (불투명)
    bg = Image.open(SRC / "02_bg_neon_street.png").convert("RGB")
    OUT.mkdir(parents=True, exist_ok=True)
    bg.save(OUT / "bg_street.webp", quality=93)
    print("  %-22s %dx%d" % ("bg_street.webp", bg.width, bg.height))
    lights = {}
    for src, dst in [("03_char_protagonist.png", "char_hero.png"), ("04_char_boss.png", "char_boss.png"),
			("05_char_police.png", "char_police.png"), ("06_veh_striker.png", "veh_striker.png"),
			("07_veh_police_front.png", "veh_police_front.png"), ("08_veh_police_rear.png", "veh_police_rear.png"),
			("09_veh_swat_van.png", "veh_swat.png")]:
        keyed = key_black(Image.open(SRC / src))
        box = content_box(keyed, 4)
        save(keyed.crop(box), dst, 600 if dst.startswith("char_") else 560)
        if dst in BARS:   # 경광등 [왼쪽 끝 중심, 오른쪽 끝 중심] (원본 그림 좌표) → 잘린 그림 안 0~1
            w, h = box[2] - box[0], box[3] - box[1]
            lights[dst[:-4]] = [[round((x - box[0]) / w, 4), round((y - box[1]) / h, 4)] for x, y in BARS[dst]]
    pass
    # 헬기: 기체와 빛기둥을 따로 (빛기둥은 램프 자리를 중심으로 흔든다)
    heli = key_black(Image.open(SRC / "10_veh_police_heli.png"), flood=40)
    box = (400, 130, 890, 392)
    save(heli.crop(box), "heli_body.png", 300)
    beam = Image.open(SRC / "10_veh_police_heli.png").convert("RGB")
    ImageDraw.Draw(beam).rectangle((box[0], box[1], box[2], 351), fill=(0, 0, 0))   # 기체 자리는 지운다
    bx = content_box(key_black(beam, flood=40), 0, 4)
    bbox = (bx[0], 352, bx[2], bx[3])
    save(beam.crop(bbox), "heli_beam.png", 420)   # 불투명 RGB — 빛이라 ADD 합성으로 쓴다
    # 램프(탐조등 자리, 원본 745,350)의 위치를 잘린 그림 안 0~1로 — 빛기둥은 램프를 중심으로 흔든다
    lights["heli_lamp_body"] = [round((745 - box[0]) / (box[2] - box[0]), 4), round((350 - box[1]) / (box[3] - box[1]), 4)]
    lights["heli_lamp_beam"] = [round((745 - bbox[0]) / (bbox[2] - bbox[0]), 4), round((350 - bbox[1]) / (bbox[3] - bbox[1]), 4)]
    (OUT / "lights.json").write_text(json.dumps(lights, indent=1))
    save(crop_content(key_black(Image.open(SRC / "11_ui_title_logo.png"), flood=40)), "logo.png", 760)
    skins = key_black(Image.open(SRC / "12_ui_menu_skins.png"), flood=34)
    save(crop_content(skins.crop((50, 55, 680, 820)), 2), "ui_panel.png")
    for name, box in [("ui_btn_focus.png", (708, 162, 1152, 280)), ("ui_btn_normal.png", (708, 395, 1152, 500)),
			("ui_btn_disabled.png", (708, 595, 1152, 700))]:
        btn = crop_content(skins.crop(box), 2)
        k = 0.58
        save(btn.resize((round(btn.width * k), round(btn.height * k)), Image.LANCZOS), name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
