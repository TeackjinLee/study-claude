class_name RoadDetail
## 도로 시트의 아스팔트·보도 재질. 물리/차선 좌표와 독립적인 바닥 장식.
static var _asphalt: ImageTexture

static func asphalt(ci: CanvasItem, r: Rect2) -> void:
	if _asphalt == null:
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				var h := noise(x, y)
				var shade := .135 + h*.065
				img.set_pixel(x,y,Color(shade,shade*1.035,shade*1.10))
		_asphalt = ImageTexture.create_from_image(img)
	ci.draw_texture_rect(_asphalt,r,true)
	# 보수 흔적과 균열은 구간 안에 제한한다.
	var seed_id := int(r.position.x*.13+r.position.y*.37)
	for k in 5:
		var at := r.position + Vector2(20,20) + (r.size-Vector2(40,40))*Vector2(noise(seed_id,k),noise(k+7919,seed_id))
		var end := (at+Vector2(12+noise(k,seed_id)*20,6)).clamp(r.position+Vector2.ONE,r.end-Vector2.ONE)
		ci.draw_line(at,end,Color(.065,.07,.075,.65),1)
		ci.draw_line(end,(end+Vector2(-4,7)).clamp(r.position,r.end),Color(.075,.08,.085,.5),.7)

static func noise(x: int,y: int) -> float:
	return fposmod(sin(x*127.1+y*311.7)*43758.5453,1.0)

static func pavement(ci: CanvasItem, r: Rect2) -> void:
	# 부지 안쪽은 기존 건물/공터가 그린다. 테두리 인도만 포장.
	var strips: Array[Rect2] = [Rect2(r.position,Vector2(r.size.x,City.SIDEWALK)),Rect2(r.position+Vector2(0,r.size.y-City.SIDEWALK),Vector2(r.size.x,City.SIDEWALK)),Rect2(r.position+Vector2(0,City.SIDEWALK),Vector2(City.SIDEWALK,r.size.y-City.SIDEWALK*2)),Rect2(r.position+Vector2(r.size.x-City.SIDEWALK,City.SIDEWALK),Vector2(City.SIDEWALK,r.size.y-City.SIDEWALK*2))]
	for strip in strips:
		var y := strip.position.y
		while y < strip.end.y:
			var x := strip.position.x
			while x < strip.end.x:
				var shade := noise(int(x),int(y))
				var size := Vector2(minf(18,strip.end.x-x),minf(14,strip.end.y-y))
				ci.draw_rect(Rect2(Vector2(x,y),size-Vector2(.8,.8)),Color("77766e").darkened(shade*.22))
				x += 18
			y += 14
	ci.draw_rect(r.grow(-1),Color("a29f8f"),false,2)
	# 횡단보도 양 끝의 점자 경고 블록.
	for corner in [r.position,r.position+Vector2(r.size.x-28,0),r.end-Vector2(28,28),r.position+Vector2(0,r.size.y-28)]:
		var tile := Rect2(corner+Vector2(4,4),Vector2(20,20))
		ci.draw_rect(tile,Color("b69b49"))
		for row in 4:
			for col in 4:
				ci.draw_circle(tile.position+Vector2(3+col*4,3+row*4),.75,Color("e1c77b"))

static func drain(ci: CanvasItem, at: Vector2, vertical: bool) -> void:
	var size := Vector2(8,22) if vertical else Vector2(22,8)
	ci.draw_rect(Rect2(at-size*.5,size),Color("121c20"))
	ci.draw_rect(Rect2(at-size*.5,size),Color("6b716b"),false,1)
	for k in 6:
		var offset := -9.0+k*3.5
		var a := at+ (Vector2(-3,offset) if vertical else Vector2(offset,-3))
		var b := at+ (Vector2(3,offset) if vertical else Vector2(offset,3))
		ci.draw_line(a,b,Color("535d5d"),1)

static func manhole(ci: CanvasItem, at: Vector2) -> void:
	ci.draw_circle(at,10,Color("12191c"))
	ci.draw_circle(at,8.5,Color("434947"))
	ci.draw_arc(at,7,0,TAU,20,Color("77776a"),.8)
	for k in range(-2,3):
		ci.draw_line(at+Vector2(-5,k*2),at+Vector2(5,k*2),Color("252d2d"),.8)

static func worn_paint(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r,Color("cecbb8"))
	for k in 7:
		var at := r.position+r.size*Vector2(noise(int(r.position.x)+k,31),noise(int(r.position.y)+k,91))
		ci.draw_rect(Rect2(at,Vector2(minf(2,r.end.x-at.x),minf(2,r.end.y-at.y))),Color("444846"))
