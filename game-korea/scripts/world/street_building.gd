class_name StreetBuilding
## 서울 일반 건물 10종. 좌표는 부지 비율, 높이는 월드 단위.
const STYLES := [&"church", &"motel", &"gas_station", &"nightlife", &"parking_tower", &"school", &"subway", &"fire_station", &"finance_tower", &"print_alley"]

static func owns(style: StringName) -> bool:
	return style in STYLES

static func part(out: Array[BuildingModel.Piece], r: Rect2, q: Rect2, h: float, color: Color, text := "", windows := &"punched", base := 0.0) -> BuildingModel.Piece:
	var p := BuildingModel._box(Rect2(r.position + q.position * r.size, q.size * r.size), base, h, color, &"flat", color.darkened(0.18), windows, out.size() * 13 + 7)
	if text != "":
		p.text = text
		p.deco = [&"street_sign", &"entrance"]
		p.accent = Color("237c99")
	out.append(p)
	return p

static func build(out: Array[BuildingModel.Piece], r: Rect2, t: BuildingType, seed: int) -> void:
	match t.style:
		&"church":
			var nave := part(out,r,Rect2(.22,.2,.52,.6),82,Color("945949"),"새빛교회")
			nave.roof = &"gable"
			nave.roof_color = Color("38424b")
			nave.rise = 40
			var steeple := part(out,r,Rect2(.12,.53,.16,.2),150,Color("b69b80"))
			steeple.roof = &"hip"
			steeple.rise = 38
			part(out,r,Rect2(.185,.605,.025,.025),225,Color("ff244f"),"",&"none",185)
			part(out,r,Rect2(.155,.605,.085,.025),213,Color("ff244f"),"",&"none",208)
		&"motel":
			var p := part(out,r,Rect2(.16,.12,.67,.58),150,Color("6d5269"),"달빛 MOTEL")
			p.accent = Color("b62370")
			BuildingModel._units(p,seed,4)
			var entry := part(out,r,Rect2(.2,.7,.6,.17),36,Color("42384b"),"주차장")
			entry.deco = [&"street_curtain", &"street_sign"]
			entry.accent = Color("a92757")
		&"gas_station":
			part(out,r,Rect2(.13,.09,.73,.23),46,Color("ccd5c7"),"한빛 에너지",&"glass")
			var canopy := part(out,r,Rect2(.1,.39,.8,.42),62,Color("1eac9b"),"HANBIT",&"none",54)
			canopy.accent = Color("168575")
			for x in [.2,.5,.8]:
				part(out,r,Rect2(x-.012,.57,.024,.024),54,Color("a7b9b9"),"",&"none")
				for y in [.47,.68]:
					var pump := part(out,r,Rect2(x-.035,y,.07,.045),22,Color("e5dfc9"),"",&"none")
					pump.deco = [&"street_pump"]
		&"nightlife":
			var p := part(out,r,Rect2(.12,.12,.76,.72),162,Color("493a51"),"별밤 노래방")
			p.deco = [&"street_nightlife", &"entrance"]
			BuildingModel._units(p,seed,5)
		&"parking_tower":
			for floor_i in 5:
				var h := float(floor_i * 34)
				for x in [.15,.48,.81]:
					for y in [.15,.75]:
						part(out,r,Rect2(x,y,.035,.035),h+32,Color("949fa6"),"",&"none",h)
				var slab := part(out,r,Rect2(.12,.12,.76,.7),h+36,Color("b3bab8"),"공영 P" if floor_i == 4 else "",&"none",h+29)
				slab.accent = Color("196b8a")
			part(out,r,Rect2(.83,.12,.1,.7),172,Color("78848c"),"",&"punched")
		&"school":
			var p := part(out,r,Rect2(.12,.08,.76,.23),106,Color("c5af89"),"한빛학교")
			BuildingModel._units(p,seed,3)
			part(out,r,Rect2(.08,.15,.17,.42),72,Color("ae8e71"))
			for x in [.12,.8]:
				part(out,r,Rect2(x,.85,.08,.025),3,Color("eeeece"),"",&"none")
			for x in [.04,.94]:
				for j in 9:
					part(out,r,Rect2(x,.1+j*.09,.012,.012),16,Color("607269"),"",&"none")
		&"subway":
			for x in [.3,.65]:
				part(out,r,Rect2(x,.25,.025,.5),12,Color("97a4a6"),"",&"none")
				for y in [.29,.67]:
					part(out,r,Rect2(x,y,.025,.025),48,Color("70828c"),"",&"none")
			var canopy := part(out,r,Rect2(.28,.23,.42,.55),54,Color("467a7e"),"지하철  2",&"none",48)
			canopy.accent = Color("228654")
		&"fire_station":
			var p := part(out,r,Rect2(.12,.1,.76,.48),94,Color("c8b9a1"),"119 소방서")
			p.accent = Color("b4332e")
			BuildingModel._units(p,seed,3)
			for j in 3:
				var bay := part(out,r,Rect2(.14+j*.245,.58,.22,.2),40,Color("a84a37"))
				bay.deco = [&"open_shutter"]
			part(out,r,Rect2(.79,.12,.08,.11),178,Color("a49c8c"),"",&"punched")
		&"finance_tower":
			var podium := part(out,r,Rect2(.1,.1,.8,.75),42,Color("afb6b4"),"한강 FINANCE",&"glass")
			var tower := BuildingModel._box(Rect2(r.position+r.size*Vector2(.24,.22),r.size*Vector2(.5,.48)),42,390,Color("42647c"),&"flat",Color("7e9b9f"),&"glass",seed)
			podium.on_top.append(tower)
			var crown := BuildingModel._box(tower.rect.grow(-18),390,420,Color("a4b9ba"),&"flat",Color("aac2c4"),&"glass",seed)
			tower.on_top.append(crown)
			BuildingModel._units(crown,seed,3)
		&"print_alley":
			var labels := ["서울인쇄", "제본", "활자공방", "철물", "공구", "전기자재"]
			for row in 2:
				for j in 3:
					var p := part(out,r,Rect2(.1+j*.27,.12+row*.52,.25,.29),48+j*12,Color("897c67") if row == 0 else Color("846457"),labels[row*3+j])
					p.deco.append(&"awning")
					BuildingModel._units(p,seed+j+row*7,2)

static func draw_ground(ci: CanvasItem, r: Rect2, t: BuildingType, seed: int) -> void:
	BuildingModel._plinth(ci,r,seed)
	if t.style == &"school":
		var field := Rect2(r.position+r.size*Vector2(.29,.39),r.size*Vector2(.58,.48))
		ci.draw_rect(field,Color("aa8e63"))
		ci.draw_rect(field.grow(-12),Color("ded4b5"),false,2)
		ci.draw_line(Vector2(field.get_center().x,field.position.y+12),Vector2(field.get_center().x,field.end.y-12),Color("ded4b5"),2)
		ci.draw_arc(field.get_center(),minf(field.size.x,field.size.y)*.17,0,TAU,32,Color("ded4b5"),2)
	elif t.style == &"subway":
		var stair := Rect2(r.position+r.size*Vector2(.33,.27),r.size*Vector2(.3,.46))
		ci.draw_rect(stair,Color("19222a"))
		for j in 12:
			var y := stair.position.y+stair.size.y*j/12.0
			ci.draw_line(Vector2(stair.position.x,y),Vector2(stair.end.x,y),Color("87918c").darkened(j*.055),3)
	elif t.style in [&"gas_station", &"parking_tower", &"fire_station", &"motel"]:
		for j in 5:
			var p := r.position+r.size*Vector2(.12+j*.16,.88)
			ci.draw_line(p,p+Vector2(0,r.size.y*.09),Color("c7be91"),2)
