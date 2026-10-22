#!/usr/bin/env python3
"""광란 모드 20개 생성기 → data/rampages/*.tres (docs/05 §7).

줄마다 (id, 블록 x, 블록 y, 인도 모서리(2 = 남동 — 앞모서리라 건물에 안 가린다), 무기, 목표, 조직, 수, 제한 초, 보상).
목표: anyone(아무나) · gang(그 조직 조직원) · cars(차 터뜨리기). 아이콘은 그 블록 인도 고리의 모서리에 선다.
자리를 바꾸면 collect_test가 공중전화·무기 상자·은신처와 겹치지 않는지, 그 장에 열린 구역인지 본다.
실행: python3 tools/gen_rampages.py data/rampages
"""
import os
import sys

TARGET = {"anyone": 0, "gang": 1, "cars": 2}

RAMPAGES = [
    # 1장 강남대로
    ("gangnam_pistol",   1, 0, 2, "pistol",       "anyone", "",         12, 60,  50000),
    ("gangnam_bat",      4, 1, 2, "bat",          "anyone", "",         10, 60,  50000),
    ("gangnam_smg",      2, 5, 2, "smg",          "gang",   "gangnam",  10, 90,  80000),
    ("gangnam_molotov",  5, 4, 2, "molotov",      "cars",   "",          5, 90,  80000),
    ("gangnam_shotgun",  0, 2, 2, "shotgun",      "anyone", "",         18, 90, 100000),
    # 2장 종로 구도심·홍대 거리·한강변
    ("jongno_bat",       2, -8, 2, "bat",         "gang",   "oldtown",  12, 90, 120000),
    ("jongno_smg",       4, -6, 2, "smg",         "anyone", "",         20, 90, 120000),
    ("jongno_grenade",   0, -7, 2, "grenade",     "cars",   "",          6, 90, 150000),
    ("hongdae_pistol",  -2, -6, 2, "pistol",      "anyone", "",         15, 75, 100000),
    ("hongdae_shotgun", -5, -7, 2, "shotgun",     "gang",   "oldtown",  12, 90, 150000),
    ("hongdae_flame",   -1, -7, 2, "flamethrower","anyone", "",         20, 60, 150000),
    ("riverside_rocket", 1, -5, 2, "rocket",      "cars",   "",          8, 90, 180000),
    ("riverside_smg",   -4, -5, 2, "smg",         "anyone", "",         18, 75, 120000),
    # 3장 여의도 섬·변두리 주택가
    ("yeouido_rifle",   -3, -2, 2, "rifle",       "anyone", "",         22, 90, 200000),
    ("yeouido_rocket",  -4, -2, 2, "rocket",      "cars",   "",         10, 120, 250000),
    ("outskirts_bat",   -2, -11, 2, "bat",        "anyone", "",         15, 75, 150000),
    ("outskirts_molotov", 2, -9, 2, "molotov",    "cars",   "",          8, 120, 200000),
    # 4장 외곽 공단
    ("industrial_rifle", -2, 1, 2, "rifle",       "gang",   "smuggler", 15, 120, 300000),
    ("industrial_flame", -5, 3, 2, "flamethrower","gang",   "smuggler", 15, 90, 300000),
    ("industrial_rocket", -3, 4, 2, "rocket",     "cars",   "",         12, 120, 300000),
]


def tres(r):
    rid, bx, by, corner, weapon, target, gang, count, limit, reward = r
    gang_line = f'gang = &"{gang}"\n' if gang else ""
    return f'''[gd_resource type="Resource" script_class="RampageType" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/collect/rampage_type.gd" id="1"]
[ext_resource type="Resource" path="res://data/weapons/{weapon}.tres" id="2"]

[resource]
script = ExtResource("1")
id = &"{rid}"
block = Vector2i({bx}, {by})
corner = {corner}
weapon = ExtResource("2")
target = {TARGET[target]}
{gang_line}count = {count}
time_limit = {float(limit)}
reward = {reward}
'''


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "data/rampages"
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".tres"):
            os.remove(os.path.join(out, f))
    ids = set()
    for r in RAMPAGES:
        assert r[0] not in ids, r[0]
        ids.add(r[0])
        with open(os.path.join(out, r[0] + ".tres"), "w") as f:
            f.write(tres(r))
    # Rampages.ALL 목록
    lines = ",\n".join(f'\tpreload("res://data/rampages/{r[0]}.tres")' for r in RAMPAGES)
    with open("scripts/collect/rampage_list.gd", "w") as f:
        f.write("class_name RampageList\nextends RefCounted\n## tools/gen_rampages.py가 만든다 — 손으로 고치지 않는다\n\n"
                f"const ALL: Array[RampageType] = [\n{lines},\n]\n")
    print(f"광란 모드 {len(RAMPAGES)}개 → {out}")


if __name__ == "__main__":
    main()
