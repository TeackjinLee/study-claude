class_name BuildingSkin
extends RefCounted
## 건물 종류 하나의 벽면 그림 (정면도 텍스처). tools/prepare_building_textures.py가 낸
## assets/buildings/facade/<id>.png · <id>_lights.png · <id>.json을 읽는다. 없으면 코드 그림 그대로다.
## 벽은 층마다(1층 띠 · 윗층 띠) 창 칸마다 그림 한 칸씩 붙이고, 난간 띠는 옥상 위에 세우고, 옥상은 옥상 그림을 편다.
## 이 투영은 아핀이라 직사각형 그림이 벽 평행사변형에 왜곡 없이 붙는다.

const DIR := "res://assets/buildings/facade/"

## 낮 그림 · 밤 불빛 (알파 = 불빛 세기)
var day: Texture2D
var lights: Texture2D
var bay_world := 34.0          ## 그림 한 칸이 맡는 창 간격 (월드 px)
var parapet := 0.5             ## 난간 높이 (층 높이 배수)
## 칸 배치: {"front"/"side": {"bays": n, "parapet"/"upper"/"ground": UV Rect2}}, "roof": UV Rect2
var blocks := {}
var roof := Rect2()

static var _cache := {}
## false면 그림을 쓰지 않고 코드 그림으로 (가이드 도구가 코드 모형을 찍을 때)
static var enabled := true


## 그 종류의 그림 (없으면 null)
static func of(t: BuildingType) -> BuildingSkin:
	if t == null or not enabled:
		return null
	var key := String(t.id).to_lower()
	if _cache.has(key):
		return _cache[key]
	var skin: BuildingSkin = null
	var path := DIR + key + ".json"
	if FileAccess.file_exists(path) and has_png(DIR + key + ".png"):
		skin = BuildingSkin.new()
		skin._load(key, JSON.parse_string(FileAccess.get_file_as_string(path)))
	_cache[key] = skin
	return skin


func _load(key: String, info: Dictionary) -> void:
	day = texture(DIR + key + ".png")
	lights = texture(DIR + key + "_lights.png")
	bay_world = info.get("bay_world", bay_world)
	parapet = info.get("parapet", parapet)
	var size := Vector2(info["size"][0], info["size"][1])
	for b in ["front", "side"]:
		var d: Dictionary = info[b]
		blocks[b] = {"bays": int(d["bays"])}
		for band in ["parapet", "upper", "ground"]:
			blocks[b][band] = _uv(d[band], size)
	roof = _uv(info["roof"], size)


## 그림 파일이 있는가 (가져오기 전 새 그림도 — 다듬기 도구로 막 넣은 그림은 .import가 아직 없다)
static func has_png(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


## 밉맵 붙인 그림 (없으면 null). 가져오기 전이면 PNG를 바로 읽는다
static func texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return _mipmapped(load(path))
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## 크게 그린 그림을 줄여 그리므로 밉맵을 만든다 (가져오기 설정은 저장소에 남지 않는다 — *.import는 git 밖)
static func _mipmapped(tex: Texture2D) -> Texture2D:
	var img := tex.get_image() if tex else null
	if img == null or img.is_empty():
		return tex
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _uv(r: Array, size: Vector2) -> Rect2:
	return Rect2(Vector2(r[0], r[1]) / size, Vector2(r[2], r[3]) / size)
