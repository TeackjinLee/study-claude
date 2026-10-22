class_name Settings
extends RefCounted
## 사용자 설정 (user://settings.cfg): 소리 크기(전체·효과음·음악·배경음), 언어(ko·en), 전체 화면, 2.5D 화면.
## 본편·타이틀이 켤 때 load_and_apply()를 부르고, 설정 화면이 값을 바꾸면 apply()·save()한다.

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"master": 0.9, "sfx": 0.9, "music": 0.7, "ambience": 0.7,
	"lang": "ko", "fullscreen": false, "iso": true,
}
const LANGS := ["ko", "en"]

static var values := DEFAULTS.duplicate()
static var path := PATH            ## 테스트는 다른 파일을 쓴다


static func load_and_apply() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		for k: String in DEFAULTS:
			values[k] = cfg.get_value("settings", k, DEFAULTS[k])
	if not LANGS.has(values.lang):
		values.lang = "ko"
	apply()


static func save() -> void:
	if path == PATH and DisplayServer.get_name() == "headless":
		return            # 헤드리스 테스트가 사용자 설정을 덮어쓰지 않게
	var cfg := ConfigFile.new()
	for k: String in values:
		cfg.set_value("settings", k, values[k])
	cfg.save(path)


static func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


static func set_value(key: String, v: Variant) -> void:
	values[key] = v
	apply()


static func apply() -> void:
	AudioSetup.set_volume(&"Master", float(values.master))
	AudioSetup.set_volume(AudioSetup.SFX, float(values.sfx))
	AudioSetup.set_volume(AudioSetup.MUSIC, float(values.music))
	AudioSetup.set_volume(AudioSetup.AMBIENCE, float(values.ambience))
	Dialogue.lang = String(values.lang)
	Locale.lang = String(values.lang)
	IsoView.enabled = bool(values.iso)
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if values.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and not (want == DisplayServer.WINDOW_MODE_WINDOWED \
				and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
			DisplayServer.window_set_mode(want)
