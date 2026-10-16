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
var activity_page: int = 0
var busy: bool = false
var animation_time: float = 0.0
var animation_duration: float = 1.0
var animation_title: String = ""
var animation_kind: String = ""
var animation_callback: Callable
var toast: String = "道盟催债，命悬一线。先刮开门红，五张后去破境引气！"
var toast_time: float = 8.0
var result_text: String = ""
var result_big: bool = false
var win_flash: float = 0.0
var last_payout: int = 0
var particles: Array = []
var fx_rng := RandomNumberGenerator.new()
var elapsed: float = 0.0
var skill_flash: float = 0.0
var danger_flash: float = 0.0
var help_lines: Array = [
	"01  你欠下道盟 1000 亿灵债。刮符票，购灵契，修仙还债。",
	"02  各票规则独立：同号、号码、龙舟、积分、极限、阵法等。",
	"03  骷髅按每张票抽取，最多一个；前 5 张教学票没有劫印。",
	"04  累积 3 个骷髅即失败，致命票不兑奖；天赋可提高上限。",
	"05  失败后按累计奖金与灵契件数结算道行，升级轮回天赋。",
	"06  精神不会自动恢复。主动吐纳、灵茶、药浴、闭关可恢复。",
	"07  炼气解锁祈运与代刮，筑基可改命，元婴可召票面头奖。",
	"08  灵车强化倍化，洞府解锁自动施法与付费修炼。",
	"09  化神、集齐 10 件灵契并解除五重债契后飞升。",
	"1–8 技能 / 空格快刮 / B 再买。虚构单机，资金仅限游戏内。"
]

func _ready() -> void:
	font = load("res://assets/fonts/fusion-pixel.otf")
	var game_theme:=Theme.new()
	game_theme.default_font=font
	game_theme.default_font_size=18
	theme=game_theme
	fx_rng.randomize()
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	card = CardView.new()
	card.position = Vector2(322, 260)
	card.size = Vector2(570, 408)
	add_child(card)
	card.scraped.connect(_debris)
	for i in Catalog.tickets.size():
		var index: int = i
		var button: Button = make_button(ui, Rect2(36, 235 + i * 52, 222, 49), "", func(): buy(index), Color(Catalog.tickets[i].color))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 18)
		ticket_buttons.append(button)
	for i in Catalog.config.skills.size():
		var index: int = i
		var button: Button = make_button(ui, Rect2(989, 341 + i * 37, 247, 34), "", func(): use_skill(index), Color("285c64"))
		button.add_theme_font_size_override("font_size", 18)
		skill_buttons.append(button)
	for entry in [["修炼", "life", 24], ["灵契", "assets", 160], ["破境 / 还债", "upgrade", 296], ["轮回天赋", "talents", 432], ["傀儡", "auto", 568], ["手账", "stats", 704]]:
		var which: String = entry[1]
		make_button(ui, Rect2(entry[2], 720, 128, 54), entry[0], func(): open_modal(which), Color("285c64"), 18)
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
	Game.ticket_changed.connect(_ticket_changed)
	Game.automation_event.connect(show_toast)
	Game.notice.connect(show_toast)
	Game.ticket_settled.connect(_settled)
	Game.run_ended.connect(func(): call_deferred("open_modal", "run_end"))
	Game.skull_revealed.connect(_skull_feedback)
	_refresh()
	if Game.run_over: open_modal("run_end")
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

func _ticket_changed() -> void:
	card.sync()
	if Game.has_pending(): result_text = ""

func _refresh() -> void:
	for i in ticket_buttons.size():
		var t: Dictionary = Catalog.tickets[i]
		var available: bool = Game.unlocked(i)
		ticket_buttons[i].text = "%s%s\n%s · %s" % [t.name,"" if available else " [锁]",Catalog.money(t.price),t.subtitle]
		ticket_buttons[i].disabled = busy or Game.run_over or not modal.is_empty() or Game.has_pending() or not available or Game.cash<int(t.price)
		ticket_buttons[i].tooltip_text = "%s\n基础中奖率 %d%% · 每张骷髅 %.2f%%\n解锁：%s / 累奖 %s / %d 张" % [t.description,int(t.chance*100),Game.skull_chance(i)*100,Catalog.config.realms[int(t.realm)].name,Catalog.money(t.unlock_earned),t.unlock_scratched]
	for i in skill_buttons.size():
		var skill: Dictionary = Catalog.config.skills[i]
		var extra: String = "-%d" % Game.skill_cost(i) if Game.skill_unlocked(i) else "锁"
		if i==3 and Game.skill_unlocked(i): extra = "暂停" if Game.auto_enabled else "启动"
		if i==7 and Game.skill_unlocked(i): extra="-%d/%d次" % [Game.skill_cost(i),1+Game.talent_level("ward")-Game.wards_used]
		skill_buttons[i].text = "%s %s · %s" % [skill.key,skill.name,extra]
		skill_buttons[i].disabled = busy or Game.run_over or not modal.is_empty()
		skill_buttons[i].tooltip_text = "%s\n解锁境界：%s" % [skill.description,Catalog.config.realms[int(skill.realm)].name]
	card.disabled = busy or Game.run_over or not modal.is_empty()
	Game.automation_paused = card.disabled
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	toast_time = maxf(0, toast_time - delta)
	skill_flash = maxf(0, skill_flash - delta)
	danger_flash=maxf(0,danger_flash-delta)
	win_flash = maxf(0,win_flash-delta)
	work_button.text = "打工  +%s" % Catalog.money(Game.work_pay()) if Game.work_cooldown <= 0 else "收工休息  %ds" % ceili(Game.work_cooldown)
	work_button.disabled = busy or Game.run_over or not modal.is_empty() or Game.work_cooldown > 0
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
			KEY_4: use_skill(3)
			KEY_5: use_skill(4)
			KEY_6: use_skill(5)
			KEY_7: use_skill(6)
			KEY_8: use_skill(7)
			KEY_B: buy(int(Game.current.get("tier", 0)))

func buy(tier: int) -> void:
	if busy or not modal.is_empty(): return
	if Game.auto_enabled: Game.stop_auto("切回手动购票。")
	if Game.buy_ticket(tier):
		result_text = ""
		result_big = false
		card.sync()
		Audio.play("click")
		if not Game.reduced_motion:
			card.position.y = 250
			create_tween().tween_property(card, "position:y", 260.0, 0.17).set_trans(Tween.TRANS_QUAD)

func use_skill(index: int) -> void:
	if busy or not modal.is_empty(): return
	var error: String = Game.skill_error(index)
	if not error.is_empty():
		show_toast(error)
		return
	if index==3:
		Game.use_skill(index)
		show_toast("自动票种："+str(Catalog.tickets[Game.auto_tier].name)+"；到自动设置调整策略。")
		return
	Audio.play("skill")
	animate_action(Catalog.config.skills[index].name,"ability",0.55,func(): _commit_skill(index))

func _commit_skill(index: int) -> void:
	if Game.use_skill(index):
		skill_flash = 0.65
		Audio.play("skill")
		card.queue_redraw()
		if index==0: show_toast("望气："+Catalog.money(Game.current.payout)+(" · 有骷髅！可用替劫符。" if int(Game.current.get("skull_index",-1))>=0 else " · 未见劫印，可改运或倍化。"))
		elif index==2: show_toast("奖金 ×%d！本张预计 %s。" % [Game.boost_factor(),Catalog.money(Game.current.payout)])
		elif index==4: show_toast("改运成功！现在按票面规则可得 "+Catalog.money(Game.current.payout))
		else: show_toast(Catalog.config.skills[index].description)

func _settled(payout: int, big: bool) -> void:
	result_big = big
	last_payout = payout
	win_flash = 1.0 if big and payout>0 else 0.0
	result_text = ("大奖来了！  +" if big else "中奖啦  +") + Catalog.money(payout) if payout > 0 else "谢谢惠顾 · 还有下一次好运"
	if payout > 0:
		Audio.play("big" if big else "win")
		burst(Vector2(582, 337), 90 if big else 24)
	if Game.scratched==5: show_toast("五张历练完成，去「破境」引气！炼气解锁祈运与代刮。")

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
	animate_action("坊市帮工 · 运送灵材", "work", 2.0, func():
		if Game.work():
			show_toast("灵材送达！报酬 +%s。" % Catalog.money(Game.work_pay()))
			Audio.play("win"))

func _activity(index: int) -> void:
	var item: Dictionary = Catalog.config.activities[index]
	if Game.cash < Game.activity_cost(index) or not Game.activity_available(index):
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
	if which.is_empty() and Game.run_over: which="run_end"
	modal = which
	if not which.is_empty():
		win_flash = 0.0
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
				for row in 3:
					var index: int = row+activity_page*3
					make_button(modal_ui,Rect2(838,228+row*98,170,54),Catalog.money(Game.activity_cost(index)),func(): _activity(index),Color("327773"),18)
				make_button(modal_ui,Rect2(838,541,170,54),"免费吐纳",func(): animate_action("盘膝吐纳 · 主动调息","meditate",4.0,func(): Game.rest(); show_toast("吐纳完成，精神 +%d。" % Game.rest_amount())),Color("697b65"),18)
				make_button(modal_ui,Rect2(830,630,178,38),"上一页" if activity_page else "进阶修炼 →",func(): activity_page=1-activity_page; open_modal("life"),Color("285c64"),18)

			"assets":
				for row in 5:
					var index: int = row + asset_page * 5
					var a: Dictionary = Catalog.config.assets[index]
					var b: Button = make_button(modal_ui, Rect2(831, 224 + row * 83, 178, 56), "已收藏" if a.id in Game.owned else Catalog.money(a.price), func(): _purchase_asset(index), Color("ad7244"), 18)
					b.disabled = a.id in Game.owned
				make_button(modal_ui, Rect2(640, 645, 172, 35), "上一页" if asset_page else "下一页", func(): asset_page = 1 - asset_page; open_modal("assets"), Color("285c64"), 18)
			"upgrade":
				make_button(modal_ui,Rect2(780,274,230,52),"境界圆满" if Game.realm==5 else "突破 "+Catalog.money(Game.breakthrough_cost()),_breakthrough,Color("7a638a"),18)
				make_button(modal_ui,Rect2(780,419,230,52),"聚财圆满" if Game.resonance>=12 else "聚财 "+Catalog.money(Catalog.config.upgrade_costs[Game.resonance]),_upgrade,Color("ac783c"),18)
				make_button(modal_ui,Rect2(780,563,230,52),"债契已清" if Game.debt_stage==5 else "偿还 "+Catalog.money(Game.debt_payment()),func():
					if Game.repay_debt(): Audio.play("big"); open_modal("upgrade"),Color("327773"),18)
			"talents":
				for i in Catalog.config.talents.size():
					var index: int=i
					var t: Dictionary = Catalog.config.talents[i]
					var level: int = Game.talent_level(t.id)
					var caption: String = "%s %d/%d\n%s\n%s" % [t.name,level,t.costs.size(),talent_summary(t.id),"已圆满" if level==t.costs.size() else "%d 道行" % t.costs[level]]
					var button: Button = make_button(modal_ui,Rect2(252+int(t.column)*258,253+int(t.row)*91,242,76),caption,func(): Game.buy_talent(index); open_modal("talents"),Color("456d66") if level>0 else Color("344852"),18)
					button.tooltip_text=t.description+("\n前置："+talent_name(t.prerequisite)+" %d 级" % t.requires if t.prerequisite!="" else "\n根天赋，无前置")
				if Game.run_over:
					make_button(modal_ui,Rect2(780,641,228,38),"开启下一世 →",_next_run,Color("a57c45"),18)
				else:
					make_button(modal_ui,Rect2(780,641,228,38),"主动轮回…",func(): open_modal("retire"),Color("7e5455"),18)
			"run_end":
				make_button(modal_ui,Rect2(279,590,340,58),"升级轮回天赋",func(): open_modal("talents"),Color("7a638a"),24)
				make_button(modal_ui,Rect2(665,590,340,58),"带着传承，再启一世",_next_run,Color("a57c45"),18)
			"retire":
				make_button(modal_ui,Rect2(650,500,350,58),"确认结算并入轮回",func(): Game.retire_run(),Color("7e5455"),18)

			"auto":
				for i in Catalog.tickets.size():
					var tier: int = i
					var label: String = ("● " if Game.auto_tier==i else "")+str(Catalog.tickets[i].name)
					var b: Button = make_button(modal_ui,Rect2(252+i%4*193,244+int(i/4)*46,180,39),label,func(): Game.set_auto_option("tier",tier); open_modal("auto"),Color(Catalog.tickets[i].color),18)
					b.disabled = not Game.unlocked(i)
				for row in 3:
					var key: String = ["luck","combo","recover"][row]
					var enabled: bool = bool(Game.get("auto_"+key))
					make_button(modal_ui,Rect2(848,354+row*57,158,42),"已开启" if enabled else "开启",func(): Game.set_auto_option(key,not enabled); open_modal("auto"),Color("327773"),18)
				make_button(modal_ui,Rect2(817,536,189,42),"升级 " + Catalog.money(Catalog.config.automation_costs[Game.auto_level]) if Game.auto_level<3 else "效率已满级",func(): Game.buy_auto_upgrade(); open_modal("auto"),Color("ac783c"),18)
				make_button(modal_ui,Rect2(689,596,120,40),"备用 -1",func(): Game.set_auto_option("reserve",Game.auto_reserve-1); open_modal("auto"),Color("285c64"),18)
				make_button(modal_ui,Rect2(829,596,177,40),"备用 +1",func(): Game.set_auto_option("reserve",Game.auto_reserve+1); open_modal("auto"),Color("285c64"),18)
			"settings":
				make_button(modal_ui, Rect2(760, 240, 240, 50), "音效：关" if Game.muted else "音效：开", func(): Game.muted = not Game.muted; Game.commit(); open_modal("settings"), Color("285c64"), 18)
				make_button(modal_ui, Rect2(760, 315, 240, 50), "减少动态：开" if Game.reduced_motion else "减少动态：关", func(): Game.reduced_motion = not Game.reduced_motion; Game.commit(); open_modal("settings"), Color("285c64"), 18)
				make_button(modal_ui, Rect2(760, 390, 240, 50), "划过即刮：开" if Game.hover_scratch else "划过即刮：关", func(): Game.hover_scratch = not Game.hover_scratch; Game.commit(); open_modal("settings"), Color("285c64"), 18)
				make_button(modal_ui, Rect2(760, 534, 240, 50), "清空全部存档…", func(): open_modal("reset"), Color("944c44"), 18)
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
	txt(Vector2(62, 86), "福 运 仙 途", 36, Color("ffe4a8"))
	txt(Vector2(68, 120), "刮尽尘缘，逆命登仙。", 18, Color("f4cf91"))
	ART.box(self, Rect2(385, 27, 282, 116), Color("254b52"), Color("647867"), 6)
	for i in 10:
		var h: int = 25 + (i * 17 % 56)
		draw_rect(Rect2(399 + i * 25, 132 - h, 20, h), Color("355b61"))
		for y in range(140 - h, 123, 12):
			draw_rect(Rect2(403 + i * 25, y, 5, 4), Color("aab795"))
	draw_line(Vector2(525,30), Vector2(525,141), Color("91a18b"), 5)
	draw_rect(Rect2(385,100,282,4), Color("91a18b"))
	# Mountains and a seated cultivator beyond the modern shop window.
	for i in 4:
		var x: float=397+i*60
		draw_colored_polygon(PackedVector2Array([Vector2(x,132),Vector2(x+32,65+i%2*18),Vector2(x+76,132)]),Color("557976") if i%2==0 else Color("3d636a"))
	ART.cultivator(self,Vector2(692,110),.85)
	ART.box(self, Rect2(758, 25, 477, 75), Color("163c40"), Color("687f6e"), 4)
	txt(Vector2(780, 51), "灵钱 · 本世", 12, Color("a3c0ad"))
	txt(Vector2(780, 85), Catalog.money(Game.cash), 36, ART.GOLD)
	txt(Vector2(1090, 54), "轮回玉简", 12, Color("95b69e"))
	txt(Vector2(1072, 79), "已自动保存" if Game.last_save_ok else "保存失败", 12, ART.CREAM)
	txt(Vector2(385,160),"清心 %d · 轻身 %d · 悟道 %d · 洞天 %d" % [Game.buffs.focus,Game.buffs.flow,Game.buffs.inspired,Game.buffs.holiday],12,Color("37594e"))
	txt(Vector2(772, 137), "道盟灵债  "+Catalog.money(int(Catalog.config.goal)-Game.debt_paid()), 18, Color("254b45"))
	draw_rect(Rect2(0, 167, 1280, 13), Color("d0b086"))
	draw_rect(Rect2(0, 180, 1280, 5), Color("071e24"))
	# Ticket rack.
	ART.box(self, Rect2(22,196,250,486), Color("1c4147"), Color("0b252c"), 3)
	txt(Vector2(39,225), "坊市符票", 24)
	txt(Vector2(177,222), "即刮即兑", 12, Color("9abaae"))
	txt(Vector2(38,661), "悬停查看玩法、境界与每张劫印概率", 12, Color("91afa2"))
	# Wooden tabletop and green felt.
	ART.box(self, Rect2(289,247,653,436), Color("956544"), Color("462f27"), 6)
	for y in range(257, 679, 25):
		draw_line(Vector2(294,y),Vector2(937,y),Color("855737"),2)
	for i in 28:
		var x: int = 303 + (i * 147 % 610)
		var y: int = 238 + (i * 33 % 416)
		draw_rect(Rect2(x,y,12 + i % 9,2),Color("ad8058"))
	ART.box(self, Rect2(310,250,594,427), Color("28564f"), Color("bec39c"), 3)
	draw_rect(Rect2(316,256,582,414), Color("56796a"), false, 2)
	# Table title and result.
	txt(Vector2(303,214), "一 念 改 命 ， 一 刮 求 仙", 18, Color("b6d1b6"))
	if not result_text.is_empty():
		txt(Vector2(305,243),result_text,18,ART.GOLD if Game.current.payout > 0 else Color("adbdb0"))
	# Persistent run danger, separate from a ticket's reward.
	for i in Game.skull_limit(): ART.skull(self,Vector2(778+i*26,209),.65,Color("df7975") if i<Game.skulls else Color("59756b"))
	txt(Vector2(658,220),"劫印 %d/%d" % [Game.skulls,Game.skull_limit()],12,Color("e5b19b"))
	# Wallet / ability ledger.
	ART.box(self,Rect2(967,196,286,486),Color("1c4147"),Color("0b252c"),3)
	txt(Vector2(988,227),Game.rank_name(),24,ART.GOLD)
	txt(Vector2(989,264),"精神力    %d / %d" % [Game.spirit,Game.max_spirit()],18)
	draw_rect(Rect2(990,278,242,14),Color("102c32"))
	draw_rect(Rect2(992,280,238*Game.spirit/Game.max_spirit(),10),Color("84c9b6"))
	txt(Vector2(989,316),"财运 ×%.1f · 倍化 ×%d" % [Game.fortune(),Game.boost_factor()],18,Color("b8d1b5"))
	txt(Vector2(991,664),"祈运 %d / 聚宝 %d / 天命 %s" % [Game.luck_charges,Game.chain_left,"就位" if Game.burst_armed else str(maxi(0,Game.burst_ready_at-Game.scratched))],12,ART.GOLD)
	var status: String = Game.auto_status if Game.auto_enabled else "手动刮票 · 空格快刮 · 1–8 技能 · B 再买"
	txt(Vector2(303,698-10),status,12,Color("b3d7c8"))
	# Lower message rail.
	draw_rect(Rect2(0,692,1280,108),Color("0e282f"))
	if toast_time > 0:
		txt(Vector2(37,710),toast,12,ART.GOLD)
	else:
		txt(Vector2(37,710),"修行路标：" + next_goal(),12,Color("a9c2b2"))

func next_goal() -> String:
	if Game.realm==0: return "炼气：刮满 5 张、累奖 ¥50、突破费用 ¥50；点击「破境 / 还债」。"
	var tier: int = Game.highest_tier()
	if tier < Catalog.tickets.size()-1:
		var t: Dictionary = Catalog.tickets[tier+1]
		return "%s · %s境 / 累奖 %s / %s / 刮 %d/%d 张" % [t.name,Catalog.config.realms[int(t.realm)].name,Catalog.money(Game.earned),Catalog.money(t.unlock_earned),Game.scratched,t.unlock_scratched]
	return "飞升：化神 / 灵契 %d/10 / 债契 %d/5" % [Game.owned.size(),Game.debt_stage]

func _draw_modal() -> void:
	var canvas: CanvasItem = modal_ui.get_child(1)
	ART.box(canvas,Rect2(220,123,840,576),Color("173b42"),ART.GOLD,3)
	var titles: Dictionary = {"life":"修炼行录 · 精神须由活动恢复","assets":"灵契图录 · 灵车与洞府","upgrade":"破境登仙 · 五重债契","talents":"轮回天赋 · 传承永存","run_end":"本世结算 · 因果归于轮回","retire":"主动轮回 · 结算本世历练","stats":"修行手账","auto":"念力工坊 · 自动购票与技能策略","help":"第一次来？从这里开始。","settings":"慢慢来，按你的节奏","reset":"重新开始这段人生？","ending":"从街边小店，到全国首富"}
	txt(Vector2(249,179),titles.get(modal,""),24,ART.GOLD,canvas)
	canvas.draw_line(Vector2(247,199),Vector2(1030,199),Color("537169"),2)
	match modal:
		"life":
			for row in 3:
				var i: int = row+activity_page*3
				var a: Dictionary = Catalog.config.activities[i]
				var y: int=246+row*98
				txt(Vector2(260,y),a.name,24,ART.CREAM,canvas)
				txt(Vector2(478,y),"恢复 %d%% 上限" % mini(100,int(a.restore_ratio*(1.0+.1*Game.count_kind("home"))*100)),18,Color("8ecab1"),canvas)
				txt(Vector2(262,y+26),a.description,12,Color("97b9a8"),canvas)
				txt(Vector2(262,y+47),"已解锁" if Game.activity_available(i) else "需 %s 境 / %d %s" % [Catalog.config.realms[int(a.realm)].name,a.assets,"灵车" if a.kind=="car" else "洞府"],12,ART.GOLD,canvas)
			txt(Vector2(260,565),"盘膝吐纳",24,ART.CREAM,canvas)
			txt(Vector2(478,565),"精神 +%d" % Game.rest_amount(),18,Color("8ecab1"),canvas)
			txt(Vector2(260,603),"免费主动调息 4 秒；洞府与天赋提高恢复量。",12,Color("97b9a8"),canvas)
			txt(Vector2(260,654),"无被动恢复 · 灵车减免费用 · 洞府强化活动",12,Color("97b9a8"),canvas)

		"assets":
			for row in 5:
				var i: int = row + asset_page*5
				var a: Dictionary = Catalog.config.assets[i]
				var y: int = 230 + row*83
				if a.kind == "car": ART.car(canvas,Vector2(256,y+6),Color("cb7352"),0.65)
				else: ART.house(canvas,Vector2(259,y),Color("bdac7e"),0.58)
				txt(Vector2(342,y+18),a.name,24,ART.CREAM,canvas)
				txt(Vector2(343,y+41),"上限 +%d · 财运 +%.0f%% · %s" % [a.spirit,a.fortune*100,"倍化 +2 / 修炼 -8%" if a.kind=="car" else "活动恢复 +10%"],12,Color("a0c8af"),canvas)
				txt(Vector2(343,y+59),a.description if Game.asset_available(i) else "需上一件收藏 + 刮满 %d 张" % a.gate,12,Color("829f99"),canvas)
			txt(Vector2(264,670),"收藏 %d/10   ·   %d/2 页" % [Game.owned.size(),asset_page+1],12,Color("adc6b2"),canvas)
		"upgrade":
			txt(Vector2(263,244),"%s → %s" % [Catalog.config.realms[Game.realm].name,Catalog.config.realms[mini(Game.realm+1,5)].name],30,ART.GOLD,canvas)
			if Game.realm<5:
				var r: Dictionary=Catalog.config.realms[Game.realm+1]
				txt(Vector2(263,283),"累奖 %s / 灵契 %d / 历练 %d 张" % [Catalog.money(r.earned),r.assets,r.scratched],18,ART.CREAM,canvas)
				txt(Vector2(263,316),r.description,12,Color("a8c9b4"),canvas)
				txt(Vector2(263,341),"现有：%s / %d 件 / %d 张" % [Catalog.money(Game.earned),Game.owned.size(),Game.scratched],12,ART.GOLD,canvas)
			else: txt(Vector2(263,296),"境界已圆满。集齐灵契，偿尽灵债，方可飞升。",18,ART.CREAM,canvas)
			canvas.draw_line(Vector2(254,368),Vector2(1020,368),Color("537169"),1)
			txt(Vector2(263,406),"聚财诀 %d/12 · 财运 ×%.2f" % [Game.resonance,Game.fortune()],24,ART.CREAM,canvas)
			txt(Vector2(263,443),"每级所有新票奖金 ×1.2，并增加硬币范围。",18,Color("a8c9b4"),canvas)
			if Game.resonance<12: txt(Vector2(263,474),"需炼气境 / 下级需历练 %d 张" % Catalog.config.upgrade_gates[Game.resonance],12,ART.GOLD,canvas)
			canvas.draw_line(Vector2(254,501),Vector2(1020,501),Color("537169"),1)
			txt(Vector2(263,541),"债契 %d/5 · 已还 %s" % [Game.debt_stage,Catalog.money(Game.debt_paid())],24,ART.GOLD,canvas)
			txt(Vector2(263,578),"每解除一重，所有符票劫印概率降低 3%。",18,ART.CREAM,canvas)
			txt(Vector2(263,614),"下一重需 %s 境界" % Catalog.config.realms[mini(Game.debt_stage+1,5)].name,12,Color("a8c9b4"),canvas)
			txt(Vector2(263,666),"已购票保留原结果；突破与升级从下一张生效。",12,Color("a8c9b4"),canvas)
		"talents":
			txt(Vector2(252,227),"可用道行 %d · 总获 %d · %s" % [Game.meta_points,Game.meta_total,"本世已结算，点击节点升级" if Game.run_over else "本世结束后才能升级"],18,ART.CREAM,canvas)
			for t in Catalog.config.talents:
				if str(t.prerequisite).is_empty(): continue
				var parent: Dictionary = talent_data(t.prerequisite)
				var x: float = 373+int(t.column)*258
				var color: Color=ART.GOLD if Game.talent_level(t.prerequisite)>=int(t.requires) else Color("49676c")
				if int(t.row)-int(parent.row)==1:
					canvas.draw_line(Vector2(x,253+int(parent.row)*91+76),Vector2(x,253+int(t.row)*91),color,3)
				else:
					var top: float=291+int(parent.row)*91
					var bottom: float=291+int(t.row)*91
					canvas.draw_polyline(PackedVector2Array([Vector2(x+121,top),Vector2(x+129,top),Vector2(x+129,bottom),Vector2(x+121,bottom)]),color,2)
			txt(Vector2(252,665),"悬停查看效果与前置 · 命 / 财 / 灵 三脉",12,Color("a8c9b4"),canvas)
		"run_end":
			var report: Dictionary = Game.last_run
			txt(Vector2(274,267),"债尽道成 · 飞升！" if Game.finished else str(report.get("reason","本世结束")),36,ART.GOLD,canvas)
			txt(Vector2(274,312),"第 %d 世  /  骷髅 %d/%d  /  历练 %d 张" % [Game.run_number,Game.skulls,report.get("limit",3),Game.scratched],18,ART.CREAM,canvas)
			txt(Vector2(274,363),"累计彩票奖金  "+Catalog.money(Game.earned),24,ART.CREAM,canvas)
			txt(Vector2(274,405),"灵契收藏  %d 件  ·  债契已解 %d/5" % [Game.owned.size(),Game.debt_stage],24,ART.CREAM,canvas)
			txt(Vector2(274,465),"道行 +%d     可用点数 %d" % [report.get("points",0),Game.meta_points],36,ART.GOLD,canvas)
			txt(Vector2(274,512),"道行按奖金的对数成长与灵契数量结算，已自动保存。",18,Color("a8c9b4"),canvas)
			txt(Vector2(274,547),"本世钱财、境界、灵契重置；轮回天赋与未用道行永久保留。",12,Color("a8c9b4"),canvas)
		"retire":
			txt(Vector2(274,287),"预计获得 %d 道行" % Game.prestige_reward(),30,ART.GOLD,canvas)
			txt(Vector2(274,341),"结束本世，保留天赋与道行；钱财、境界和灵契归零。",18,ART.CREAM,canvas)
			txt(Vector2(274,383),"至少刮完 10 张，且桌上不能有未完成的票。",18,Color("a8c9b4"),canvas)

		"stats":
			var rows: Array = [["当前身家",Catalog.money(Game.net_worth())],["累计彩票奖金",Catalog.money(Game.earned)],["已刮 / 自动","%d / %d 张" % [Game.scratched,Game.auto_tickets]],["车房收藏","%d / 10" % Game.owned.size()],["单张最高奖金",Catalog.money(Game.biggest_win)],["永久收益","×%.2f" % Game.fortune()]]
			for i in rows.size():
				txt(Vector2(277,252+i*49),rows[i][0],18,Color("a8c9b4"),canvas)
				txt(Vector2(740,252+i*49),rows[i][1],24,ART.GOLD,canvas)
			txt(Vector2(277,584),"自动已兑 %s · 改运加倍增收 %s" % [Catalog.money(Game.auto_earned),Catalog.money(Game.skill_profit)],18,ART.CREAM,canvas)
			txt(Vector2(277,637),next_goal(),12,Color("a8c9b4"),canvas)
		"help":
			for i in help_lines.size(): txt(Vector2(254,239+i*40),help_lines[i],18 if i < 8 else 12,ART.CREAM,canvas)
		"auto":
			txt(Vector2(254,229),"自动票种（菜单打开时暂停；关闭后继续）",18,ART.CREAM,canvas)
			var labels: Array = ["自动祈运 · 每三张补充必中","望气 → 替劫 → 改命 → 倍化 · 一座洞府","自动付费修炼 · 两座洞府"]
			for i in 3: txt(Vector2(256,380+i*57),labels[i],18,ART.CREAM,canvas)
			txt(Vector2(255,554),"念力效率 Lv.%d / 3 · 单格 %.2f 秒" % [Game.auto_level,Game.automation_interval()],18,ART.GOLD,canvas)
			if Game.auto_level<3:
				txt(Vector2(257,576),"下级需 %d 张票 / %d 套房" % [Catalog.config.automation_gates[Game.auto_level],Catalog.config.automation_homes[Game.auto_level]],12,Color("a8c9b4"),canvas)
			txt(Vector2(257,622),"保留 %d 张票钱 · 不足自动停购" % Game.auto_reserve,18,ART.CREAM,canvas)
			txt(Vector2(257,673),"代刮消耗精神；自动修炼会付费。劫印满额立刻停止，重进需手动启动。",12,Color("a8c9b4"),canvas)
		"settings":
			for row in [["刮擦与中奖的声音",273],["减少庆祝粒子与动画",347],["松开鼠标也能轻松刮票",422],["存档自动保存在本机",492],["清空存档需要再次确认",567]]:
				txt(Vector2(273,row[1]),row[0],18,ART.CREAM,canvas)
			txt(Vector2(273,646),"福运人生 v0.3.0 · 原创像素素材 · Godot 4.5.1",12,Color("97b9a8"),canvas)
		"reset":
			txt(Vector2(272,311),"清空本世、道行与全部轮回天赋。",24,ART.CREAM,canvas)
			txt(Vector2(273,359),"如果还想保留这段人生，请点击右上角关闭。",18,Color("a8c9b4"),canvas)
		"ending":
			txt(Vector2(395,294),"全国首富",60,ART.GOLD,canvas)
			txt(Vector2(370,367),"刮尽尘缘，逆命登仙。",24,ART.CREAM,canvas)
			txt(Vector2(369,418),"总身家 " + Catalog.money(Game.net_worth()),24,Color("a8c9b4"),canvas)
			txt(Vector2(369,460),"%d 张刮票，10 件梦想收藏。" % Game.scratched,18,ART.CREAM,canvas)
			txt(Vector2(369,500),"山海已在眼前，人生还在继续。",18,ART.CREAM,canvas)

func _draw_overlay() -> void:
	if danger_flash>0 and not Game.reduced_motion and modal.is_empty():
		cursor_layer.draw_rect(Rect2(292,198,648,483),Color(.85,.27,.32,danger_flash),false,8)
	for particle in particles:
		cursor_layer.draw_rect(Rect2(particle.pos,Vector2.ONE*particle.size),particle.color)
	if skill_flash > 0 and not Game.reduced_motion and modal.is_empty():
		cursor_layer.draw_rect(Rect2(316,253,582,421),Color(0.94,0.83,0.43,skill_flash*0.8),false,4)
	if not modal.is_empty() and toast_time > 0:
		ART.box(cursor_layer,Rect2(239,711,802,40),Color("163a40"),ART.GOLD,2)
		txt(Vector2(257,737),toast,12,ART.GOLD,cursor_layer)
	if win_flash>0 and not Game.reduced_motion and modal.is_empty() and not busy:
		var shade := Color("193f46"); shade.a = minf(1.0,win_flash*3.0)
		ART.box(cursor_layer,Rect2(351,404,510,116),shade,ART.GOLD,3)
		txt(Vector2(381,442),"神技爆奖！" if Game.current.get("boosted",false) else "大奖来了！",24,ART.GOLD,cursor_layer)
		txt(Vector2(381,491),"+"+Catalog.money(last_payout),36,ART.CREAM,cursor_layer)
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
			ART.cultivator(cursor_layer,Vector2(640,334+offset),2.0)
			txt(Vector2(493,293),"吐故纳新，道法自然。",12,ART.CREAM,cursor_layer)
		txt(Vector2(406,447),animation_title,24,ART.GOLD,cursor_layer)
		cursor_layer.draw_rect(Rect2(402,480,476,12),Color("122e36"))
		cursor_layer.draw_rect(Rect2(402,480,476*p,12),Color("9fc3a6"))
	ART.coin(cursor_layer,get_global_mouse_position(),0.72)

func _smoke() -> void:
	Game.reset(); open_modal("")
	await _capture("start")
	buy(0); use_skill(0)
	await get_tree().create_timer(.7).timeout
	for rect in card.cell_rects:
		for y in range(int(rect.position.y),int(rect.end.y),12):
			for x in range(int(rect.position.x),int(rect.end.x),12): card.scratch_at(Vector2(x,y))
	assert(Game.scratched==1 and Game.cash==120)
	await _capture("win")
	Game.cash=200000000000; Game.earned=200000000000; Game.scratched=1500; Game.realm=5
	for asset in Catalog.config.assets: Game.owned.append(asset.id)
	Game.spirit=Game.max_spirit()
	for tier in Catalog.tickets.size():
		open_modal("")
		buy(tier)
		Game.current.board=TicketRules.make_board(Catalog.tickets[tier],4,Game.rng)
		Game.current.cells=Game.current.board.cells; Game.current.skull_index=-1
		Economy.recalculate(Game.current); card.sync()
		Game.spirit=Game.max_spirit(); Game.use_skill(0)
		await _capture("ticket-%d" % tier)
		for i in Game.current.cells.size(): Game.reveal_cell(i)
		await _capture("revealed-%d" % tier)
	for page in ["assets","life","auto","upgrade","talents","help"]:
		open_modal(page); await _capture(page)
	activity_page=1; open_modal("life"); await _capture("life-advanced"); activity_page=0
	open_modal("")
	Game.set_auto_option("tier",2); Game.set_auto_option("combo",true); Game.set_auto_option("recover",true)
	Game.use_skill(3)
	var before: int=Game.scratched
	await get_tree().create_timer(5).timeout
	assert(Game.scratched>before,"Rendered automation must buy, scratch, and settle")
	Game.stop_auto("验收")
	if Game.has_pending():
		for i in Game.current.cells.size(): Game.reveal_cell(i)
	buy(2); Game.current.skull_index=0; Game.current.skull_blocked=false; Game.current.skull_seen=false
	Game.spirit=Game.max_spirit(); Game.use_skill(0)
	await _capture("skull-preview")
	Game.skulls=2; Game.reveal_cell(0)
	await get_tree().process_frame
	assert(Game.run_over)
	await _capture("run-end")
	open_modal("talents"); Game.buy_talent(0); Game.buy_talent(0); Game.buy_talent(1); open_modal("talents")
	await _capture("talents-purchased")
	_next_run(); assert(Game.skull_limit()==4 and Game.run_number==2)
	await _capture("reborn")
	Audio.stop_all()
	await get_tree().create_timer(.1).timeout
	print("SMOKE PASSED: physical scratching, 8 rules, cultivation modals, live automation, fatal skull, talents, rebirth")
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

func _capture(id: String) -> void:
	win_flash = 0.0
	particles.clear()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://v03-"+id+".png")

func _skull_feedback(blocked: bool) -> void:
	Audio.play("skill" if blocked else "skull")
	danger_flash=0.0 if blocked else .8
	show_toast("替劫符燃尽，躲过此劫。" if blocked else "骷髅劫印！%d/%d · 可先查看轮回天赋规划下一世。" % [Game.skulls,Game.skull_limit()])

func talent_data(id: String) -> Dictionary:
	for t in Catalog.config.talents:
		if t.id==id: return t
	return {}

func talent_name(id: String) -> String:
	return str(talent_data(id).get("name",""))

func _next_run() -> void:
	if Game.begin_next_run():
		card.sync(); result_text=""; open_modal("")
		show_toast("第 %d 世 · 宿世天赋已生效。" % Game.run_number)

func _breakthrough() -> void:
	var error: String=Game.breakthrough_error()
	if not error.is_empty(): show_toast(error); return
	animate_action("破境 · "+str(Catalog.config.realms[Game.realm+1].name),"ability",1.8,func():
		if Game.breakthrough():
			Audio.play("big"); burst(Vector2(640,340),70)
			show_toast(Catalog.config.realms[Game.realm].description))

func talent_summary(id: String) -> String:
	return {"guard":"劫印率 -10%/级","lives":"骷髅上限 +1/级","ward":"替劫符 +1次/世","merit":"结算道行 +20%/级","cash":"开局金钱 +100/级","fortune":"奖金 +15%/级","break":"突破费用 -15%/级","yield":"资产财运 +20%/级","spirit":"精神上限 +15/级","focus":"技能耗神 -5%/级","rest":"吐纳恢复 +10/级","speed":"代刮速度 +15%/级"}.get(id,"")
