extends Node
## Transaction boundary for all gameplay; views never mutate the wallet.
signal changed
signal notice(message: String)
signal ticket_settled(payout: int, big: bool)
signal completed

var cash: int = 80
var spirit: float = 60.0
var earned: int = 0
var scratched: int = 0
var misses: int = 0
var resonance: int = 0
var owned: Array = []
var current: Dictionary = {}
var luck_armed: bool = false
var finished: bool = false
var muted: bool = false
var reduced_motion: bool = false
var hover_scratch: bool = false
var rng := RandomNumberGenerator.new()
var no_save: bool = false
var autosave_clock: float = 0.0
var work_cooldown: float = 0.0
var last_save_ok: bool = true

func _ready() -> void:
	Catalog.load_data()
	no_save = "--test" in OS.get_cmdline_user_args() or "--smoke" in OS.get_cmdline_user_args()
	rng.randomize()
	if not no_save:
		var saved: Dictionary = SaveStore.read_snapshot()
		if not saved.is_empty():
			restore(saved)
	get_tree().auto_accept_quit = false

func _process(delta: float) -> void:
	work_cooldown = maxf(0.0, work_cooldown - delta)
	spirit = minf(max_spirit(), spirit + delta * 0.4)
	autosave_clock += delta
	if autosave_clock >= 6.0:
		autosave_clock = 0.0
		save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		save()

func reset() -> void:
	cash = int(Catalog.config.initial_cash)
	spirit = float(Catalog.config.initial_spirit)
	earned = 0
	scratched = 0
	misses = 0
	resonance = 0
	owned.clear()
	current.clear()
	luck_armed = false
	finished = false
	work_cooldown = 0.0
	rng.randomize()
	commit()

func max_spirit() -> float:
	var result: float = float(Catalog.config.initial_spirit)
	for asset in Catalog.config.assets:
		if asset.id in owned:
			result += float(asset.spirit)
	return result

func fortune() -> float:
	var bonus: float = 1.0
	for asset in Catalog.config.assets:
		if asset.id in owned:
			bonus += float(asset.fortune)
	return pow(float(Catalog.config.resonance_factor), resonance) * bonus

func net_worth() -> int:
	var value: int = cash
	for asset in Catalog.config.assets:
		if asset.id in owned:
			value += int(asset.price)
	return value

func rank_name() -> String:
	if finished: return "全国首富"
	if net_worth() >= 1000000000: return "商界传奇"
	if net_worth() >= 10000000: return "城市新贵"
	if net_worth() >= 100000: return "小有身家"
	return "街坊新面孔"

func unlocked(tier: int) -> bool:
	if tier not in range(Catalog.tickets.size()): return false
	var t: Dictionary = Catalog.tickets[tier]
	return earned >= int(t.unlock_earned) and scratched >= int(t.unlock_scratched)

func highest_tier() -> int:
	for i in range(Catalog.tickets.size() - 1, -1, -1):
		if unlocked(i): return i
	return 0

func has_pending() -> bool:
	return not current.is_empty() and not bool(current.settled)

func untouched() -> bool:
	return has_pending() and not bool(current.get("started", false))

func start_scratching() -> void:
	if has_pending() and not bool(current.get("started", false)):
		current.started = true
		commit()

func buy_ticket(tier: int) -> bool:
	if has_pending(): return reject("先把桌上这张刮完。")
	if not unlocked(tier): return reject("达到累计奖金与刮票张数后解锁。")
	var price: int = int(Catalog.tickets[tier].price)
	if cash < price: return reject("零钱不够啦，去打工或换一张便宜票。")
	cash -= price
	current = Economy.roll(rng, tier, luck_armed, misses, fortune(), scratched == 0)
	luck_armed = false
	commit() # Outcome and RNG persisted before any reveal; reload cannot reroll.
	return true

func skill_unlocked(index: int) -> bool:
	var skill: Dictionary = Catalog.config.skills[index]
	return scratched >= int(skill.scratched) and max_spirit() >= float(skill.capacity)

func skill_error(index: int) -> String:
	if index not in range(3): return "没有这个技能。"
	var skill: Dictionary = Catalog.config.skills[index]
	if not skill_unlocked(index): return "解锁需要 %d 张刮票、精神上限 %d。" % [skill.scratched, skill.capacity]
	if spirit < float(skill.cost): return "精神力不足，去生活菜单休息一下。"
	if index == 1:
		if has_pending(): return "好运来要在买下一张票之前使用。"
		if luck_armed: return "好运已经就位，去选一张彩票。"
	else:
		if not untouched(): return "购买后、刮开前才能使用这个技能。"
		if index == 0 and current.seen: return "这张票已经看穿了。"
		if index == 2 and current.boosted: return "这一张已经加倍过了。"
	return ""

func use_skill(index: int) -> bool:
	var error: String = skill_error(index)
	if not error.is_empty(): return reject(error)
	var skill: Dictionary = Catalog.config.skills[index]
	match index:
		0:
			current.seen = true
		1:
			luck_armed = true
		2:
			current.boosted = true
			current.payout = int(current.payout) * 3
			for i in current.cells.size():
				current.cells[i] = int(current.cells[i]) * 3
	spirit -= float(skill.cost)
	commit()
	return true

func reveal_cell(index: int) -> void:
	if not has_pending() or index not in range(current.cells.size()) or current.revealed[index]: return
	current.started = true
	current.revealed[index] = true
	if not false in current.revealed:
		current.settled = true # Mark before signals to make settlement idempotent.
		var payout: int = int(current.payout)
		cash += payout
		earned += payout
		scratched += 1
		misses = 0 if payout > 0 else misses + 1
		commit()
		ticket_settled.emit(payout, float(current.multiplier) >= 15.0)
	else:
		commit()

func buy_upgrade() -> bool:
	var costs: Array = Catalog.config.upgrade_costs
	if resonance >= costs.size(): return reject("聚财已经满级。")
	if scratched < int(Catalog.config.upgrade_gates[resonance]): return reject("再多刮几张，就能掌握更强的聚财。")
	if cash < int(costs[resonance]): return reject("资金不足，先攒一攒。")
	cash -= int(costs[resonance])
	resonance += 1
	commit()
	return true

func asset_available(index: int) -> bool:
	if index not in range(Catalog.config.assets.size()): return false
	var asset: Dictionary = Catalog.config.assets[index]
	return scratched >= int(asset.gate) and (index == 0 or Catalog.config.assets[index - 1].id in owned)

func buy_asset(index: int) -> bool:
	if index not in range(Catalog.config.assets.size()): return false
	var asset: Dictionary = Catalog.config.assets[index]
	if asset.id in owned: return reject("已经收入收藏。")
	if not asset_available(index): return reject("按顺序收藏，并达到刮票张数要求。")
	if cash < int(asset.price): return reject("还差一点资金，这个梦想先记下来。")
	cash -= int(asset.price)
	owned.append(asset.id)
	spirit = minf(max_spirit(), spirit + float(asset.spirit))
	commit()
	return true

func activity(index: int) -> bool:
	if index not in range(Catalog.config.activities.size()): return false
	var item: Dictionary = Catalog.config.activities[index]
	if earned < int(item.unlock): return reject("累计奖金达到 %s 后解锁。" % Catalog.money(item.unlock))
	if spirit >= max_spirit() - 0.1: return reject("精神饱满，暂时不用休息。")
	if cash < int(item.cost): return reject("资金不足，也可以静坐免费恢复。")
	cash -= int(item.cost)
	spirit = minf(max_spirit(), spirit + float(item.restore))
	commit()
	return true

func work_pay() -> int:
	return 25 * int(pow(5.0, highest_tier()))

func work() -> bool:
	if work_cooldown > 0.0: return reject("稍微歇一会儿，再接下一单。")
	cash += work_pay()
	spirit = minf(max_spirit(), spirit + 3.0)
	work_cooldown = 6.0
	commit()
	return true

func rest() -> void:
	spirit = minf(max_spirit(), spirit + 15.0)
	commit()

func reject(message: String) -> bool:
	notice.emit(message)
	return false

func commit() -> void:
	if not finished and owned.size() == Catalog.config.assets.size() and net_worth() >= int(Catalog.config.goal):
		finished = true
		completed.emit()
	save()
	changed.emit()

func snapshot() -> Dictionary:
	return {"cash":cash,"spirit":spirit,"earned":earned,"scratched":scratched,"misses":misses,"resonance":resonance,"owned":owned.duplicate(),"current":current.duplicate(true),"luck_armed":luck_armed,"finished":finished,"rng_state":str(rng.state),"rng_seed":str(rng.seed),"muted":muted,"reduced_motion":reduced_motion,"hover_scratch":hover_scratch,"work_cooldown":work_cooldown}

func restore(data: Dictionary) -> void:
	cash = maxi(0, int(data.cash))
	earned = maxi(0, int(data.earned))
	scratched = maxi(0, int(data.scratched))
	misses = clampi(int(data.misses), 0, int(Catalog.config.pity_losses))
	resonance = clampi(int(data.resonance), 0, Catalog.config.upgrade_costs.size())
	owned = data.owned.duplicate()
	spirit = clampf(float(data.spirit), 0.0, max_spirit())
	current = data.current.duplicate(true)
	if not current.is_empty() and not current.has("started"):
		current.started = true in current.revealed
	luck_armed = bool(data.get("luck_armed", false))
	finished = bool(data.get("finished", false))
	muted = bool(data.get("muted", false))
	reduced_motion = bool(data.get("reduced_motion", false))
	hover_scratch = bool(data.get("hover_scratch", false))
	work_cooldown = clampf(float(data.get("work_cooldown", 0.0)), 0.0, 6.0)
	rng.seed = int(data.get("rng_seed", "1"))
	rng.state = int(data.get("rng_state", "1"))
	changed.emit()

func save() -> void:
	if not no_save:
		last_save_ok = SaveStore.write_snapshot(snapshot())
