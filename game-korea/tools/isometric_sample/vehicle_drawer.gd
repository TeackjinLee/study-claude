extends RefCounted
## 실제 차량의 크기·도색·방향으로 입체 외형을 그린다. 물리 크기는 바꾸지 않는다.

static func point(view: Node2D, car: Vehicle, local: Vector2, height: float) -> Vector2:
	return view.project(car.global_position + local.rotated(car.motor.heading), height * view.vehicle_height_scale)


static func box(view: Node2D, car: Vehicle, rect: Rect2, bottom: float, top: float, color: Color) -> void:
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	var normals: Array[Vector2] = [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]
	for i in 4:
		var normal := normals[i].rotated(car.motor.heading)
		if normal.x + normal.y <= 0:
			continue
		var j := (i+1)%4
		view._poly([point(view,car,corners[i],bottom),point(view,car,corners[j],bottom),point(view,car,corners[j],top),point(view,car,corners[i],top)],color.darkened(0.3 if normal.x > normal.y else 0.48))
	view._poly([point(view,car,corners[0],top),point(view,car,corners[1],top),point(view,car,corners[2],top),point(view,car,corners[3],top)],color)


static func draw(view: Node2D, car: Vehicle) -> void:
	var w: float = car.stats.size.x
	var l: float = car.stats.size.y
	var cat: StringName = car.stats.category
	var color: Color = car.paint if not car.wrecked else Color("34363b")
	var glass := Color("345665")
	var tire := Color("11151c")
	var tall := cat in [&"suv",&"light",&"swat",&"ambulance",&"camper",&"bus"]
	var truck := cat in [&"truck",&"bigtruck",&"tanker",&"mixer",&"garbage",&"fire",&"tow"]
	# 차체 아래에 접지 그림자를 놓는다.
	var shadow: Array[Vector2] = []
	for p in [Vector2(-w*0.58,-l*0.5),Vector2(w*0.58,-l*0.5),Vector2(w*0.58,l*0.53),Vector2(-w*0.58,l*0.53)]:
		shadow.append(point(view,car,p,0))
	view._poly(shadow,Color(0,0,0,0.4))
	if cat in [&"bike",&"bicycle"]:
		for y in [-l*0.33,l*0.33]:
			box(view,car,Rect2(-2,y-5,4,10),0,8,tire)
		box(view,car,Rect2(-w*0.2,-l*0.22,w*0.4,l*0.5),5,12,color)
		box(view,car,Rect2(-w*0.3,0,w*0.6,9),12,14,tire)
		box(view,car,Rect2(-w*0.5,-l*0.3,w,2),12,13,Color("a2adb1"))
		return
	for side in [-1,1]:
		for axle in [-0.3,0.32]:
			box(view,car,Rect2(side*w*0.51-2,l*axle-5,4,10),1,7,tire)
	box(view,car,Rect2(-w*0.48,-l*0.48,w*0.96,l*0.96),4,10,color)
	# 보닛·범퍼·전후 등화로 진행 방향을 구분한다.
	box(view,car,Rect2(-w*0.43,-l*0.49,w*0.86,3),5,8,Color("76848b"))
	for side in [-1,1]:
		box(view,car,Rect2(side*w*0.31-3,-l*0.48,6,4),9,10,Color("fff1c1"))
		box(view,car,Rect2(side*w*0.32-3,l*0.43,6,3),9,10,Color("d94651"))
	if car.wrecked:
		box(view,car,Rect2(-w*0.3,-l*0.1,w*0.6,l*0.4),10,12,tire)
		return
	if truck:
		box(view,car,Rect2(-w*0.47,-l*0.45,w*0.94,l*0.33),10,22,color)
		box(view,car,Rect2(-w*0.38,-l*0.4,w*0.76,l*0.15),22,23,glass)
		var bed := Rect2(-w*0.46,-l*0.05,w*0.92,l*0.5)
		if cat == &"truck" or cat == &"tow":
			box(view,car,bed,10,12,color.darkened(0.4))
			for side in [-1,1]:
				box(view,car,Rect2(side*w*0.45-1,-l*0.05,2,l*0.5),11,17,color)
			box(view,car,Rect2(-w*0.46,l*0.43,w*0.92,2),11,17,color)
		else:
			box(view,car,bed,10,27,car.stats.roof_color)
			for y in range(0,int(l*0.43),8):
				box(view,car,Rect2(-w*0.44,y,w*0.88,1),27,28,Color("7b8990"))
	elif tall:
		var h := 25.0 if cat == &"bus" else 21.0
		box(view,car,Rect2(-w*0.44,-l*0.36,w*0.88,l*0.79),10,h,color)
		box(view,car,Rect2(-w*0.38,-l*0.34,w*0.76,l*0.16),h,h+1,glass)
		for side in [-1,1]:
			for y in range(int(-l*0.12),int(l*0.32),10):
				box(view,car,Rect2(side*w*0.44-1,y,2,7),13,h-3,glass)
		box(view,car,Rect2(-w*0.25,-l*0.02,w*0.5,l*0.3),h,h+2,car.stats.roof_color)
	else:
		# 지붕 폭을 줄이고 경사진 앞뒤 유리를 그린다.
		var lower := Rect2(-w*0.44,-l*0.25,w*0.88,l*0.62)
		var upper := Rect2(-w*0.32,-l*0.09,w*0.64,l*0.32)
		var low: Array[Vector2] = [lower.position,Vector2(lower.end.x,lower.position.y),lower.end,Vector2(lower.position.x,lower.end.y)]
		var high: Array[Vector2] = [upper.position,Vector2(upper.end.x,upper.position.y),upper.end,Vector2(upper.position.x,upper.end.y)]
		for k in 4:
			var j := (k+1)%4
			view._poly([point(view,car,low[k],10),point(view,car,low[j],10),point(view,car,high[j],19),point(view,car,high[k],19)],glass.darkened(0.12*(k%2)))
		box(view,car,upper,18,20,color.lightened(0.12))
		for side in [-1,1]:
			box(view,car,Rect2(side*w*0.49-2,-l*0.17,4,4),11,13,color)
		if cat == &"sport":
			box(view,car,Rect2(-w*0.47,l*0.35,w*0.94,3),12,15,color.darkened(0.4))
	if cat == &"taxi":
		box(view,car,Rect2(-w*0.23,0,w*0.46,6),20,25,Color("ffe085"))
	if cat in [&"police",&"ambulance",&"swat",&"fire"]:
		var z := 22.0 if cat == &"police" else 28.0
		var flash := car.siren and int(Time.get_ticks_msec()/180)%2 == 0
		box(view,car,Rect2(-w*0.33,-3,w*0.33,5),z,z+3,Color("ff6574") if flash else Color("922b43"))
		box(view,car,Rect2(0,-3,w*0.33,5),z,z+3,Color("609fff") if not flash else Color("285287"))
