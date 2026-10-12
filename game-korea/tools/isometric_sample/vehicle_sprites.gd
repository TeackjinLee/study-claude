extends RefCounted
## 앞·뒤 사선 시트와 좌우 반전으로 도로의 네 방향을 표현한다.
const ATLAS: Texture2D = preload("res://assets/vehicles/reference_v1/lineup.png")
const REAR: Texture2D = preload("res://assets/vehicles/reference_v1/lineup_rear.png")
const IDS := ["car_avela","car_sonato","car_sorea","car_striker","car_rumi","car_zenith_g8","car_taxi","car_avela_r","trk_porta","trk_bongo","trk_titan","trk_tanker","trk_garbage","trk_mixer","bus_city","bus_express","bus_village","sp_fire","sp_ambulance","police_patrol","sp_swat","sp_tow","sp_fire_heli","etc_bike","etc_bicycle","etc_camper","etc_truck"]
var regions := {}
var rear_regions := {}

func _init() -> void:
	regions = _regions(ATLAS)
	rear_regions = _regions(REAR)

func _regions(texture: Texture2D) -> Dictionary:
	var result := {}
	var image := texture.get_image()
	var cell := Vector2(image.get_size()) / Vector2(9,3)
	for idx in IDS.size():
		var start := Vector2i(Vector2(idx%9,idx/9)*cell)
		var end := Vector2i(Vector2(idx%9+1,idx/9+1)*cell)
		var region := Rect2i(start,end-start)
		var used := image.get_region(region).get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			result[IDS[idx]] = Rect2(region.position+used.position,used.size)
	return result

func draw(view: Node2D, car: Vehicle) -> bool:
	var key := car.stats.resource_path.get_file().get_basename()
	if not regions.has(key) or car.wrecked:
		return false
	var forward: Vector2 = view.basis.basis_xform(Vector2.UP.rotated(car.motor.heading)).normalized()
	var rear := forward.y < 0.0 and rear_regions.has(key)
	var region: Rect2 = rear_regions[key] if rear else regions[key]
	var extent := maxf(car.stats.size.y,car.stats.size.x)*1.2
	var size := region.size * (extent / region.size.x)
	var foot: Vector2 = view.project(car.global_position)
	# 접지점을 기준으로 배치한다. 회전해도 이미지 자체를 뒤집어 세우지 않는다.
	var destination := Rect2(foot-Vector2(size.x*0.5,size.y*0.72),size)
	# 앞면 원본은 좌하단, 뒷면 원본은 우상단으로 진행하는 방향이다.
	var mirrored := forward.x < 0 if rear else forward.x > 0
	if mirrored:
		destination.position.x += size.x
		destination.size.x = -size.x
	view.draw_texture_rect_region(REAR if rear else ATLAS,destination,region)
	if car.siren:
		var blink := int(Time.get_ticks_msec()/160)%2 == 0
		var lamp := foot-Vector2(0,size.y*0.42)
		view.draw_circle(lamp-Vector2(3,0),2.5,Color("ff4767") if blink else Color("662238"))
		view.draw_circle(lamp+Vector2(3,0),2.5,Color("264277") if blink else Color("5f9fff"))
	if car.controlled:
		# 회전 중의 실제 진행 방향 표식.
		var tip := foot+forward*(extent*0.5+7)
		view.draw_line(tip-forward*6+forward.orthogonal()*4,tip,Color("ffe096"),2)
		view.draw_line(tip-forward*6-forward.orthogonal()*4,tip,Color("ffe096"),2)
	return true
