#!/usr/bin/env python3
"""모션 편집기의 "게임 그림" 탭이 읽는 목록을 만든다 → tools/motion_game_index.js

브라우저는 파일로 연 페이지(file://)에서 .json을 못 읽어서, assets/characters/*_dir8.json과
인물 데이터(data/npc/*.tres의 이름·키 배율·걷기·달리기 속도)를 스크립트 한 장에 담는다.
그림(*_dir8.png)은 편집기가 ../assets/characters/에서 바로 읽는다.
실행: python3 tools/gen_motion_index.py (prepare_character_sprites.py 끝에서도 부른다)
"""
import json
import re
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHARS = ROOT / "assets/characters"
NPC = ROOT / "data/npc"
OUT = ROOT / "tools/motion_game_index.js"
PLAYER = {"name": "주인공", "scale": 1.0, "walk": 110.0, "run": 190.0}   # scripts/actors/player.gd WALK_SPEED·RUN_SPEED


def _npc(path):
    text = path.read_text(encoding="utf-8")

    def val(key, default=None):
        m = re.search(rf"^{key} = (.+)$", text, re.M)
        return m[1].strip() if m else default

    cid = re.sub(r'^&"|"$', "", val("id", '""')).lower()
    st = int(val("stat_speed", 0))   # scripts/actors/npc_type.gd 게터와 같은 계산
    lo = 35.0 + st * 3.0 if st > 0 else float(val("walk_speed_min", 50))
    hi = 57.0 + st * 3.0 if st > 0 else float(val("walk_speed_max", 72))
    run = 110.0 + st * 12.0 if st > 0 else float(val("run_speed", 170))
    return cid, {"name": json.loads(val("display_name", '""')) or cid, "scale": float(val("body_scale", 1.0)),
                 "walk": (lo + hi) / 2 * float(val("walk_scale", 1.0)), "run": run}


def write_index():
    npcs = dict(_npc(p) for p in sorted(NPC.glob("*.tres")))
    chars = []
    for meta in sorted(CHARS.glob("*_dir8.json")):
        cid = meta.stem[: -len("_dir8")]
        if not (CHARS / f"{cid}_dir8.png").exists():
            continue
        info = PLAYER if cid == "player" else npcs.get(cid, {"name": cid, "scale": 1.0, "walk": 50.0, "run": 150.0})
        chars.append(dict(info, id=cid, meta=json.loads(meta.read_text(encoding="utf-8"))))
    chars.sort(key=lambda c: (c["id"] != "player", c["name"]))
    data = {"version": int(time.time()), "chars": chars}
    OUT.write_text("// tools/gen_motion_index.py가 만든다 — 손으로 고치지 않는다\nwindow.GAME_DIR8 = "
                   + json.dumps(data, ensure_ascii=False, indent=1) + ";\n", encoding="utf-8")
    print(f"모션 편집기 게임 그림 목록: {len(chars)}종 → {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    write_index()
