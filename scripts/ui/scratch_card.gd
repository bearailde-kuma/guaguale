class_name ScratchCard
extends Control
## Spatial scratch surface plus per-rule ticket layout. No wallet mutations here.
signal scraped(at: Vector2)
var font: Font
var masks: Array = []
var cell_rects: Array[Rect2] = []
var card_size := Vector2(570,408)
var disabled: bool = false
var last_point := Vector2(-999,-999)
var quick_clock: float = 0.0
var elapsed: float = 0.0
const GRID_X: int = 18
const GRID_Y: int = 10

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://assets/fonts/fusion-pixel.otf")
	sync()

func sync() -> void:
	masks.clear(); cell_rects.clear()
	last_point = Vector2(-999,-999)
	if Game.current.is_empty():
		queue_redraw(); return
	var board: Dictionary = Game.current.board
	for i in board.cells.size():
		var rect := Rect2()
		match str(board.rule):
			"integral": rect=Rect2(23+i*87,209,77,46)
			"path": rect=Rect2(24+i*65,247,57,44)
			"limit": rect=Rect2(38+i%2*187,161+int(i/2)*66,162,51)
			"circuit": rect=Rect2(66+i%3*84,118+int(i/3)*61,70,49)
			"convolution": rect=Rect2(24+i*87,173,77,49)
			"dragon": rect = Rect2(22+i*88,177,78,48)
			"numbers":
				if i<2: rect = Rect2(27+i*106,156,94,72)
				else: rect = Rect2(256+(i-2)%3*96,137+int((i-2)/3)*84,87,68)
			"vault":
				if i<3: rect = Rect2(26+i*126,119,112,31)
				else: rect = Rect2(26+(i-3)%3*126,164+int((i-3)/3)*47,112,37)
			"pairs": rect = Rect2(44+i%2*150,122+int(i/2)*46,124,37)
			"collect": rect = Rect2(23+i%4*92,126+int(i/4)*57,80,47)
			"sum": rect = Rect2(24+i%3*120,138+int(i/3)*54,105,44)
			_:
				var cols: int = 3 if board.cells.size()<=9 else 5
				rect = Rect2(24+i%cols*(368.0/cols),125+int(i/cols)*57,368.0/cols-12,47)
		cell_rects.append(rect)
		var mask: Array = []
		mask.resize(GRID_X*GRID_Y); mask.fill(bool(Game.current.revealed[i])); masks.append(mask)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if not Game.current.is_empty(): queue_redraw()
	if disabled or not Game.has_pending(): return
	var mouse: Vector2 = get_local_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Game.hover_scratch:
		if last_point.x>-900:
			var steps: int = maxi(1,ceili(last_point.distance_to(mouse)/8.0))
			for step in mini(steps,100): scratch_at(last_point.lerp(mouse,float(step+1)/steps))
		else: scratch_at(mouse)
		last_point = mouse
	else: last_point = Vector2(-999,-999)
	if Input.is_key_pressed(KEY_SPACE):
		quick_clock += delta
		if quick_clock>=0.18:
			quick_clock = 0.0
			for i in masks.size():
				if not Game.current.revealed[i]:
					Game.reveal_cell(i); Audio.play("reveal"); break

func scratch_at(point: Vector2) -> void:
	if not Game.has_pending() or disabled: return
	var hit: bool = false
	var radius: float = 20.0+mini(4,Game.resonance/3)*4.0+(10.0 if Game.current.get("flow",false) else 0.0)
	for i in cell_rects.size():
		if Game.current.revealed[i]: continue
		var rect: Rect2 = cell_rects[i]
		if not rect.grow(radius).has_point(point): continue
		var cell_size := Vector2(rect.size.x/GRID_X,rect.size.y/GRID_Y)
		for y in GRID_Y:
			for x in GRID_X:
				var index: int = y*GRID_X+x
				if masks[i][index]: continue
				var center: Vector2 = rect.position+Vector2(x+0.5,y+0.5)*cell_size
				if center.distance_to(point)<radius:
					masks[i][index] = true; hit = true
		if masks[i].count(true)>=int(GRID_X*GRID_Y*0.58):
			masks[i].fill(true); Game.reveal_cell(i); Audio.play("reveal")
	if hit:
		Game.start_scratching(); Audio.play("scratch"); scraped.emit(global_position+point); queue_redraw()

func text_at(at: Vector2, value: String, px: int, color: Color) -> void:
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,px,color)

func centered(rect: Rect2, value: String, px: int, color: Color, offset: float = 0) -> void:
	var w: float = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x
	text_at(rect.position+Vector2((rect.size.x-w)/2,rect.size.y/2+px/3.0+offset),value,px,color)

func _draw() -> void:
	if Game.current.is_empty():
		PixelArt.box(self,Rect2(Vector2.ZERO,card_size),Color("285651"),Color("c6b68f"),3)
		draw_rect(Rect2(12,12,546,384),Color("60847a"),false,2)
		text_at(Vector2(117,109),"刮尽尘缘，逆命登仙",30,PixelArt.CREAM)
		PixelArt.cultivator(self,Vector2(285,212),1.8)
		text_at(Vector2(89,287),"你欠下道盟千亿灵债，唯有符票能改命",18,Color("b0cec0"))
		text_at(Vector2(123,327),"首票教学必中 · 前五张无骷髅 · 炼气解锁代刮",12,Color("a6beae"))
		return
	var cur: Dictionary = Game.current
	var t: Dictionary = Catalog.tickets[int(cur.tier)]
	var board: Dictionary = cur.board
	var rule: String = str(board.rule)
	var accent := Color(t.color)
	PixelArt.box(self,Rect2(6,7,570,408),Color(0.04,0.08,0.08,0.4),Color.TRANSPARENT,0)
	PixelArt.box(self,Rect2(Vector2.ZERO,card_size),Color("f5e9cb"),accent,4)
	draw_rect(Rect2(0,0,570,78),accent)
	for x in range(10,566,16): draw_rect(Rect2(x,5,5,3),PixelArt.GOLD)
	text_at(Vector2(22,48),str(t.name),36,Color("fff0ce"))
	text_at(Vector2(24,68),str(t.subtitle)+"  /  "+str(t.symbol)+"道主题" if rule==t.rule else "前版已购票 · 保留原规则与奖金",12,Color("ffe3b5"))
	text_at(Vector2(437,29),"仙途 · 即开符",12,PixelArt.CREAM)
	text_at(Vector2(426,61),Catalog.money(t.price),24,PixelArt.CREAM)
	text_at(Vector2(18,101),"旧版已购票：沿用原票面规则与奖金，下一张采用新玩法。" if rule!=t.rule else str(t.description),12,Color("5c594e"))
	_draw_theme(rule,accent)
	var visible: Array = TicketRules.visible_hits(cur)
	var next_auto: int = cur.revealed.find(false) if Game.auto_enabled and not disabled else -1
	for i in cell_rects.size():
		var rect: Rect2 = cell_rects[i]
		var known: bool = bool(cur.revealed[i])
		var winning: bool = (i in cur.hits and (cur.settled or cur.seen)) or i in visible
		PixelArt.box(self,rect.grow(2),Color("fff8df"),Color("ae8739") if winning and known else accent,2)
		if rule=="pairs": _face(rect,int(board.cells[i]))
		if rule=="circuit": _pipe(rect,int(board.cells[i]),Color("3c9a88") if winning else accent)
		var color := Color("984037") if winning else Color("364c53")
		centered(rect,TicketRules.cell_text(board,i),18 if rule in MysticRules.RULES else (24 if rule!="legacy" else 12),color,-8 if rule=="numbers" and i>=2 else 0)
		if rule=="numbers" and i>=2:
			centered(rect,Catalog.money(float(board.cells[i].prize)*int(cur.price)),12,Color("95652f"),20)
		if i==int(cur.get("skull_index",-1)):
			PixelArt.skull(self,rect.end-Vector2(10,10),.55,Color("57958c") if cur.get("skull_blocked",false) else Color("af4555"))
		var cell_size := Vector2(rect.size.x/GRID_X,rect.size.y/GRID_Y)
		var auto_coverage: float = clampf(Game.auto_clock/Game.automation_interval(),0,1) if i==next_auto and cur.get("auto_paid",false) and Game.auto_wait<=0 else 0.0
		if not known:
			for y in GRID_Y:
				for x in GRID_X:
					if not masks[i][y*GRID_X+x] and float(x)/GRID_X>=auto_coverage:
						var shade := Color("a8b7b7") if (x+y*3+i)%7<3 else Color("c3cfca")
						draw_rect(Rect2(rect.position+Vector2(x,y)*cell_size,cell_size+Vector2.ONE),shade)
			if cur.seen and i==int(cur.get("skull_index",-1)):
				centered(rect,"已化劫" if cur.get("skull_blocked",false) else "骷髅！",12,Color("ad4244"))
			elif cur.seen and int(cur.payout)==0 and rule=="dragon" and board.cells[i].op=="*" and board.cells[i].n==0:
				centered(rect,"危险 ×0",12,Color("ad4244"))
			elif masks[i].count(true)<8 and auto_coverage<=0:
				centered(rect,"刮",18,Color("849d99"))
		if auto_coverage>0 and not Game.reduced_motion:
			PixelArt.coin(self,rect.position+Vector2(rect.size.x*auto_coverage,rect.size.y*.5),.42)
	_draw_receipt()
	text_at(Vector2(20,397),"NO. %06d / 劫印 %.2f%%每张 / 虚构符票" % [Game.scratched+(0 if cur.settled else 1),float(cur.get("risk_chance",0))*100],12,Color("877966"))
	for x in range(467,546,4): draw_rect(Rect2(x,385,2 if x%3 else 3,14),Color("6b6d60"))

func _draw_theme(rule: String, accent: Color) -> void:
	var cur: Dictionary = Game.current
	var board: Dictionary = cur.board
	if rule in MysticRules.RULES:
		_draw_mystic(rule,accent)
	elif rule in ["match3","collect","lines"]:
		text_at(Vector2(419,130),"兑奖表",18,accent)
		for i in 6:
			var label: String = "%d号" % (i+1)
			if rule=="collect": label = "%d宝" % (i+3)
			text_at(Vector2(407,156+i*25),label,12,Color("716959"))
			text_at(Vector2(453,156+i*25),Catalog.money(float(board.grades[i])*int(cur.price)),12,Color("9d6234"))
		if rule=="lines":
			for x in [80,200,322]:
				draw_line(Vector2(x,109),Vector2(x,119),accent,2)
				draw_rect(Rect2(x-8,111,16,8),Color("dea348"))
	elif rule=="numbers":
		text_at(Vector2(48,139),"幸运号码",18,accent)
		text_at(Vector2(39,256),"号码相同才能中奖",12,accent)
		for i in 6: draw_rect(Rect2(37+i*29,276-i*3,17,17+i*3),Color("83a67e"))
	elif rule=="dragon":
		var running: int = 0
		var expression: String = "起点 0"
		for i in 6:
			var x: float = 61+i*88
			# Pixel rowers: head, shirt (the scratch field), and moving paddles.
			draw_rect(Rect2(x-11,146,22,22),Color("e4af7b"))
			draw_rect(Rect2(x-14,142,28,7),Color("273f4d"))
			draw_rect(Rect2(x-20,169,40,8),accent)
			var sway: float = sin(elapsed*5+i)*6 if not Game.reduced_motion else 0.0
			draw_line(Vector2(x+28,227),Vector2(x+42+sway,267),Color("996841"),4)
			draw_rect(Rect2(x+37+sway,257,11,21),Color("d69e58"))
			if cur.revealed[i]:
				expression += " → "+TicketRules.cell_text(board,i)
				if board.cells[i].op=="+": running += int(board.cells[i].n)
				else: running *= int(board.cells[i].n)
			else:
				expression += " → ?"
		text_at(Vector2(26,130),expression,12,accent)
		draw_colored_polygon(PackedVector2Array([Vector2(14,276),Vector2(550,276),Vector2(523,296),Vector2(52,296)]),Color("9a493c"))
		draw_rect(Rect2(16,268,27,16),PixelArt.GOLD)
		draw_rect(Rect2(14,257,13,18),accent)
		draw_rect(Rect2(17,260,4,4),PixelArt.CREAM)
		for x in range(28,546,24): draw_rect(Rect2(x,301,16,3),Color("649ea5"))
	elif rule in ["sum","pairs","vault"]:
		var rows: int = 4 if rule=="pairs" else 3
		for row in rows:
			var y: float = 147+row*46 if rule=="pairs" else (189+row*47 if rule=="vault" else 167+row*54)
			text_at(Vector2(409,y),"奖 "+Catalog.money(float(board.prizes[row])*int(cur.price)),12,accent)
		if rule=="vault": text_at(Vector2(419,141),"三把钥匙",12,accent)
		if rule=="sum": text_at(Vector2(27,124),"三条寻宝路线 · 每行目标 18 点",12,accent)

func _face(rect: Rect2, n: int) -> void:
	var colors: Array = [Color("db7771"),Color("deb17f"),Color("99b5cc"),Color("9ebf9a"),Color("c6abcf"),Color("e3c879")]
	draw_rect(rect.grow(-3),colors[n-1])
	for x in [10,rect.size.x-18]:
		draw_rect(Rect2(rect.position+Vector2(x,10),Vector2(8,4)),Color("334b50"))
		draw_rect(Rect2(rect.position+Vector2(x+2,15),Vector2(4,8)),Color("fff1cc"))

func _draw_receipt() -> void:
	var cur: Dictionary = Game.current
	draw_line(Vector2(17,313),Vector2(553,313),Color("b5a37b"),1)
	if cur.settled or cur.seen:
		text_at(Vector2(22,332),("本世终止 · " if Game.run_over and not cur.settled else ("已兑奖 · " if cur.settled else "望气 · "))+str(cur.detail),12,Color("965738"))
		text_at(Vector2(22,355),"票面 %s × 财运 %.2f × 状态 %.0f × 技能 %d" % [Catalog.money(cur.base_prize),cur.fortune,cur.effect,cur.skill_factor],12,Color("665c4c"))
		text_at(Vector2(22,377),("致命票不兑奖 · 原可得 " if Game.run_over and not cur.settled else "合计 ")+Catalog.money(cur.payout)+("  · 点石成金已改运" if cur.get("transmuted",false) else ""),18,Color("a23f37"))
	else:
		text_at(Vector2(22,337),"刮开全部才能兑奖，满足票面规则才有奖金。",12,Color("736a59"))
		text_at(Vector2(22,363),"当前加成：财运 ×%.2f · 状态 ×%.0f · 技能 ×%d" % [cur.fortune,cur.effect,cur.skill_factor],12,Color("956333"))

func _pipe(rect: Rect2, mask: int, color: Color) -> void:
	var center: Vector2=rect.get_center()
	for d in 4:
		if mask & (1<<d):
			var direction := Vector2(MysticRules.DIRS[d])
			draw_line(center,center+direction*rect.size*.5,color,7)
	draw_rect(Rect2(center-Vector2(5,5),Vector2(10,10)),color)

func _draw_mystic(rule: String, accent: Color) -> void:
	var cur: Dictionary=Game.current
	var b: Dictionary=cur.board
	var all_known: bool=not false in cur.revealed
	match rule:
		"integral":
			text_at(Vector2(24,123),"积分炼丹：每炉面积 = 宽 × 高；红色负面积会扣除",12,accent)
			draw_line(Vector2(22,176),Vector2(546,176),Color("a3a486"),2)
			for i in 6:
				if not cur.revealed[i]: continue
				var value: int=int(b.cells[i].w)*int(b.cells[i].h)
				var h: float=clampf(absf(value)*1.2,2,36)
				draw_rect(Rect2(38+i*87,176-h if value>=0 else 176,48,h),Color("68a489") if value>=0 else Color("c97870"))
			text_at(Vector2(25,281),"净面积 ≥6/10/16/24/36/54 → 一至六档奖",12,accent)
		"path":
			draw_line(Vector2(24,225),Vector2(548,225),Color("ba8271"),2)
			var height: int=0
			var previous:=Vector2(26,225)
			for i in 8:
				if not cur.revealed[i]: break
				height+=1 if int(b.cells[i])==1 else -1
				var point:=Vector2(26+(i+1)*63,225-height*12)
				draw_line(previous,point,accent if height>=0 else Color("be5258"),4)
				draw_rect(Rect2(point-Vector2(3,3),Vector2(6,6)),PixelArt.GOLD)
				previous=point
				if height<0: break
			text_at(Vector2(24,123),"剑气面积 ≥4/6/8/10/12/14 → 一至六档奖",12,accent)
		"limit":
			text_at(Vector2(39,139),"lim (a·n^p + 1) / (b·n^q + 1)",18,accent)
			text_at(Vector2(403,169),"n → 无穷",18,accent)
			text_at(Vector2(403,203),"同阶 → a/b",12,accent)
			text_at(Vector2(403,231),"异阶 → 空奖",12,accent)
			text_at(Vector2(39,295),"极限 1/2/3/5/8/13 → 一至六档奖",12,accent)
		"circuit":
			text_at(Vector2(15,207),"灵源",12,accent)
			draw_line(Vector2(43,203),Vector2(65,203),accent,4)
			for row in 3:
				text_at(Vector2(337,148+row*61),"阵眼 "+Catalog.money(int(b.prizes[row])*int(cur.price)),18,accent)
			text_at(Vector2(337,291),"只沿相接的符脉传导",12,accent)
		"convolution":
			text_at(Vector2(24,137),"六枚灵石各用零次或一次 · 目标灵气 %d" % b.target,18,accent)
			text_at(Vector2(25,253),"生成函数：各枚对应 (1+x^灵气)，相乘取目标系数",12,accent)
			text_at(Vector2(25,278),"组合 ≥1/2/4/6/10/15 种 → 一至六档奖",12,accent)
			if all_known: text_at(Vector2(25,302),"自动穷举 64 种选择：共有 %d 种达标" % MysticRules.coefficient(b.cells,int(b.target)),12,accent)
	if rule!="circuit":
		var prize_text: String="奖档 "
		for g in b.grades: prize_text+="×%d " % int(g)
		text_at(Vector2(25,(309 if rule=="limit" else 303) if rule!="convolution" else 158),prize_text+"票价",12,Color("9d6234"))
