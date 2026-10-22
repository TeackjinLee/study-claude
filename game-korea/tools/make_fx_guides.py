#!/usr/bin/env python3
"""폭발·불 효과 그림 요청용 가이드 (output/imagegen/fx/GPT_EXPLOSION_PROMPT.md).

칸 배치(4×4·4×2)와 칸마다 바닥 점·크기 원을 그려 생성기에 "이 칸 안에, 이 크기로"를 보여 준다.
선·숫자는 생성기에게 지우라고 한다 (다듬기 도구는 가이드 색을 배경으로 본다).

  python3 tools/make_fx_guides.py

결과: output/imagegen/fx/guides/
  blast_fire_guide.png   E1 불덩이 16장 (검정 배경 — 게임은 더하기 섞기로 그린다)
  blast_smoke_guide.png  E2 폭발 연기 16장 (마젠타 배경)
  flame_loop_guide.png   E3 불난 차 불꽃 되풀이 8장 (검정 배경)
  scorch_guide.png       E4 그을음 바닥 자국 4장 (마젠타 배경, 2:1 타원)
  fx_guides.json         칸 크기·바닥 점·칸마다 원(가운데·반지름)
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "output/imagegen/fx/guides"
CELL = 256
BLACK = (0, 0, 0)
MAGENTA = (255, 0, 255)
LINE_ON_BLACK = (40, 40, 70)       ## 칸 선·원 (검정 위 — 어두운 남색)
LINE_ON_MAGENTA = (150, 0, 150)    ## 칸 선·원 (마젠타 위 — 짙은 자주)


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def fire_frames() -> list:
    """E1 불덩이: 섬광(1~2) → 부풀기(3~4) → 가장 큼(5~8) → 갈라짐(9~12) → 꺼짐(13~16). [가운데 y, 반지름]"""
    out = []
    for i in range(16):
        if i < 4:
            r = lerp(26, 92, i / 3.0)
        elif i < 8:
            r = lerp(96, 104, (i - 4) / 3.0)
        else:
            r = lerp(104, 70, (i - 8) / 7.0)
        cy = lerp(196, 112, min(i / 12.0, 1.0)) if i > 0 else 196
        cy = min(cy, 214 - r * 0.55, 248 - r)   # 아래쪽은 바닥 점 근처까지만, 칸 밖으로 넘지 않게
        cy = max(cy, r + 8)
        out.append([128, round(cy), round(r)])
    return out


def smoke_frames() -> list:
    """E2 연기: 불덩이 뒤에서 피어 위로 오르며 커지고 옅어진다"""
    out = []
    for i in range(16):
        t = i / 15.0
        r = lerp(40, 108, t ** 0.7)
        cy = max(min(lerp(180, 100, t), 248 - r), r + 8)
        out.append([128 + round(10 * t), round(cy), round(r)])
    return out


def grid(path: Path, cols: int, rows: int, bg, line, frames: list, ground_y: int, ellipse: bool = False) -> None:
    img = Image.new("RGB", (cols * CELL, rows * CELL), bg)
    d = ImageDraw.Draw(img)
    for c in range(1, cols):
        d.line([(c * CELL, 0), (c * CELL, rows * CELL)], fill=line, width=2)
    for r in range(1, rows):
        d.line([(0, r * CELL), (cols * CELL, r * CELL)], fill=line, width=2)
    for i, (cx, cy, rad) in enumerate(frames):
        ox, oy = (i % cols) * CELL, (i // cols) * CELL
        if ellipse:   # 바닥 자국: 2:1 타원
            d.ellipse([ox + cx - rad, oy + cy - rad / 2, ox + cx + rad, oy + cy + rad / 2], outline=line, width=2)
        else:
            d.ellipse([ox + cx - rad, oy + cy - rad, ox + cx + rad, oy + cy + rad], outline=line, width=2)
            # 바닥 점(폭발이 일어난 땅) + 땅에 닿은 2:1 타원
            gx, gy = ox + 128, oy + ground_y
            d.line([(gx - 8, gy), (gx + 8, gy)], fill=line, width=2)
            d.line([(gx, gy - 4), (gx, gy + 4)], fill=line, width=2)
        d.text((ox + 8, oy + 6), str(i + 1), fill=line)
    img.save(path)
    print("가이드 저장:", path.relative_to(ROOT), img.size)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    fire, smoke = fire_frames(), smoke_frames()
    flame = [[128, 150, 70] for _ in range(8)]
    scorch = [[128, 128, 110] for _ in range(4)]
    grid(OUT / "blast_fire_guide.png", 4, 4, BLACK, LINE_ON_BLACK, fire, 214)
    grid(OUT / "blast_smoke_guide.png", 4, 4, MAGENTA, LINE_ON_MAGENTA, smoke, 214)
    grid(OUT / "flame_loop_guide.png", 4, 2, BLACK, LINE_ON_BLACK, flame, 214)
    grid(OUT / "scorch_guide.png", 2, 2, MAGENTA, LINE_ON_MAGENTA, scorch, 128, ellipse=True)
    info = {
        "cell": CELL,
        "ground": [128, 214],
        "sheets": {
            "blast_fire": {"grid": [4, 4], "bg": "black", "blend": "add", "frames": fire, "seconds": 0.75},
            "blast_smoke": {"grid": [4, 4], "bg": "magenta", "blend": "mix", "frames": smoke, "seconds": 1.8},
            "flame_loop": {"grid": [4, 2], "bg": "black", "blend": "add", "frames": flame, "loop": True},
            "scorch": {"grid": [2, 2], "bg": "magenta", "blend": "mix", "frames": scorch, "ground_decal": True},
        },
    }
    (OUT / "fx_guides.json").write_text(json.dumps(info, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
