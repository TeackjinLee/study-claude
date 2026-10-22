class_name Dialogue
extends RefCounted
## 말풍선 대사 (docs/02 §5.3). 대사는 data/dialogue/lines.csv 한 곳에 둔다 — 줄마다 npc,situation,ko,en.
## npc는 NpcType.id, *는 모든 사람 (그 사람 줄이 없으면 * 줄을 쓴다). 번역 칸이 비면 한국어를 쓴다.
## 상황: talk 주인공이 곁에 서 있으면 · flee 겁먹어 도망칠 때 · taxi 택시 부업 손님 ·
## robbed 소매치기당한 사람 · held 강도에게 붙잡힌 사람 · thanks 범인이 잡혔을 때 피해자 ·
## snatch 도둑이 낚아챌 때 · threat 강도가 위협할 때 · escape 범인이 달아날 때 · caught 범인이 잡혔을 때
## 고를 때 rng를 쓰지 않는다(salt로 고른다) — 보행자 rng를 더 뽑으면 다른 결과가 바뀐다.
## (.csv는 Godot가 번역 파일로 가져가므로 lines.csv.import에 importer="keep"을 둔다)

const PATH := "res://data/dialogue/lines.csv"
const ANY := &"*"

static var lang := "ko"           ## 쓸 언어 칸 (ko·en)
static var _table := {}           ## "npc/situation" → [{ko, en, …}]
static var _loaded := false


## 그 사람·상황의 대사 모두 (지금 언어)
static func lines(npc: StringName, situation: StringName) -> PackedStringArray:
	_load()
	var rows: Array = _table.get(_key(npc, situation), _table.get(_key(ANY, situation), []))
	var out := PackedStringArray()
	for r: Dictionary in rows:
		var text: String = r.get(lang, "")
		out.append(text if text != "" else String(r.get("ko", "")))
	return out


## 대사 하나 (없으면 ""). 같은 salt면 같은 줄
static func pick(npc: StringName, situation: StringName, salt: int) -> String:
	var l := lines(npc, situation)
	return "" if l.is_empty() else l[posmod(salt, l.size())]


static func has(npc: StringName, situation: StringName) -> bool:
	return not lines(npc, situation).is_empty()


## 파일을 다시 읽는다 (대사를 고친 뒤 테스트·도구에서)
static func reload() -> void:
	_loaded = false
	_load()


static func _key(npc: StringName, situation: StringName) -> String:
	return "%s/%s" % [npc, situation]


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_table.clear()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("대사 파일을 못 읽는다: " + PATH)
		return
	var head := f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 3 or row[0].strip_edges() == "" or row[0].begins_with("#"):
			continue
		var r := {}
		for i in mini(row.size(), head.size()):
			r[head[i]] = row[i]
		var k := _key(StringName(r.npc), StringName(r.situation))
		if not _table.has(k):
			_table[k] = []
		_table[k].append(r)
