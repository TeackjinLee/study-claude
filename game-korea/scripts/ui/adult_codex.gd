extends Control
## 독립 실행 및 UI 자식으로 인스턴스 가능한 성인 도감. 전투 수치는 변경하지 않는다.
const DATA := "res://data/codex/adult_roster.json"
const COLORS := [Color("3abbd9"), Color("dc5869"), Color("4d9eed"), Color("b285e3")]
var grids: Array[GridContainer] = []

class Figure extends Control:
	var npc: NpcType
	func _draw() -> void:
		PersonDrawer.draw_standing(self, 2.2, 0.0, npc.shirt_colors[0], npc.pants_colors[0], npc.hair_colors[0], 1.0, null, npc, 0)

func label(text_value: String, font_size: int, color := Color("e3edf3")) -> Label:
	var item := Label.new()
	item.text = text_value
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	return item

func panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b1925")
	style.border_color = color.darkened(.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("050e18")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side, 22)
	scroll.add_child(margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	margin.add_child(body)
	body.add_child(label("서울 거리  /  인물 도감", 30))
	body.add_child(label("성인 캐릭터 · 체력 / 스피드 / 파워 · 10점 기준", 16, Color("88a6b8")))
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var categories: Array[String] = []
	for row: Dictionary in data:
		if not categories.has(row.category):
			categories.append(row.category)
	for index in categories.size():
		var color: Color = COLORS[index]
		body.add_child(label(categories[index], 22, color))
		var grid := GridContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		body.add_child(grid)
		grids.append(grid)
		for row: Dictionary in data:
			if row.category == categories[index]:
				grid.add_child(card(row,color))
	body.add_child(label("파워는 근접 공격 기준 · 능력치는 설계안입니다", 14, Color("88a6b8")))
	resized.connect(_resize_grid)
	_resize_grid()

func _resize_grid() -> void:
	for grid in grids:
		grid.columns = maxi(1, int((size.x-44)/246.0))

func card(row: Dictionary, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(236, 292)
	panel.add_theme_stylebox_override("panel",panel_style(color))
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(label(row.name,18))
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(208,150)
	stage.clip_contents = true
	box.add_child(stage)
	var npc: NpcType = load(row.npc)
	# 동일 캐릭터의 전신과 확대 얼굴. Control 그림이므로 월드 지면 높이에 영향받지 않는다.
	for portrait in [false,true]:
		var frame := Control.new()
		frame.position = Vector2(94,0) if portrait else Vector2.ZERO
		frame.size = Vector2(114,150) if portrait else Vector2(94,150)
		frame.clip_contents = true
		stage.add_child(frame)
		var transform_node := Node2D.new()
		var zoom := 8.0 if portrait else 4.1
		transform_node.transform = IsoView.BASIS.scaled(Vector2(zoom,zoom))
		transform_node.position = Vector2(53,238) if portrait else Vector2(43,140)
		frame.add_child(transform_node)
		var figure := Figure.new()
		figure.npc = npc
		figure.mouse_filter = Control.MOUSE_FILTER_IGNORE
		transform_node.add_child(figure)
	var keys := ["health","speed","power"]
	var names := ["체력","스피드","파워"]
	var colors := [Color("ed6174"),Color("46cbd4"),Color("efa254")]
	for k in 3:
		var line := HBoxContainer.new()
		box.add_child(line)
		var title := label(names[k],14)
		title.custom_minimum_size.x = 48
		line.add_child(title)
		var bar := ProgressBar.new()
		bar.max_value = 10
		bar.value = row[keys[k]]
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(96,12)
		var fill := StyleBoxFlat.new()
		fill.bg_color = colors[k]
		bar.add_theme_stylebox_override("fill",fill)
		line.add_child(bar)
		line.add_child(label("%d/10" % int(row[keys[k]]),14))
	return panel
