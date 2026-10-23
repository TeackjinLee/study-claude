#!/usr/bin/env python3
"""여러 방향의 인물이 칸마다 같은 시각에 같은 동작(주먹질·소총 조준과 발사)을 하는 영상에서 동작마다 장면을 골라 투명 시트로 낸다.
매니페스트의 kind가 결과 이름이다: attacks(주먹, punch_capture/) · rifle(소총, rifle_capture/) · pistol(권총, pistol_capture/)
· rocket(로켓포, rocket_capture/) · jump(점프, jump_capture/) · ko(넘어짐·기절, ko_capture/) — 총은 remove_flash로 영상의 총구 불꽃을 지운다.

영상(프로젝트 기준 경로 — 지금은 reference/video/punch.mp4)·칸·방향·공격 구간은 매니페스트(.json)에 적는다 (output/imagegen/characters/punch_capture/capture_manifest.json):
  regions: 칸마다 crop [x, y, w, h] · dir (DIR8 이름) · use (같은 방향 칸이 여럿이면 하나만 true)
  regions[].foot_band: 발 기준점을 찾는 맨 아래 띠 높이 (기본 14px — 앞발이 더 낮게 그려진 칸은 늘려 두 발 가운데를 잡는다)
  regions[].erase: 칸 안으로 들어온 옆 인물 조각을 배경색으로 덮을 영상 box 목록 [[x, y, w, h], ...] (칸 사이 선 없이 흩어 선 영상 — 로켓포)
  regions[].rocket: {tip 발사관 입구 앞(탄두 뿌리 — 로켓·앞 불꽃이 나오는 곳) [x, y] · rear 발사관 뒤끝 [x, y] · warhead 탄두 box [x, y, w, h] · fill "erase"(지운다)|"inpaint"(둘레 옷 색으로 메운다 —
     탄두가 몸 앞에 겹치는 정면) · mouth [x, y, r] 빈 발사관 입구 (inpaint일 때)}
     tip·rear는 칸 좌표로 .json rows[].points에 적는다 (게임이 로켓·후폭풍을 그 자리에서 낸다)
  regions[].head: "left"|"right" — 넘어짐(kind ko)에서 다 누운 머리가 칸의 어느 끝인가 (게임이 기절 별을 그 위에 띄운다)
  star: 생성기 워터마크 별(✦)이 있는 영상 box [x, y, w, h] (있으면 메운다) · muzzle: 잴 수 없는 방향(↓·↑)의 총구 자리
  attacks: 공격마다 segments [[처음, 끝, 간격], ...] (영상 장 번호, 1부터, 간격이 음수면 거꾸로 — 왕복 되풀이) · hit (타격 장) · duration (게임에서 한 번 치는 초)
     unload: true면 장마다 탄두를 지운다(로켓이 나간 빈 발사관 — 영상 발사 장면은 폭발 연기에 덮여 조준 장면으로 만든다)
     recoil: 장마다 반동 px(영상 단위) — 발사관 축 뒤로(앞 → 뒤) 밀고 그 1/3만큼 위로
     ground: true면 떠 있는 장(점프)을 발끝이 서 있기 발끝에 닿게 내리고, 내린 만큼(영상 px)을 lift로 적는다 —
     게임이 높이를 직접 올려 그린다(그림자는 땅에 남는다). takeoff·land(영상 장 번호)는 발이 떨어지는 장·닿는 장
결과: output/imagegen/characters/00_<id>_<kind>_dir8.png (줄 = 쓰는 칸의 방향, 열 = 공격 장면을 차례로 이어 붙인 것, 칸 = 가장 큰 crop 크기)
     + 같은 이름 .json (rows · cell · 줄마다 발 기준점 foot [x, y]·서 있기 키 · attacks [{name, frames, hit_frame, duration, src}]).
배경(마젠타·초록)은 prepare_character_sprites.py와 같은 방식(unmix_key — 그림 전체에서 배경색 섞임을 푼다)으로 지운다.
칸 안의 인물은 옮기지 않는다 — 영상이 제자리라 모든 장이 같은 발 기준점을 쓰면 발이 미끄러지지 않는다 (장마다 몸통 가운데에 맞추면 뻗는 팔 쪽으로 몸이 밀려 보인다).
게임 시트(assets/characters/<id>_attacks_dir8.png)는 그 뒤 python3 tools/prepare_character_sprites.py <id> 가 만든다.

  python3 tools/punch_video_sheet.py output/imagegen/characters/punch_capture/capture_manifest.json [--id player] [--preview]
--preview면 매니페스트 옆에 공격마다 미리보기(preview_<공격>.png, 타격 장은 빨간 테두리)와 모션 편집기 작업 파일도 낸다:
  <공격>_regions.png (줄 = 방향, 칸 반 크기) + player_punch_motion_project.json (tools/motion_editor.html "작업 열기"로 연다 —
  동작 jab·straight·uppercut·counter × 방향, ↘·←·↗는 ↙·→·↖ 줄을 뒤집은 것, ↑는 없다)
"""
import argparse
import base64
import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_character_sprites import SRC, _key_background, components  # noqa: E402


def frames_of(attack: dict) -> list:
    """공격 구간 → 쓰는 영상 장 번호 (타격 장은 간격 때문에 빠지지 않게 꼭 넣는다). hit가 없으면 첫 장"""
    out = []
    for lo, hi, step in attack["segments"]:
        out += list(range(lo, hi + (1 if step > 0 else -1), step))
    attack.setdefault("hit", out[0])
    if attack["hit"] not in out:
        out = sorted(out + [attack["hit"]])   # (왕복 구간에는 hit를 따로 주지 않는다 — 첫 장)
    return out


def extract(video: str, numbers: set) -> dict:
    """영상의 장 번호(1부터) → RGB 배열"""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["ffmpeg", "-v", "error", "-i", video, "-vsync", "0", f"{tmp}/%05d.png"], check=True)
        return {n: np.asarray(Image.open(f"{tmp}/{n:05d}.png").convert("RGB")).astype(np.int32) for n in sorted(numbers)}


def key_cell(rgb: np.ndarray, no_flash: bool = False) -> np.ndarray:
    """배경을 지운 RGBA. 인물에서 떨어진 작은 부스러기(압축 얼룩·워터마크·튀는 탄피)는 지운다.
    no_flash면 총구 불꽃(흰·노란 빛)과 그 둘레 번짐도 지운다 — 게임이 총알 궤적과 함께 불꽃을 그린다"""
    rgba = _key_background(rgb, unmix=True)
    if no_flash:
        c = rgb.astype(np.int32)
        hot = (c[:, :, 0] > 215) & (c[:, :, 1] > 195) & (c[:, :, 2] > 150)
        # 불꽃 덩어리(작은 하이라이트가 아니라 큰 빛)와 그 둘레 4px — 둘레는 배경과 섞인 분홍빛 번짐이다
        blobs = [b for b in components(hot) if len(b) >= 30]
        if blobs:
            m = np.zeros(hot.shape, bool)
            for b in blobs:
                ys, xs = zip(*b)
                m[list(ys), list(xs)] = True
            for _ in range(4):
                g = m.copy()
                g[1:] |= m[:-1]
                g[:-1] |= m[1:]
                g[:, 1:] |= m[:, :-1]
                g[:, :-1] |= m[:, 1:]
                m = g
            rgba[m] = 0
    solid = rgba[:, :, 3] > 40
    blobs = sorted(components(solid), key=len, reverse=True)
    if blobs:
        keep = np.zeros_like(solid)
        for b in blobs:
            if len(b) >= max(400, len(blobs[0]) * 0.02):
                ys, xs = zip(*b)
                keep[list(ys), list(xs)] = True
        # 남긴 덩어리 둘레 2px 안의 반투명 가장자리는 그대로 둔다
        grown = keep.copy()
        for _ in range(2):
            g = grown.copy()
            g[1:] |= grown[:-1]
            g[:-1] |= grown[1:]
            g[:, 1:] |= grown[:, :-1]
            g[:, :-1] |= grown[:, 1:]
            grown = g
        rgba[~grown] = 0
    return rgba


def star_alpha(video: dict, box: list) -> np.ndarray:
    """생성기 워터마크 별(✦)의 불투명도 (box [x, y, w, h] 안, 0~1). 별은 화면에 고정된 반투명 흰색이라 배경(마젠타) 위에 겹친 장에서
    초록 값이 배경보다 얼마나 올랐는지로 잰다 — 점마다 배경 위였던 장들의 가운데값. 배경 위였던 장이 없는 점은 0"""
    x, y, w, h = box
    stack = np.stack([f[y:y + h, x:x + w] for f in video.values()]).astype(np.float64)
    bg = (stack[..., 0] > 200) & (stack[..., 2] > 180)        # 배경(마젠타)이나 별이 겹친 배경
    g = np.where(bg, stack[..., 1], np.nan)
    base = np.nanmedian(np.where(bg, stack[..., 1], np.nan).reshape(len(stack), -1), axis=1)  # 장마다 배경 초록 값
    a = (g - base[:, None, None]) / (255.0 - base[:, None, None])
    with np.errstate(all="ignore"):
        out = np.nan_to_num(np.nanmedian(a, axis=0))
    out[out < 0.04] = 0.0
    return np.clip(out, 0.0, 0.9)


def unstar(frame: np.ndarray, box: list, a: np.ndarray) -> np.ndarray:
    """별 걷어 내기: 보이는 색 = 밑색 × (1 − a) + 흰색 × a 를 거꾸로 푼다"""
    x, y, w, h = box
    out = frame.copy()
    c = out[y:y + h, x:x + w].astype(np.float64)
    k = a[:, :, None]
    out[y:y + h, x:x + w] = np.clip((c - 255.0 * k) / (1.0 - k), 0, 255).astype(out.dtype)
    return out


def cut(frame: np.ndarray, crop: list, w: int, h: int, no_flash: bool, erase: list = ()) -> np.ndarray:
    """영상 한 장에서 칸 crop [x, y, cw, ch]을 잘라 배경을 지우고 w×h 투명 칸의 아래 가운데에 놓는다.
    erase(영상 box 목록)는 먼저 배경색(영상 맨 윗줄 가운데값)으로 덮는다 — 칸 안으로 들어온 옆 인물의 발사관·발·머리"""
    x, y, cw, ch = crop
    if erase:
        frame = frame.copy()
        bg = np.median(frame[0], axis=0).astype(frame.dtype)
        for ex, ey, ew, eh in erase:
            frame[max(ey, 0):ey + eh, max(ex, 0):ex + ew] = bg
    out = np.zeros((h, w, 4), np.uint8)
    ox = (w - cw) // 2
    out[h - ch:, ox:ox + cw] = key_cell(frame[y:y + ch, x:x + cw], no_flash)
    return out


def to_cell(p: list, crop: list, w: int, h: int) -> list:
    """영상 좌표 → 칸 좌표 (cut이 crop을 w×h 칸 아래 가운데에 놓는 것과 같게)"""
    return [p[0] - crop[0] + (w - crop[2]) // 2, p[1] - crop[1] + (h - crop[3])]


def unload(cell: np.ndarray, rocket: dict, crop: list, w: int, h: int) -> np.ndarray:
    """로켓이 나간 빈 발사관: 탄두 box 안을 지운다.
    fill "inpaint"면(정면 — 탄두가 손·가슴 앞에 겹쳐 지우면 구멍이 난다) 탄두 색(국방색) 점을 둘레 옷 색으로 메우고(투명도는 둘레에서 번진다),
    mouth [x, y, r](영상 좌표)에 빈 발사관 입구(어두운 테 + 검은 구멍)를 그린다"""
    out = cell.copy()
    x0, y0 = to_cell(rocket["warhead"][:2], crop, w, h)
    bw, bh = rocket["warhead"][2:]
    sl = (slice(max(y0, 0), y0 + bh), slice(max(x0, 0), x0 + bw))
    if rocket.get("fill", "erase") != "inpaint":
        out[sl] = 0
        return out
    box = out[sl].astype(np.float64)
    r, g, b, a = (box[:, :, i] for i in range(4))
    hole = (g >= r - 15) & (g > b + 10) & (a > 0)
    for _ in range(1):   # 탄두 테두리(검은 선)까지
        grown = hole.copy()
        grown[1:] |= hole[:-1]
        grown[:-1] |= hole[1:]
        grown[:, 1:] |= hole[:, :-1]
        grown[:, :-1] |= hole[:, 1:]
        hole = grown
    pre = np.dstack([box[:, :, :3] * (a[..., None] / 255.0), a / 255.0])   # 미리 곱한 색으로 번진다 (투명한 바깥은 투명하게)
    pre[hole] = pre[~hole].mean(axis=0)
    for _ in range(200):
        p = np.pad(pre, ((1, 1), (1, 1), (0, 0)), mode="edge")
        avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4.0
        pre[hole] = avg[hole]
    alpha = np.clip(pre[:, :, 3], 0, 1)
    # 색은 둘레의 짙은 옷(가죽 재킷) 색 하나로 — 번지면 옆 손 살색이 섞여 갈색 얼룩이 된다
    known = ~hole & (a > 200) & (box[:, :, :3].mean(axis=2) < 90)
    jacket = np.median(box[known][:, :3], axis=0) if known.any() else np.array([38.0, 38.0, 40.0])
    rgb = np.broadcast_to(jacket, pre[:, :, :3].shape)
    alpha = np.where(alpha > 0.5, 1.0, alpha * 0.5)   # 번진 가장자리가 흐리게 남지 않게
    fill = np.dstack([np.clip(rgb, 0, 255), alpha * 255.0]).astype(np.uint8)
    box8 = out[sl]
    box8[hole] = fill[hole]
    if "mouth" in rocket:
        mx, my = to_cell(rocket["mouth"][:2], crop, w, h)
        mr = rocket["mouth"][2]
        yy, xx = np.mgrid[0:h, 0:w]
        d = np.hypot((xx - mx) / 1.0, (yy - my) / 0.85)   # 화면 쪽을 보는 입구 — 조금 납작한 타원
        rim = d <= mr
        out[rim] = (52, 56, 46, 255)
        out[d <= mr * 0.62] = (14, 14, 13, 255)
    return out


def shift(cell: np.ndarray, dx: float, dy: float) -> np.ndarray:
    """칸 그림을 (dx, dy)만큼 옮긴다 (정수 px, 밖으로 나간 곳은 버린다)"""
    dx, dy = int(round(dx)), int(round(dy))
    out = np.zeros_like(cell)
    h, w = cell.shape[:2]
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = cell[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


def foot_point(rgba: np.ndarray, band_h: int = 14) -> tuple:
    """발 기준점 (두 발 가운데 x, 발끝 y)과 키. 두 발 높이가 다르면(앞발이 낮다) band_h를 늘려 두 발이 모두 들게 한다"""
    a = rgba[:, :, 3] > 40
    ys = np.nonzero(a.any(1))[0]
    top, bottom = int(ys.min()), int(ys.max())
    band = a[bottom - band_h:bottom + 1]
    xs = np.nonzero(band.any(0))[0]
    return (float(xs.min() + xs.max()) / 2.0, float(bottom)), float(bottom - top)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("manifest")
    ap.add_argument("--id", default="player")
    ap.add_argument("--project", action="store_true", help="모션 편집기 작업 파일도 낸다 (--preview면 늘)")
    ap.add_argument("--preview", action="store_true", help="공격별 미리보기를 매니페스트 옆에 낸다")
    args = ap.parse_args()
    man_path = Path(args.manifest)
    man = json.loads(man_path.read_text())
    regions = [r for r in man["regions"] if r["use"]]
    attacks = [dict(a, src=frames_of(a)) for a in man["attacks"]]
    need = {man.get("stance_frame", 1)} | {n for a in attacks for n in a["src"]}
    path = Path(man["video"])
    video = extract(str(path if path.is_absolute() else SRC.parent.parent.parent / path), need)
    if "star" in man:   # 워터마크 별 box [x, y, w, h] (영상 좌표)
        a = star_alpha(video, man["star"])
        video = {n: unstar(f, man["star"], a) for n, f in video.items()}
        print(f"  워터마크 별 {int((a > 0).sum())}px 걷어 냄 (가장 짙은 곳 {a.max():.2f})")
    # 칸 크기가 다른 영상(권총 — 칸 너비 253~414)은 가장 큰 칸에 맞추고, 작은 칸은 아래 가운데에 놓는다
    w, h = max(r["crop"][2] for r in regions), max(r["crop"][3] for r in regions)
    cols = sum(len(a["src"]) for a in attacks)
    sheet = Image.new("RGBA", (w * cols, h * len(regions)), (0, 0, 0, 0))
    rows_meta = []
    for r, reg in enumerate(regions):
        no_flash = man.get("remove_flash", False)
        erase = reg.get("erase", [])
        foot, stance = foot_point(cut(video[man.get("stance_frame", 1)], reg["crop"], w, h, no_flash, erase), reg.get("foot_band", 14))
        rows_meta.append({"dir": reg["dir"], "slot": reg["slot"], "foot": [round(foot[0], 1), foot[1]], "stance_h": stance})
        if "head" in reg:   # 넘어짐: 누운 머리가 화면 왼쪽·오른쪽 어느 끝인가
            rows_meta[-1]["head"] = reg["head"]
        rocket = reg.get("rocket")
        if rocket:
            rows_meta[-1]["points"] = {k: to_cell(rocket[k], reg["crop"], w, h) for k in ("tip", "rear")}
            axis = np.subtract(rocket["tip"], rocket["rear"]).astype(float)
            axis /= np.linalg.norm(axis)
        c = 0
        for a in attacks:
            for i, n in enumerate(a["src"]):
                cell = cut(video[n], reg["crop"], w, h, no_flash, erase)
                if rocket and a.get("unload"):
                    cell = unload(cell, rocket, reg["crop"], w, h)
                kick = a.get("recoil", [])
                if rocket and i < len(kick) and kick[i]:
                    cell = shift(cell, -axis[0] * kick[i], -axis[1] * kick[i] - kick[i] / 3.0)
                if a.get("ground"):
                    # 이 장이 떠오른 높이 = 서 있기 발끝 − 이 장 맨 아래 (줄 r의 값을 a["lift"][r]에)
                    ys = np.nonzero((cell[:, :, 3] > 40).any(1))[0]
                    up = max(foot[1] - float(ys.max()), 0.0) if ys.size else 0.0
                    if up >= 1.0:
                        cell = shift(cell, 0, up)
                    a.setdefault("lift", [[] for _ in regions])[r].append(round(up, 1))
                sheet.paste(Image.fromarray(cell), (c * w, r * h))
                c += 1
        print(f"  칸 {reg['slot']} → {reg['dir']}: 발 {foot[0]:.0f},{foot[1]:.0f} · 서 있기 키 {stance:.0f}px")
    kind = man.get("kind", "attacks")   ## attacks(주먹 공격) · rifle(소총 조준·발사) · pistol(권총 조준·발사) · rocket(로켓포 조준·발사) · jump(제자리 점프)
    out = SRC / f"00_{args.id}_{kind}_dir8.png"
    sheet.save(out)
    meta = {"video": man["video"], "fps": man["fps"], "kind": kind, "cell": [w, h], "rows": rows_meta, "attacks": [],
            "muzzle": man.get("muzzle", {})}
    col = 0
    for a in attacks:
        meta["attacks"].append({"name": a["name"], "col": col, "frames": len(a["src"]), "hit_frame": a["src"].index(a["hit"]),
                                "duration": a["duration"], "src": a["src"], "loop": a.get("loop", False)})
        if a.get("ground"):
            # 떠오른 높이는 줄마다 (영상 px), 발이 떨어지는·닿는 장은 이 동작 안의 차례로
            meta["attacks"][-1].update(lift=a["lift"], takeoff=a["src"].index(a["takeoff"]), land=a["src"].index(a["land"]))
        print(f"  {a['name']}: {len(a['src'])}장 (영상 {a['src'][0]}~{a['src'][-1]}), 타격 {a['src'].index(a['hit'])}번째 = 영상 {a['hit']}, {a['duration']}초")
        col += len(a["src"])
    out.with_suffix(".json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    print(f"{out.relative_to(SRC.parent.parent.parent)}: {len(regions)}줄 × {cols}장")
    if args.preview:
        # 공격마다 회색 바탕에 줄(방향) × 장, 타격 장은 빨간 테두리
        k = 0.4
        for a in meta["attacks"]:
            pw, ph = int(w * k), int(h * k)
            img = Image.new("RGBA", (pw * a["frames"], ph * len(regions)), (90, 90, 90, 255))
            d = ImageDraw.Draw(img)
            for r in range(len(regions)):
                for i in range(a["frames"]):
                    cell = sheet.crop(((a["col"] + i) * w, r * h, (a["col"] + i + 1) * w, (r + 1) * h)).resize((pw, ph), Image.LANCZOS)
                    img.alpha_composite(cell, (i * pw, r * ph))
                    if i == a["hit_frame"]:
                        d.rectangle((i * pw, r * ph, (i + 1) * pw - 1, (r + 1) * ph - 1), outline=(230, 40, 40, 255), width=2)
                d.text((3, r * ph + 3), regions[r]["dir"], fill=(255, 255, 0, 255))
            img.save(man_path.parent / f"preview_{a['name']}.png")
    if args.preview or args.project:
        write_editor_project(man_path.parent, sheet, meta, args.id, kind)


EDITOR_MIRROR = {"se": "sw", "w": "e", "ne": "nw"}


def write_editor_project(folder: Path, sheet: Image.Image, meta: dict, cid: str, kind: str = "attacks") -> None:
    """모션 편집기 작업 파일 — 공격마다 그림 한 장(줄 = 방향, 반 크기), 동작·방향마다 장면 순서"""
    w, h = meta["cell"]
    rows = [r["dir"] for r in meta["rows"]]
    sheets, clips = [], {}
    for n, a in enumerate(meta["attacks"]):
        part = sheet.crop((a["col"] * w, 0, (a["col"] + a["frames"]) * w, len(rows) * h))
        part = part.resize((part.width // 2, part.height // 2), Image.LANCZOS)
        part.save(folder / f"{a['name']}_regions.png")
        buf = io.BytesIO()
        part.save(buf, "PNG")
        sid = f"s{n + 1}"
        sheets.append({"id": sid, "name": f"{a['name']}_regions.png",
                       "opts": {"cols": a["frames"], "rows": len(rows), "bg": "alpha", "pad": 0, "marker": False},
                       "data": "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()})
        for d in rows + list(EDITOR_MIRROR):
            src = EDITOR_MIRROR.get(d, d)
            if src not in rows:
                continue
            r = rows.index(src)
            clips[f"{a['name']}:{d}"] = {"frames": [{"f": f"{sid}:{r * a['frames'] + i}", "dx": 0, "dy": 0, "flip": False}
                                                    for i in range(a["frames"])],
                                         "flip": d in EDITOR_MIRROR, "cycle": a["duration"]}
    name = f"{cid}_punch" if kind == "attacks" else f"{cid}_{kind}"
    project = {"version": 1, "id": name,
               "out": {"preset": "dir8", "w": 128, "h": 112, "fx": 64, "fy": 108, "body": 93, "align": "feet", "fit": "sheet"},
               "cycle": {"idle": 1.6, "walk": 1, "run": 0.62}, "speed": {"walk": 34, "run": 90}, "clips": clips,
               "cur": {"mode": meta["attacks"][0]["name"], "dir": "e"}, "sheets": sheets}
    (folder / f"{name}_motion_project.json").write_text(json.dumps(project, ensure_ascii=False))
    print(f"  모션 편집기 작업 파일: {folder.name}/{name}_motion_project.json (동작·방향 {len(clips)}개)")


if __name__ == "__main__":
    main()
