class_name Locale
extends RefCounted
## 화면 글자 번역 (M7 현지화). 글자는 코드에 한국어로 쓰고, 영어는 data/i18n/ui.csv(ko,en) 한 곳에 둔다.
## Locale.t("한국어") → 지금 언어(Settings lang)의 글자, 표에 없으면 한국어 그대로.
## 형식 글자는 형식째 번역한다: Locale.t("비밀 패키지 %d/%d") % [n, total]
## 사람 대사·DJ 자막은 Dialogue가 따로 맡는다 (data/dialogue/lines.csv의 en 칸).
## (.csv는 Godot가 번역 파일로 가져가므로 ui.csv.import에 importer="keep"을 둔다)

const PATH := "res://data/i18n/ui.csv"

static var lang := "ko"
static var _table := {}            ## 한국어 → {en: …}
static var _loaded := false


static func t(ko: String) -> String:
	if lang == "ko":
		return ko
	_load()
	var row: Dictionary = _table.get(ko, {})
	var out: String = row.get(lang, "")
	return out if out != "" else ko


static func has(ko: String) -> bool:
	_load()
	return _table.has(ko)


static func reload() -> void:
	_loaded = false
	_load()


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_table.clear()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var header := f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0] == "" or row[0].begins_with("#"):
			continue
		var d := {}
		for i in mini(header.size(), row.size()):
			d[header[i]] = row[i]
		_table[row[0]] = d
