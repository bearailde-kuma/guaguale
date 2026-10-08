class_name ScratchCard
extends Control
## Real, spatial foil removal. Coverage advances only along the pointer stroke.
signal scraped(at: Vector2)
var font: Font
var masks: Array = []
var cell_rects: Array[Rect2] = []
var card_size := Vector2(480, 340)
var disabled: bool = false
var last_point := Vector2(-999, -999)
var auto_clock: float = 0.0
const GRID_X: int = 18
const GRID_Y: int = 10

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://assets/fonts/fusion-pixel.otf")
	sync()

func sync() -> void:
	masks.clear()
	cell_rects.clear()
	if Game.current.is_empty():
		queue_redraw()
		return
	var t: Dictionary = Catalog.tickets[int(Game.current.tier)]
	var columns: int = int(t.columns)
	var rows: int = ceili(float(t.cells) / columns)
	var width: float = (432.0 - (columns - 1) * 8.0) / columns
	var height: float = minf(66.0, (204.0 - (rows - 1) * 10.0) / rows)
	for i in int(t.cells):
		cell_rects.append(Rect2(24 + (i % columns) * (width + 8), 111 + int(i / columns) * (height + 10), width, height))
		var mask: Array = []
		mask.resize(GRID_X * GRID_Y)
		mask.fill(bool(Game.current.revealed[i]))
		masks.append(mask)
	queue_redraw()

func _process(delta: float) -> void:
	if disabled or not Game.has_pending(): return
	var mouse: Vector2 = get_local_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Game.hover_scratch:
		if last_point.x > -900:
			var steps: int = maxi(1, ceili(last_point.distance_to(mouse) / 8.0))
			for step in mini(steps, 100):
				scratch_at(last_point.lerp(mouse, float(step + 1) / steps))
		else:
			scratch_at(mouse)
		last_point = mouse
	else:
		last_point = Vector2(-999, -999)
	if Input.is_key_pressed(KEY_SPACE) and Game.scratched >= 30:
		auto_clock += delta
		if auto_clock >= 0.12:
			auto_clock = 0.0
			for i in masks.size():
				if not Game.current.revealed[i]:
					masks[i].fill(true)
					Game.reveal_cell(i)
					Audio.play("reveal")
					queue_redraw()
					break

func scratch_at(point: Vector2) -> void:
	if not Game.has_pending() or disabled: return
	var hit: bool = false
	var radius: float = 19.0 + mini(4, Game.resonance / 3) * 4.0
	for i in cell_rects.size():
		if Game.current.revealed[i]: continue
		var rect: Rect2 = cell_rects[i]
		if not rect.grow(radius).has_point(point): continue
		var cell_size := Vector2(rect.size.x / GRID_X, rect.size.y / GRID_Y)
		for y in GRID_Y:
			for x in GRID_X:
				var index: int = y * GRID_X + x
				if masks[i][index]: continue
				var center: Vector2 = rect.position + Vector2(x + 0.5, y + 0.5) * cell_size
				if center.distance_to(point) < radius:
					masks[i][index] = true
					hit = true
		if masks[i].count(true) >= int(GRID_X * GRID_Y * 0.58):
			masks[i].fill(true)
			Game.reveal_cell(i)
			Audio.play("reveal")
	if hit:
		Game.start_scratching()
		Audio.play("scratch")
		scraped.emit(global_position + point)
		queue_redraw()

func text_at(at: Vector2, value: String, size_px: int, color: Color) -> void:
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func _draw() -> void:
	if Game.current.is_empty():
		PixelArt.box(self, Rect2(0, 0, 480, 340), Color("285651"), Color("c6b68f"), 3)
		draw_rect(Rect2(12, 12, 456, 316), Color("60847a"), false, 2)
		text_at(Vector2(122, 114), "好运，就在手边", 24, PixelArt.CREAM)
		PixelArt.coin(self, Vector2(240, 184), 2.0)
		text_at(Vector2(102, 264), "从左边买一张「开门红」", 18, Color("b0cec0"))
		text_at(Vector2(156, 293), "首张教学票固定中奖", 12, Color("8faaa0"))
		return
	var t: Dictionary = Catalog.tickets[int(Game.current.tier)]
	var accent := Color(t.color)
	PixelArt.box(self, Rect2(7, 9, 480, 340), Color(0.06, 0.09, 0.08, 0.35), Color.TRANSPARENT, 0)
	PixelArt.box(self, Rect2(0, 0, 480, 340), PixelArt.CREAM, accent, 5)
	draw_rect(Rect2(0, 0, 480, 91), accent)
	for x in range(12, 480, 16):
		draw_rect(Rect2(x, 6, 5, 4), PixelArt.GOLD)
		draw_rect(Rect2(x, 82, 5, 4), PixelArt.GOLD)
	text_at(Vector2(22, 58), str(t.name), 36, Color("fff0ce"))
	text_at(Vector2(27, 77), str(t.subtitle), 12, Color("ffe3b5"))
	text_at(Vector2(342, 34), "福运 · 即开票", 12, PixelArt.CREAM)
	text_at(Vector2(343, 64), Catalog.money(t.price), 24, PixelArt.CREAM)
	for i in cell_rects.size():
		var rect: Rect2 = cell_rects[i]
		PixelArt.box(self, rect.grow(2), Color("faf2d9"), accent, 2)
		var amount: int = int(Game.current.cells[i])
		var value: String = Catalog.money(amount) if amount > 0 else "谢谢惠顾"
		var size_px: int = 18 if rect.size.x > 90 else 12
		var text_width: float = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		text_at(rect.position + Vector2((rect.size.x - text_width) / 2.0, rect.size.y / 2.0 + 7), value, size_px, Color("a73e38") if amount > 0 else Color("8a8174"))
		var cell_size := Vector2(rect.size.x / GRID_X, rect.size.y / GRID_Y)
		if not Game.current.revealed[i]:
			for y in GRID_Y:
				for x in GRID_X:
					if not masks[i][y * GRID_X + x]:
						var shade := Color("a6b5b5") if (x + y * 3 + i) % 7 < 3 else Color("bec9c5")
						draw_rect(Rect2(rect.position + Vector2(x,y) * cell_size, cell_size + Vector2.ONE), shade)
			if masks[i].count(true) < 8:
				text_at(rect.position + Vector2(rect.size.x / 2 - 12, rect.size.y / 2 + 7), "刮", 24, Color("829796"))
	if int(t.cells) == 3:
		# A red-paper good-luck seal fills the small beginner card's lower half.
		draw_rect(Rect2(177,209,126,80),accent)
		draw_rect(Rect2(182,214,116,70),PixelArt.GOLD,false,2)
		text_at(Vector2(217,272),str(t.symbol),48,PixelArt.GOLD)
		text_at(Vector2(30,247),"喜气临门",18,accent)
		text_at(Vector2(326,247),"鸿运当头",18,accent)
	elif int(t.cells) == 6:
		text_at(Vector2(54,295),"竹报平安    ·    节节高升    ·    好运相随",18,accent)
	text_at(Vector2(24, 329), "NO. %06d  ·  刮出金额即得奖金" % (Game.scratched + (0 if Game.current.settled else 1)), 12, Color("877966"))
	for x in range(356, 449, 4):
		draw_rect(Rect2(x, 317, 2 if x % 3 else 3, 13), Color("6b6d60"))
