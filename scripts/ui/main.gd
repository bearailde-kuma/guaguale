extends Control
## Composition root: presentation, input routing and short activity cutscenes.
const ART = preload("res://scripts/ui/pixel_art.gd")
const CardView = preload("res://scripts/ui/scratch_card.gd")
var font: Font
var card: ScratchCard
var ui: Control
var modal_ui: Control
var cursor_layer: Control
var ticket_buttons: Array[Button] = []
var skill_buttons: Array[Button] = []
var work_button: Button
var modal: String = ""
var asset_page: int = 0
var busy: bool = false
var animation_time: float = 0.0
var animation_duration: float = 1.0
var animation_title: String = ""
var animation_kind: String = ""
var animation_callback: Callable
var toast: String = "欢迎光临！左边选票，按住硬币刮开涂层。"
var toast_time: float = 8.0
var result_text: String = ""
var result_big: bool = false
var particles: Array = []
var fx_rng := RandomNumberGenerator.new()
var elapsed: float = 0.0
var skill_flash: float = 0.0
var help_lines: Array = [
	"01  买票：左侧选一张，按住鼠标左键拖动硬币。",
	"02  银色涂层刮开后，所有格子的金额相加兑奖。",
	"03  好运来在购票前用；透视和倍率在刮开前用。",
	"04  精神会慢慢恢复，也能喝茶、按摩、出门旅行。",
	"05  聚财提升所有奖金；车房增加精神上限和收益。",
	"06  连续 4 张未中奖，第 5 张保证中奖。",
	"07  刮满 30 张后，按住空格可以快速刮开。",
	"08  买齐 10 件资产、身家达到 1000 亿即可通关。",
	"快捷键：1 / 2 / 3 技能，B 再买同款，Esc 关闭。",
	"这是虚构的单机增量游戏，所有资金仅用于游戏内。"
]

func _ready() -> void:
	font = load("res://assets/fonts/fusion-pixel.otf")
	fx_rng.randomize()
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	card = CardView.new()
	card.position = Vector2(344, 274)
	card.size = Vector2(480, 340)
	add_child(card)
	card.scraped.connect(_debris)
	for i in Catalog.tickets.size():
		var index: int = i
		var button: Button = make_button(ui, Rect2(36, 235 + i * 78, 222, 68), "", func(): buy(index), Color(Catalog.tickets[i].color))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 18)
		ticket_buttons.append(button)
	for i in 3:
		var index: int = i
		var button: Button = make_button(ui, Rect2(989, 386 + i * 77, 247, 64), "", func(): use_skill(index), Color("285c64"))
		button.add_theme_font_size_override("font_size", 18)
		skill_buttons.append(button)
	for entry in [["生活", "life", 36], ["车房收藏", "assets", 217], ["聚财升级", "upgrade", 398], ["成长手账", "stats", 579]]:
		var which: String = entry[1]
		make_button(ui, Rect2(entry[2], 720, 162, 54), entry[0], func(): open_modal(which), Color("285c64"))
	work_button = make_button(ui, Rect2(956, 720, 282, 54), "", _work, Color("ad7244"))
	make_button(ui, Rect2(858, 720, 76, 54), "设置", func(): open_modal("settings"), Color("394d54"), 18)
	make_button(ui, Rect2(1175, 113, 64, 36), "帮助", func(): open_modal("help"), Color("394d54"), 12)
	modal_ui = Control.new()
	modal_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_ui)
	cursor_layer = Control.new()
	cursor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cursor_layer)
	cursor_layer.draw.connect(_draw_overlay)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	Game.changed.connect(_refresh)
	Game.notice.connect(show_toast)
	Game.ticket_settled.connect(_settled)
	Game.completed.connect(func(): call_deferred("open_modal", "ending"))
	_refresh()
	if not Game.current.is_empty() and Game.current.settled:
		result_text = "已兑奖  +%s" % Catalog.money(Game.current.payout) if Game.current.payout > 0 else "这次没中，下一张再见。"
	if "--smoke" in OS.get_cmdline_user_args():
		call_deferred("_smoke")

func make_button(parent: Control, rect: Rect2, caption: String, callback: Callable, color: Color, size_px: int = 24) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = caption
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", size_px)
	button.add_theme_color_override("font_color", ART.CREAM)
	button.add_theme_color_override("font_hover_color", Color("fff7dc"))
	button.add_theme_color_override("font_disabled_color", Color("778a89"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.lightened(0.12) if state == "hover" else color
		if state == "pressed": style.bg_color = color.darkened(0.16)
		if state == "disabled": style.bg_color = Color("263e43")
		style.border_color = ART.GOLD if state == "hover" or state == "focus" else Color("152c32")
		style.set_border_width_all(2)
		style.border_width_bottom = 5
		style.content_margin_left = 12
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(func():
		if busy: return
		Audio.play("click")
		callback.call())
	parent.add_child(button)
	return button

func _refresh() -> void:
	for i in ticket_buttons.size():
		var t: Dictionary = Catalog.tickets[i]
		var available: bool = Game.unlocked(i)
		ticket_buttons[i].text = "%s    %s\n%d 个刮区  ·  %s" % [t.name, Catalog.money(t.price), t.cells, "点击购票" if available else "尚未解锁"]
		ticket_buttons[i].disabled = busy or not modal.is_empty() or Game.has_pending() or not available or Game.cash < int(t.price)
		ticket_buttons[i].tooltip_text = "基础中奖率 %d%% · 原始最高奖金 %s\n解锁：累计奖金 %s + 刮 %d 张" % [int(t.chance * 100), Catalog.money(t.price * t.jackpot), Catalog.money(t.unlock_earned), t.unlock_scratched]
	for i in skill_buttons.size():
		var s: Dictionary = Catalog.config.skills[i]
		var effects: Array = ["看穿中奖", "下张+25%", "本张×3"]
		skill_buttons[i].text = "%s   [%s]\n%s" % [s.name, s.key, "精神-%d / %s" % [s.cost,effects[i]] if Game.skill_unlocked(i) else "%d张 / 精神上限%d" % [s.scratched, s.capacity]]
		skill_buttons[i].disabled = busy or not modal.is_empty() or not Game.skill_unlocked(i)
		skill_buttons[i].tooltip_text = s.description
	card.disabled = busy or not modal.is_empty()
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	toast_time = maxf(0, toast_time - delta)
	skill_flash = maxf(0, skill_flash - delta)
	work_button.text = "打工  +%s" % Catalog.money(Game.work_pay()) if Game.work_cooldown <= 0 else "收工休息  %ds" % ceili(Game.work_cooldown)
	work_button.disabled = busy or not modal.is_empty() or Game.work_cooldown > 0
	if busy:
		animation_time += delta
		if animation_time >= animation_duration:
			busy = false
			if animation_callback.is_valid(): animation_callback.call()
			animation_callback = Callable()
			_refresh()
	for i in range(particles.size() - 1, -1, -1):
		particles[i].life -= delta
		particles[i].pos += particles[i].velocity * delta
		particles[i].velocity.y += 170 * delta
		if particles[i].life <= 0: particles.remove_at(i)
	queue_redraw()
	cursor_layer.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not busy:
			open_modal("" if not modal.is_empty() else "settings")
		if busy or not modal.is_empty(): return
		match event.keycode:
			KEY_1: use_skill(0)
			KEY_2: use_skill(1)
			KEY_3: use_skill(2)
			KEY_B: buy(int(Game.current.get("tier", 0)))

func buy(tier: int) -> void:
	if busy or not modal.is_empty(): return
	if Game.buy_ticket(tier):
		result_text = ""
		result_big = false
		card.sync()
		Audio.play("click")
		if not Game.reduced_motion:
			card.position.y = 261
			create_tween().tween_property(card, "position:y", 274.0, 0.17).set_trans(Tween.TRANS_QUAD)

func use_skill(index: int) -> void:
	if busy or not modal.is_empty(): return
	var error: String = Game.skill_error(index)
	if not error.is_empty():
		show_toast(error)
		return
	Audio.play("skill")
	animate_action(Catalog.config.skills[index].name,"ability",0.55,func(): _commit_skill(index))

func _commit_skill(index: int) -> void:
	if Game.use_skill(index):
		skill_flash = 0.65
		Audio.play("skill")
		card.queue_redraw()
		if index == 0: show_toast("透视结果：这张会中奖！" if Game.current.payout > 0 else "透视结果：这张未中奖。保留精神力吧。")
		elif index == 1: show_toast("好运就位：下一张票中奖率 +25 个百分点。")
		else: show_toast("就这把了！本张奖金 ×3，未中奖仍为 0。")

func _settled(payout: int, big: bool) -> void:
	result_big = big
	result_text = ("大奖来了！  +" if big else "中奖啦  +") + Catalog.money(payout) if payout > 0 else "谢谢惠顾 · 还有下一次好运"
	if payout > 0:
		Audio.play("big" if big else "win")
		burst(Vector2(582, 337), 90 if big else 24)
	if Game.scratched == 3: show_toast("聚财升级已解锁！花 ¥100 让所有奖金永久 ×%.1f。" % Catalog.config.resonance_factor)
	elif Game.scratched == 10: show_toast("新技能：好运来！买票前按 2 提升中奖概率。")
	elif Game.scratched == 30: show_toast("快速刮票已解锁：按住空格，让硬币帮你刮完。")
	card.queue_redraw()

func show_toast(message: String) -> void:
	toast = message
	toast_time = 5.0

func _debris(at: Vector2) -> void:
	if Game.reduced_motion: return
	for i in 2:
		particles.append({"pos":at,"velocity":Vector2(fx_rng.randf_range(-35, 35), fx_rng.randf_range(-60, 0)),"life":0.4,"color":Color("bcc9bd"),"size":3})

func burst(at: Vector2, count: int) -> void:
	if Game.reduced_motion: return
	for i in count:
		particles.append({"pos":at,"velocity":Vector2(fx_rng.randf_range(-310, 310), fx_rng.randf_range(-350, -50)),"life":fx_rng.randf_range(0.8, 2.4),"color":[ART.GOLD,Color("e76957"),Color("9ed4ba"),ART.CREAM][i % 4],"size":6})

func animate_action(title: String, kind: String, duration: float, callback: Callable) -> void:
	open_modal("")
	busy = true
	animation_title = title
	animation_kind = kind
	animation_time = 0.0
	animation_duration = maxf(0.3, duration * (0.35 if Game.reduced_motion else 1.0))
	animation_callback = callback
	_refresh()

func _work() -> void:
	if Game.work_cooldown > 0: return
	animate_action("街坊帮工 · 送一单快递", "work", 2.0, func():
		if Game.work():
			show_toast("收工啦！工资 +%s，精神 +3。" % Catalog.money(Game.work_pay()))
			Audio.play("win"))

func _activity(index: int) -> void:
	var item: Dictionary = Catalog.config.activities[index]
	if Game.cash < int(item.cost) or Game.earned < int(item.unlock) or Game.spirit >= Game.max_spirit() - 0.1:
		Game.activity(index)
		return
	animate_action(item.name, item.id, float(item.duration), func():
		if Game.activity(index):
			show_toast(item.description)
			Audio.play("skill"))

func _purchase_asset(index: int) -> void:
	var asset: Dictionary = Catalog.config.assets[index]
	if not Game.asset_available(index) or Game.cash < int(asset.price) or asset.id in Game.owned:
		Game.buy_asset(index)
		return
	animate_action("新收藏 · " + str(asset.name), asset.kind, 2.0, func():
		if Game.buy_asset(index):
			burst(Vector2(640, 370), 50)
			show_toast("%s · 精神上限 +%d" % [asset.name, asset.spirit])
			Audio.play("big"))

func _upgrade() -> void:
	if Game.buy_upgrade():
		open_modal("")
		skill_flash = 0.8
		show_toast("聚财 Lv.%d · 今后所有新票奖金 ×%.1f！" % [Game.resonance,Catalog.config.resonance_factor])
		Audio.play("skill")

func open_modal(which: String) -> void:
	modal = which
	if not which.is_empty():
		particles.clear()
		skill_flash = 0.0
		toast_time = 0.0
	for child in modal_ui.get_children():
		modal_ui.remove_child(child)
		child.queue_free()
	if not which.is_empty():
		var shade := ColorRect.new()
		shade.size = Vector2(1280, 800)
		shade.color = Color(0.025, 0.07, 0.08, 0.82)
		modal_ui.add_child(shade)
		var panel := Control.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.draw.connect(_draw_modal)
		modal_ui.add_child(panel)
		make_button(modal_ui, Rect2(963, 146, 68, 40), "关闭", func(): open_modal(""), Color("924e44"), 18)
		match which:
			"life":
				for i in 4:
					var index: int = i
					var a: Dictionary = Catalog.config.activities[i]
					make_button(modal_ui, Rect2(838, 228 + i * 84, 170, 54), Catalog.money(a.cost), func(): _activity(index), Color("327773"), 18)
				make_button(modal_ui, Rect2(838, 567, 170, 54), "免费静坐", func(): animate_action("靠窗静坐 · 心慢慢安静", "tea", 4.0, func(): Game.rest(); show_toast("精神 +15。歇好了，慢慢来。")), Color("697b65"), 18)
			"assets":
				for row in 5:
					var index: int = row + asset_page * 5
					var a: Dictionary = Catalog.config.assets[index]
					var b: Button = make_button(modal_ui, Rect2(831, 224 + row * 83, 178, 56), "已收藏" if a.id in Game.owned else Catalog.money(a.price), func(): _purchase_asset(index), Color("ad7244"), 18)
					b.disabled = a.id in Game.owned
				make_button(modal_ui, Rect2(640, 645, 172, 35), "上一页" if asset_page else "下一页", func(): asset_page = 1 - asset_page; open_modal("assets"), Color("285c64"), 18)
			"upgrade":
				make_button(modal_ui, Rect2(676, 540, 288, 66), "聚财已满级" if Game.resonance >= 12 else "升级  " + Catalog.money(Catalog.config.upgrade_costs[Game.resonance]), _upgrade, Color("ac783c"), 24)
			"settings":
				make_button(modal_ui, Rect2(760, 240, 240, 50), "音效：关" if Game.muted else "音效：开", func(): Game.muted = not Game.muted; Game.commit(); open_modal("settings"), Color("285c64"), 18)
				make_button(modal_ui, Rect2(760, 315, 240, 50), "减少动态：开" if Game.reduced_motion else "减少动态：关", func(): Game.reduced_motion = not Game.reduced_motion; Game.commit(); open_modal("settings"), Color("285c64"), 18)
				make_button(modal_ui, Rect2(760, 390, 240, 50), "划过即刮：开" if Game.hover_scratch else "划过即刮：关", func(): Game.hover_scratch = not Game.hover_scratch; Game.commit(); open_modal("settings"), Color("285c64"), 18)
				make_button(modal_ui, Rect2(760, 534, 240, 50), "重新开始…", func(): open_modal("reset"), Color("944c44"), 18)
			"reset":
				make_button(modal_ui, Rect2(643, 476, 300, 60), "确认清空并重新开始", func(): Game.reset(); card.sync(); result_text = ""; open_modal(""), Color("944c44"), 18)
			"ending":
				make_button(modal_ui, Rect2(490, 569, 300, 62), "继续我的福运人生", func(): open_modal(""), Color("ad7244"), 24)
	_refresh()

func txt(at: Vector2, content: String, px: int = 18, color: Color = ART.CREAM, canvas: CanvasItem = self) -> void:
	canvas.draw_string(font, at, content, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color("142e35"))
	# Shop wall, aged tiles and a warm street-facing window.
	draw_rect(Rect2(0, 0, 1280, 180), Color("acb5a0"))
	for y in range(0, 180, 30):
		draw_line(Vector2(0,y), Vector2(1280,y), Color("99a694"), 2)
		for x in range((y / 30 % 2) * 32, 1280, 64):
			draw_line(Vector2(x,y), Vector2(x,y+30), Color("99a694"), 2)
	ART.box(self, Rect2(30, 24, 320, 122), Color("a4443c"), Color("682e2b"), 4)
	draw_rect(Rect2(38,32,304,106), ART.GOLD, false, 2)
	txt(Vector2(62, 86), "福 运 人 生", 36, Color("ffe4a8"))
	txt(Vector2(68, 120), "一枚硬币，一场好梦。", 18, Color("f4cf91"))
	ART.box(self, Rect2(385, 27, 282, 116), Color("254b52"), Color("647867"), 6)
	for i in 10:
		var h: int = 25 + (i * 17 % 56)
		draw_rect(Rect2(399 + i * 25, 132 - h, 20, h), Color("355b61"))
		for y in range(140 - h, 123, 12):
			draw_rect(Rect2(403 + i * 25, y, 5, 4), Color("aab795"))
	draw_line(Vector2(525,30), Vector2(525,141), Color("91a18b"), 5)
	draw_rect(Rect2(385,100,282,4), Color("91a18b"))
	ART.plant(self, Vector2(687, 94))
	ART.box(self, Rect2(758, 25, 477, 75), Color("163c40"), Color("687f6e"), 4)
	txt(Vector2(780, 51), "零钱包", 12, Color("a3c0ad"))
	txt(Vector2(780, 85), Catalog.money(Game.cash), 36, ART.GOLD)
	txt(Vector2(1090, 54), "福运存档", 12, Color("95b69e"))
	txt(Vector2(1072, 79), "已自动保存" if Game.last_save_ok else "保存失败", 12, ART.CREAM)
	txt(Vector2(772, 137), "街角体彩店  /  好运常在", 18, Color("254b45"))
	draw_rect(Rect2(0, 167, 1280, 13), Color("d0b086"))
	draw_rect(Rect2(0, 180, 1280, 5), Color("071e24"))
	# Ticket rack.
	ART.box(self, Rect2(22,196,250,486), Color("1c4147"), Color("0b252c"), 3)
	txt(Vector2(39,225), "今日票柜", 24)
	txt(Vector2(177,222), "即刮即兑", 12, Color("9abaae"))
	txt(Vector2(38,661), "累计奖金和张数决定新票解锁", 12, Color("91afa2"))
	# Wooden tabletop and green felt.
	ART.box(self, Rect2(289,227,653,437), Color("956544"), Color("462f27"), 6)
	for y in range(237, 661, 25):
		draw_line(Vector2(294,y),Vector2(937,y),Color("855737"),2)
	for i in 28:
		var x: int = 303 + (i * 147 % 610)
		var y: int = 238 + (i * 33 % 416)
		draw_rect(Rect2(x,y,12 + i % 9,2),Color("ad8058"))
	ART.box(self, Rect2(321,255,532,374), Color("28564f"), Color("bec39c"), 3)
	draw_rect(Rect2(330,264,514,356), Color("56796a"), false, 2)
	# Desk clutter: spare scratchers and a tea cup.
	for i in 3:
		ART.box(self,Rect2(865+i*3,290+i*5,45,78),Color("ad4b42"),ART.GOLD,2)
	txt(Vector2(877,330),"福",24,ART.GOLD)
	ART.box(self,Rect2(872,520,45,48),Color("c5d6b7"),Color("35574e"),3)
	draw_rect(Rect2(915,528,13,27),Color("9aaf93"),false,4)
	draw_rect(Rect2(878,521,32,7),Color("657854"))
	if not Game.reduced_motion:
		draw_line(Vector2(885,514),Vector2(890 + sin(elapsed)*3,499),Color("b5bba0"),3)
	# Table title and result.
	txt(Vector2(303,214), "刮 开 今 天 的 好 运", 18, Color("b6d1b6"))
	if not result_text.is_empty():
		txt(Vector2(358,250),result_text,24,ART.GOLD if Game.current.payout > 0 else Color("adbdb0"))
	# Wallet / ability ledger.
	ART.box(self,Rect2(967,196,286,486),Color("1c4147"),Color("0b252c"),3)
	txt(Vector2(988,227),Game.rank_name(),24,ART.GOLD)
	txt(Vector2(989,264),"精神力    %d / %d" % [Game.spirit,Game.max_spirit()],18)
	draw_rect(Rect2(990,278,242,14),Color("102c32"))
	draw_rect(Rect2(992,280,238*Game.spirit/Game.max_spirit(),10),Color("84c9b6"))
	txt(Vector2(989,317),"永久收益  ×%.2f" % Game.fortune(),18,Color("b8d1b5"))
	txt(Vector2(989,342),"已刮 %d 张    收藏 %d/10" % [Game.scratched,Game.owned.size()],12,Color("91afa2"))
	draw_line(Vector2(990,358),Vector2(1230,358),Color("456166"),2)
	txt(Vector2(990,377),"特殊能力",12,Color("91afa2"))
	if Game.luck_armed:
		txt(Vector2(991,650),"好运已就位  ·  下一张 +25%",12,ART.GOLD)
	elif Game.has_pending() and Game.current.seen:
		txt(Vector2(991,650),"透视：会中奖" if Game.current.payout > 0 else "透视：未中奖",18,ART.GOLD)
	elif Game.misses > 0:
		txt(Vector2(991,650),"未中 %d/4 · 随后必中奖" % Game.misses,12,Color("acc7b3"))
	else:
		txt(Vector2(991,650),"先透视，再决定是否加倍率。",12,Color("acc7b3"))
	var hint: String = "按住左键拖动硬币  ·  刮开每个银色区域"
	if Game.scratched >= 30: hint = "按住空格快速刮开  ·  B 再买一张同款"
	if Game.has_pending() and Game.current.boosted: hint = "本张奖金 ×3  ·  好运正在发生"
	txt(Vector2(345,651),hint,12,ART.CREAM)
	# Lower message rail.
	draw_rect(Rect2(0,692,1280,108),Color("0e282f"))
	if toast_time > 0:
		txt(Vector2(37,710),toast,12,ART.GOLD)
	else:
		txt(Vector2(37,710),"慢慢刮，慢慢富。下一站：" + next_goal(),12,Color("a9c2b2"))

func next_goal() -> String:
	var tier: int = Game.highest_tier()
	if tier < 4:
		var t: Dictionary = Catalog.tickets[tier+1]
		return "%s · 累计奖金 %s / %s，刮 %d / %d 张" % [t.name,Catalog.money(Game.earned),Catalog.money(t.unlock_earned),Game.scratched,t.unlock_scratched]
	return "全国首富 · 身家 %s / 1000亿，收藏 %d/10" % [Catalog.money(Game.net_worth()),Game.owned.size()]

func _draw_modal() -> void:
	var canvas: CanvasItem = modal_ui.get_child(1)
	ART.box(canvas,Rect2(220,123,840,576),Color("173b42"),ART.GOLD,3)
	var titles: Dictionary = {"life":"把日子过好，运气才会来","assets":"车房收藏 · 给梦想一个地址","upgrade":"聚财 · 让每一张票更值钱","stats":"成长手账","help":"第一次来？从这里开始。","settings":"慢慢来，按你的节奏","reset":"重新开始这段人生？","ending":"从街边小店，到全国首富"}
	txt(Vector2(249,179),titles.get(modal,""),24,ART.GOLD,canvas)
	canvas.draw_line(Vector2(247,199),Vector2(1030,199),Color("537169"),2)
	match modal:
		"life":
			for i in 4:
				var a: Dictionary = Catalog.config.activities[i]
				var y: int = 244 + i*84
				txt(Vector2(260,y),a.name,24,ART.CREAM,canvas)
				txt(Vector2(478,y),"精神全恢复" if a.restore > 9000 else "精神 +%d" % a.restore,18,Color("8ecab1"),canvas)
				txt(Vector2(262,y+26),a.description if Game.earned >= a.unlock else "累计奖金 %s 解锁" % Catalog.money(a.unlock),12,Color("97b9a8"),canvas)
			txt(Vector2(260,590),"靠窗静坐",24,ART.CREAM,canvas)
			txt(Vector2(478,590),"精神 +15",18,Color("8ecab1"),canvas)
			txt(Vector2(260,620),"也可以什么都不做，精神每秒自然恢复 0.4。",12,Color("97b9a8"),canvas)
		"assets":
			for row in 5:
				var i: int = row + asset_page*5
				var a: Dictionary = Catalog.config.assets[i]
				var y: int = 230 + row*83
				if a.kind == "car": ART.car(canvas,Vector2(256,y+6),Color("cb7352"),0.65)
				else: ART.house(canvas,Vector2(259,y),Color("bdac7e"),0.58)
				txt(Vector2(342,y+18),a.name,24,ART.CREAM,canvas)
				txt(Vector2(343,y+41),"精神上限 +%d  ·  财运加成 +%.0f%%" % [a.spirit,a.fortune*100],12,Color("a0c8af"),canvas)
				txt(Vector2(343,y+59),a.description if Game.asset_available(i) else "需上一件收藏 + 刮满 %d 张" % a.gate,12,Color("829f99"),canvas)
			txt(Vector2(264,670),"收藏 %d/10   ·   %d/2 页" % [Game.owned.size(),asset_page+1],12,Color("adc6b2"),canvas)
		"upgrade":
			txt(Vector2(273,259),"聚财 Lv.%d / 12" % Game.resonance,36,ART.CREAM,canvas)
			txt(Vector2(274,307),"所有新购彩票的奖金永久 ×%.1f" % Catalog.config.resonance_factor,24,ART.GOLD,canvas)
			txt(Vector2(275,349),"升级同时增加硬币刮擦范围，后期刮票更轻松。",18,Color("a8c9b4"),canvas)
			for i in 12:
				canvas.draw_rect(Rect2(278+i*57,399,43,58),ART.GOLD if i < Game.resonance else Color("2a555a"))
			txt(Vector2(276,514),"当前总收益 ×%.2f" % Game.fortune(),24,ART.CREAM,canvas)
			if Game.resonance < 12:
				txt(Vector2(276,558),"升级需刮满 %d 张" % Catalog.config.upgrade_gates[Game.resonance],18,Color("a8c9b4"),canvas)
			txt(Vector2(274,648),"已买下的彩票保留原奖金；升级从下一张生效。",12,Color("a8c9b4"),canvas)
		"stats":
			var rows: Array = [["当前身家",Catalog.money(Game.net_worth())],["累计彩票奖金",Catalog.money(Game.earned)],["累计刮票","%d 张" % Game.scratched],["车房收藏","%d / 10" % Game.owned.size()],["精神上限","%d" % Game.max_spirit()],["永久收益","×%.2f" % Game.fortune()]]
			for i in rows.size():
				txt(Vector2(277,252+i*49),rows[i][0],18,Color("a8c9b4"),canvas)
				txt(Vector2(740,252+i*49),rows[i][1],24,ART.GOLD,canvas)
			txt(Vector2(277,584),"终局：买齐车房，身家达到 1000 亿。",24,ART.CREAM,canvas)
			txt(Vector2(277,637),next_goal(),12,Color("a8c9b4"),canvas)
		"help":
			for i in help_lines.size(): txt(Vector2(254,239+i*40),help_lines[i],18 if i < 8 else 12,ART.CREAM,canvas)
		"settings":
			for row in [["刮擦与中奖的声音",273],["减少庆祝粒子与动画",347],["松开鼠标也能轻松刮票",422],["存档自动保存在本机",492],["清空存档需要再次确认",567]]:
				txt(Vector2(273,row[1]),row[0],18,ART.CREAM,canvas)
			txt(Vector2(273,646),"福运人生 v0.1.0 · 原创像素素材 · Godot 4.5.1",12,Color("97b9a8"),canvas)
		"reset":
			txt(Vector2(272,311),"零钱、技能、车房和所有进度将归零。",24,ART.CREAM,canvas)
			txt(Vector2(273,359),"如果还想保留这段人生，请点击右上角关闭。",18,Color("a8c9b4"),canvas)
		"ending":
			txt(Vector2(395,294),"全国首富",60,ART.GOLD,canvas)
			txt(Vector2(370,367),"一枚硬币，一场好梦。",24,ART.CREAM,canvas)
			txt(Vector2(369,418),"总身家 " + Catalog.money(Game.net_worth()),24,Color("a8c9b4"),canvas)
			txt(Vector2(369,460),"%d 张刮票，10 件梦想收藏。" % Game.scratched,18,ART.CREAM,canvas)
			txt(Vector2(369,500),"山海已在眼前，人生还在继续。",18,ART.CREAM,canvas)

func _draw_overlay() -> void:
	for particle in particles:
		cursor_layer.draw_rect(Rect2(particle.pos,Vector2.ONE*particle.size),particle.color)
	if skill_flash > 0 and not Game.reduced_motion and modal.is_empty():
		cursor_layer.draw_rect(Rect2(331,261,506,366),Color(0.94,0.83,0.43,skill_flash*0.8),false,4)
	if not modal.is_empty() and toast_time > 0:
		ART.box(cursor_layer,Rect2(239,711,802,40),Color("163a40"),ART.GOLD,2)
		txt(Vector2(257,737),toast,12,ART.GOLD,cursor_layer)
	if busy:
		cursor_layer.draw_rect(Rect2(0,0,1280,800),Color(0.03,0.08,0.10,0.85))
		ART.box(cursor_layer,Rect2(356,223,568,330),Color("234e53"),ART.GOLD,3)
		var p: float = clampf(animation_time/animation_duration,0,1)
		var offset: float = sin(elapsed*6)*4 if not Game.reduced_motion else 0.0
		if animation_kind == "ability":
			ART.coin(cursor_layer,Vector2(640,340+offset),2.2)
			for i in 6:
				var angle: float = i*TAU/6+elapsed*2
				cursor_layer.draw_rect(Rect2(Vector2(640,340)+Vector2(cos(angle),sin(angle))*82,Vector2(8,8)),ART.GOLD)
		elif animation_kind == "car" or animation_kind == "work":
			ART.car(cursor_layer,Vector2(532+offset,306),Color("d88858"),2.0)
		elif animation_kind == "home":
			ART.house(cursor_layer,Vector2(535,283),Color("c8b984"),2.0)
		elif animation_kind == "trip" or animation_kind == "sea":
			for i in 5:
				cursor_layer.draw_rect(Rect2(400,333+i*15,480,7),Color("428784"))
			cursor_layer.draw_circle(Vector2(640,302),30,ART.GOLD)
		elif animation_kind == "massage":
			cursor_layer.draw_rect(Rect2(512,364,250,24),Color("b1805d"))
			cursor_layer.draw_rect(Rect2(524,339,167,25),Color("a1c0a4"))
			cursor_layer.draw_rect(Rect2(692,332,38,31),Color("e5b485"))
			cursor_layer.draw_rect(Rect2(630+offset,310,16,30),Color("dfb488"))
			cursor_layer.draw_rect(Rect2(668-offset,310,16,30),Color("dfb488"))
		else:
			ART.plant(cursor_layer,Vector2(616,317+offset))
			txt(Vector2(493,293),"休息，是为了下一次好运。",12,ART.CREAM,cursor_layer)
		txt(Vector2(406,447),animation_title,24,ART.GOLD,cursor_layer)
		cursor_layer.draw_rect(Rect2(402,480,476,12),Color("122e36"))
		cursor_layer.draw_rect(Rect2(402,480,476*p,12),Color("9fc3a6"))
	ART.coin(cursor_layer,get_global_mouse_position(),0.72)

func _smoke() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://smoke-start.png")
	buy(0)
	use_skill(0)
	await get_tree().create_timer(0.7).timeout
	for i in card.cell_rects.size():
		var rect: Rect2 = card.cell_rects[i]
		for y in range(int(rect.position.y),int(rect.end.y),12):
			for x in range(int(rect.position.x),int(rect.end.x),12): card.scratch_at(Vector2(x,y))
	assert(Game.scratched == 1 and Game.cash == 120)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://smoke-win.png")
	open_modal("assets")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://smoke-assets.png")
	open_modal("life")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://smoke-life.png")
	open_modal("")
	Game.cash = 100000000
	Game.earned = 100000000
	Game.scratched = 150
	buy(4)
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://smoke-tier5.png")
	open_modal("")
	await get_tree().process_frame
	print("SMOKE PASSED: spatial scratching, skill, settlement, modal, screenshots")
	get_tree().quit()
