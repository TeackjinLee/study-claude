class_name SaveGame
extends RefCounted
## 세이브 데이터. 은신처에서 슬롯(1~3)을 골라 저장하고, 장이 열릴 때 자동 저장 칸에도 저장한다.
## 게임을 켤 때 칸을 골라 불러온다 (docs/05 §8).
## 노드 없는 순수 데이터 — 무엇을 모으고 어떻게 되돌릴지는 main이 정한다.

const VERSION := 1
const SLOTS := 3
const AUTO_SLOT := 99                      ## 장이 열릴 때 쓰는 자동 저장 칸 (<prefix>auto.json)
const DEFAULT_PREFIX := "user://save_"     ## 슬롯 n은 <prefix>n.json

var money := 0
var respect := {}            ## gang id(String) → 존경도
var completed: Array[String] = []
var weapons := {}            ## 무기 .tres 경로 → 남은 탄
var saved_at := ""           ## 저장한 시각 (슬롯 목록에 보여 준다)
var chapter := 1
var finished := false        ## 엔딩을 봤다
var hideout := ""            ## 이 은신처에서 저장했다 (불러오면 여기서 시작)
var hideouts: Array[String] = []   ## 산 은신처 id
var jobs := {}               ## 부업 id → 한 교대에 끝낸 가장 많은 단계
var job_bonuses: Array[String] = []
var packages: Array[int] = []      ## 주운 비밀 패키지 번호
var rampages: Array[String] = []   ## 끝낸 광란 모드 id


static func slot_path(prefix: String, slot: int) -> String:
	if slot == AUTO_SLOT:
		return "%sauto.json" % prefix
	return "%s%d.json" % [prefix, slot]


## 슬롯 목록 한 줄: "2장 · ₩ 00340000 · 미션 4/60 · 2026-10-11 18:20"
func summary(mission_total: int) -> String:
	var when := saved_at.substr(0, 16).replace("T", " ")
	return "%s · %s · 미션 %d/%d%s" % ["엔딩" if finished else "%d장" % chapter, Hud.money_text(money),
		completed.size(), mission_total, " · " + when if when != "" else ""]


func to_dict() -> Dictionary:
	return {"version": VERSION, "money": money, "respect": respect, "completed": completed, "weapons": weapons,
		"saved_at": saved_at, "chapter": chapter, "finished": finished, "hideout": hideout, "hideouts": hideouts,
		"jobs": jobs, "job_bonuses": job_bonuses, "packages": packages, "rampages": rampages}


static func from_dict(d: Dictionary) -> SaveGame:
	var s := SaveGame.new()
	s.money = int(d.get("money", 0))
	for k: String in d.get("respect", {}):
		s.respect[k] = int(d.respect[k])
	for id in d.get("completed", []):
		s.completed.append(str(id))
	for k: String in d.get("weapons", {}):
		s.weapons[k] = int(d.weapons[k])
	s.saved_at = str(d.get("saved_at", ""))
	# M6에서 더한 칸 — M5 세이브에는 없으니 기본값 (1장, 강남 오피스텔)
	s.chapter = clampi(int(d.get("chapter", 1)), 1, CityMap.LAST_CHAPTER)
	s.finished = bool(d.get("finished", false))
	s.hideout = str(d.get("hideout", ""))
	for id in d.get("hideouts", []):
		s.hideouts.append(str(id))
	for k: String in d.get("jobs", {}):
		s.jobs[k] = int(d.jobs[k])
	for id in d.get("job_bonuses", []):
		s.job_bonuses.append(str(id))
	for i in d.get("packages", []):
		s.packages.append(int(i))
	for id in d.get("rampages", []):
		s.rampages.append(str(id))
	return s


func write(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return true


## 없거나 깨진 파일이면 null
static func read(path: String) -> SaveGame:
	if not FileAccess.file_exists(path):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or int(data.get("version", 0)) != VERSION:
		return null
	return from_dict(data)
