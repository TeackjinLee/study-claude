class_name CheckpointVisual
extends Node2D
## 기존 ★4 다리 검문소 수명에 종속되는 초소. 차단은 기존 경찰차가 담당한다.
var spot := Vector2.ZERO
var across := Vector2.RIGHT
var views: Array[BuildingView] = []

func _ready() -> void:
	var at := spot + across * (City.ROAD * 0.5 - 15.0)
	var piece := BuildingModel._box(Rect2(at-Vector2(12,12),Vector2(24,24)),0,35,Color("aeb4af"),&"flat",Color("7f8988"),&"punched",1)
	piece.deco=[&"landmark_sign"]
	piece.text="검문"
	var holder := Node2D.new()
	holder.position=IsoView.lift(CityMap.ground_height(at))
	add_child(holder)
	views=BuildingView.make(holder,null,-1,piece)
	var body := StaticBody2D.new()
	add_child(body)
	City._add_box(body,piece.rect)
	_update_visibility()

func _process(_delta: float) -> void:
	_update_visibility()

func _update_visibility() -> void:
	for view in views:
		view.visible=IsoView.enabled
	queue_redraw()

func _draw() -> void:
	if not IsoView.enabled:
		var at := spot+across*(City.ROAD*0.5-15)
		draw_rect(Rect2(at-Vector2(12,12),Vector2(24,24)),Color("67778e"))
