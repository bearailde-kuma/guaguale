extends Node
## Transaction boundary for all gameplay; views never mutate the wallet.
signal changed
signal notice(message: String)
signal ticket_settled(payout: int, big: bool)
signal completed
signal run_ended
signal skull_revealed(blocked: bool)
signal ticket_changed
signal automation_event(message: String)

var realm: int = 0
var skulls: int = 0
var wards_used: int = 0
var debt_stage: int = 0
var run_over: bool = false
var run_number: int = 1
var meta_points: int = 0
var meta_total: int = 0
var talents: Dictionary = {}
var last_run: Dictionary = {}
var rest_cooldown: float = 0.0
var cash: int = 80
var spirit: float = 60.0
var earned: int = 0
var scratched: int = 0
var misses: int = 0
var resonance: int = 0
var owned: Array = []
var unlocked_ids: Array = [] # Grandfathered unlocks migrated from earlier releases.
var current: Dictionary = {}
var luck_armed: bool = false # v0.1 migration alias
var luck_charges: int = 0
var chain_left: int = 0
var burst_armed: bool = false
var burst_ready_at: int = 0
var buffs: Dictionary = {"focus":0,"flow":0,"inspired":0,"holiday":0}
var auto_enabled: bool = false
var automation_paused: bool = false
var auto_tier: int = 0
var auto_level: int = 0
var auto_reserve: int = 3
var auto_luck: bool = false
var auto_combo: bool = false
var auto_recover: bool = false
var auto_clock: float = 0.0
var auto_wait: float = 0.0
var auto_status: String = "尚未启动"
var auto_tickets: int = 0
var auto_earned: int = 0
var skill_profit: int = 0
var biggest_win: int = 0
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
	rest_cooldown = maxf(0.0, rest_cooldown-delta) # Spirit only changes through explicit activities.
	automation_tick(delta)
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
	talents.clear()
	meta_points=0; meta_total=0; run_number=1; last_run.clear()
	_reset_run()

func _reset_run() -> void:
	realm=0; skulls=0; wards_used=0; debt_stage=0; run_over=false; rest_cooldown=0.0
	cash = int(Catalog.config.initial_cash)+int(talent_bonus("cash"))
	spirit = float(Catalog.config.initial_spirit)+talent_bonus("spirit")
	earned = 0
	scratched = 0
	misses = 0
	resonance = 0
	owned.clear()
	unlocked_ids.clear()
	current.clear()
	luck_armed = false
	luck_charges = 0
	chain_left = 0
	burst_armed = false
	burst_ready_at = 0
	buffs = {"focus":0,"flow":0,"inspired":0,"holiday":0}
	auto_enabled = false
	auto_tier = 0
	auto_level = 0
	auto_reserve = 3
	auto_luck = false
	auto_combo = false
	auto_recover = false
	auto_clock = 0.0
	auto_wait = 0.0
	auto_tickets = 0
	auto_earned = 0
	skill_profit = 0
	biggest_win = 0
	finished = false
	work_cooldown = 0.0
	rng.randomize()
	commit()

func max_spirit() -> float:
	var result: float = float(Catalog.config.initial_spirit)+talent_bonus("spirit")+20*realm
	for asset in Catalog.config.assets:
		if asset.id in owned:
			result += float(asset.spirit)
	return result

func fortune() -> float:
	var bonus: float = 1.0
	for asset in Catalog.config.assets:
		if asset.id in owned:
			bonus += float(asset.fortune)*(1.0+talent_bonus("yield"))
	return pow(float(Catalog.config.resonance_factor), resonance)*bonus*float(Catalog.config.realm_fortune[realm])*(1.0+talent_bonus("fortune"))

func net_worth() -> int:
	var value: int = cash
	for asset in Catalog.config.assets:
		if asset.id in owned:
			value += int(asset.price)
	return value

func rank_name() -> String:
	return "飞升 · 债尽道成" if finished else str(Catalog.config.realms[realm].name)+" · 第 %d 世" % run_number

func unlocked(tier: int) -> bool:
	if tier not in range(Catalog.tickets.size()): return false
	var t: Dictionary = Catalog.tickets[tier]
	if t.id in unlocked_ids: return true
	return earned >= int(t.unlock_earned) and scratched >= int(t.unlock_scratched) and realm>=int(t.realm)

func highest_tier() -> int:
	for i in range(Catalog.tickets.size() - 1, -1, -1):
		if unlocked(i): return i
	return 0

func has_pending() -> bool:
	return not run_over and not current.is_empty() and not bool(current.settled)

func untouched() -> bool:
	return has_pending() and not bool(current.get("started", false))

func start_scratching() -> void:
	if has_pending() and not bool(current.get("started", false)):
		current.started = true
		commit()

func count_kind(kind: String) -> int:
	var count: int = 0
	for asset in Catalog.config.assets:
		if asset.id in owned and asset.kind == kind: count += 1
	return count

func regen_rate() -> float:
	return 0.0 # Kept for API compatibility. No passive or offline recovery.

func boost_factor() -> int:
	return 6+count_kind("car")*2

func skill_cost(index: int) -> int:
	var focused: bool = bool(current.get("focused",false)) if has_pending() else int(buffs.focus)>0
	return maxi(1,ceili(float(Catalog.config.skills[index].cost)*(0.75 if focused else 1.0)*(1.0-talent_bonus("focus"))))

func buy_ticket(tier: int) -> bool:
	if run_over: return reject("本世已结束，请在轮回天赋中开启下一世。")
	if has_pending(): return reject("先把桌上这张刮完。")
	if not unlocked(tier): return reject("达到境界、累计奖金与刮票张数后解锁。")
	var price: int = int(Catalog.tickets[tier].price)
	if cash < price: return reject("零钱不够啦，去打工或换一张便宜票。")
	cash -= price
	current = Economy.roll(rng,tier,luck_charges>0,misses,fortune(),scratched==0,burst_armed)
	current.risk_chance = 0.0 if scratched<int(Catalog.config.skull_grace) else skull_chance(tier)
	current.skull_index = rng.randi_range(0,current.cells.size()-1) if scratched>=int(Catalog.config.skull_grace) and rng.randf()<skull_chance(tier) else -1
	current.forfeited = false
	current.skull_seen = false
	current.skull_blocked = false
	current.focused = int(buffs.focus)>0
	current.flow = int(buffs.flow)>0
	current.effect = 3.0 if int(buffs.holiday)>0 else (2.0 if int(buffs.inspired)>0 else 1.0)
	current.chain_factor = 7-chain_left if chain_left>0 else 1
	current.skill_factor = int(current.chain_factor)
	current.burst = burst_armed
	for key in buffs: buffs[key] = maxi(0,int(buffs[key])-1)
	luck_charges = maxi(0,luck_charges-1)
	luck_armed = luck_charges>0
	chain_left = maxi(0,chain_left-1)
	burst_armed = false
	Economy.recalculate(current)
	current.original_payout = int(current.payout)
	auto_clock = 0.0
	commit() # Persist outcome and RNG before any reveal.
	ticket_changed.emit()
	return true

func skill_unlocked(index: int) -> bool:
	return index in range(Catalog.config.skills.size()) and realm>=int(Catalog.config.skills[index].realm)

func skill_error(index: int) -> String:
	if run_over: return "本世已结束。前往轮回天赋。"
	if index not in range(Catalog.config.skills.size()): return "没有这个技能。"
	if index == 3 and auto_enabled: return ""
	var skill: Dictionary = Catalog.config.skills[index]
	if not skill_unlocked(index): return "突破到「%s」后解锁。" % Catalog.config.realms[int(skill.realm)].name
	if index == 3: return ""
	if spirit < skill_cost(index): return "精神力不足，主动吐纳或参加修炼活动。"
	if index in [1,5,6]:
		if has_pending(): return "这个技能在购买下一张彩票之前使用。"
		if index == 1 and luck_charges>0: return "还有 %d 张好运票，先用完。" % luck_charges
		if index == 5 and chain_left>0: return "聚宝连锁还剩 %d 张。" % chain_left
		if index == 6 and (burst_armed or scratched<burst_ready_at): return "爆发充能还需 %d 张。" % maxi(0,burst_ready_at-scratched)
	else:
		if not untouched(): return "购买后、刮开前才能使用这个技能。"
		if index == 0 and current.seen: return "这张票已经看穿了。"
		if index == 2 and current.boosted: return "这一张已经加倍过了。"
		if index == 2 and current.seen and int(current.payout)==0: return "这张是空奖；先用点石成金改运。"
		if index == 7:
			if not current.seen: return "先用望气术确认劫印。"
			if int(current.get("skull_index",-1))<0 or current.get("skull_blocked",false): return "这张没有待化解的骷髅。"
			if wards_used>=1+int(talent_bonus("ward")): return "本世替劫符已耗尽；轮回后恢复。"
		if index == 4:
			if not current.seen: return "先用望气术确认票面，再发动改运。"
			if current.get("transmuted",false): return "每张只能改运一次。"
			if current.board.rule == "legacy" or current.board.rule not in ["match3","numbers","dragon"]+MysticRules.RULES: return "旧版已购票保留原结果；下一张可使用改运。"
			if int(current.payout)>0: return "这张已经中奖，留精神给加倍吧。"
	return ""

func use_skill(index: int) -> bool:
	var error: String = skill_error(index)
	if not error.is_empty(): return reject(error)
	if index == 3:
		auto_enabled = not auto_enabled
		auto_status = "自动运行中" if auto_enabled else "手动暂停"
		auto_clock = 0.0
		commit()
		return true
	var cost: int = skill_cost(index)
	match index:
		0: current.seen = true
		1:
			luck_charges = 3
			luck_armed = true
		2:
			current.boosted = true
			current.skill_factor = int(current.skill_factor)*boost_factor()
			Economy.recalculate(current)
		4:
			current.transmuted = true
			current.before_alchemy = int(current.payout)
			if current.board.rule == "dragon":
				for cell in current.board.cells:
					if cell.op == "*" and int(cell.n)==0: cell.n = 2
			else:
				current.board = TicketRules.make_board(Catalog.tickets[int(current.tier)],2,rng)
				current.cells = current.board.cells
			Economy.recalculate(current)
			ticket_changed.emit()
		5: chain_left = 5
		6:
			burst_armed = true
			burst_ready_at = scratched+18
		7:
			current.skull_blocked = true
			wards_used += 1
	spirit -= cost
	commit()
	return true

func reveal_cell(index: int) -> void:
	if not has_pending() or index not in range(current.cells.size()) or current.revealed[index]: return
	current.started = true
	current.revealed[index] = true
	if index==int(current.get("skull_index",-1)) and not current.get("skull_seen",false):
		current.skull_seen = true
		var blocked: bool = bool(current.get("skull_blocked",false))
		if not blocked: skulls+=1
		skull_revealed.emit(blocked)
		if skulls>=skull_limit():
			current.forfeited=true
			_end_run(false,"劫印噬命")
			return # A fatal card never pays, including a fatal last cell.
	if not false in current.revealed:
		Economy.recalculate(current)
		current.settled = true # Mark before signals to make settlement idempotent.
		var payout: int = int(current.payout)
		cash += payout
		earned += payout
		scratched += 1
		misses = 0 if payout > 0 else misses + 1
		biggest_win = maxi(biggest_win,payout)
		skill_profit += maxi(0,payout-int(current.get("original_payout",payout)))
		if bool(current.get("auto_paid",false)):
			auto_tickets += 1
			auto_earned += payout
		auto_wait = 1.25 if float(current.multiplier)>=float(Catalog.tickets[int(current.tier)].jackpot) else 0.65
		commit()
		ticket_settled.emit(payout, float(current.multiplier) >= 24.0 or (current.boosted and payout > 0))
	else:
		commit()

func buy_upgrade() -> bool:
	if realm<1: return reject("先突破炼气，再修习聚财诀。")
	if run_over: return reject("本世已结束，请开启下一世。")
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
	if run_over: return reject("本世已结束，请开启下一世。")
	if index not in range(Catalog.config.assets.size()): return false
	var asset: Dictionary = Catalog.config.assets[index]
	if asset.id in owned: return reject("已经收入收藏。")
	if not asset_available(index): return reject("按顺序收藏，并达到刮票张数要求。")
	if cash < int(asset.price): return reject("还差一点资金，这个梦想先记下来。")
	cash -= int(asset.price)
	owned.append(asset.id)

	commit()
	return true

func activity_cost(index: int) -> int:
	var item: Dictionary = Catalog.config.activities[index]
	var base: float = maxf(float(item.cost),float(Catalog.tickets[highest_tier()].price)*float(item.price_factor))
	return maxi(1,ceili(base*(1.0-count_kind("car")*0.08)))

func activity(index: int) -> bool:
	if run_over: return reject("本世已结束，请开启下一世。")
	if index not in range(Catalog.config.activities.size()): return false
	var item: Dictionary = Catalog.config.activities[index]
	if not activity_available(index): return reject("需 %s 境界与 %d 件对应灵契。" % [Catalog.config.realms[int(item.realm)].name,item.assets])
	if spirit >= max_spirit()-0.1 and int(buffs[item.buff])>=int(item.charges): return reject("精神与该活动增益都已充满。")
	var cost: int = activity_cost(index)
	if cash < cost: return reject("资金不足，也可以静坐免费恢复。")
	cash -= cost
	spirit = minf(max_spirit(),spirit+max_spirit()*float(item.restore_ratio)*(1.0+.1*count_kind("home")))
	buffs[item.buff] = int(item.charges) # Refresh, never infinitely stack charges.
	if item.id=="sword": buffs.focus=12
	if item.id=="ritual": buffs.focus=24; buffs.flow=24
	commit()
	return true

func automation_interval() -> float:
	var flow: float = 1.5 if bool(current.get("flow",false)) else 1.0
	return float(Catalog.config.automation_intervals[auto_level])/((1.0+count_kind("car")*0.12)*flow*(1.0+talent_bonus("speed")))

func set_auto_option(key: String, value: Variant) -> bool:
	match key:
		"tier":
			if not unlocked(int(value)): return reject("先解锁这个票种。")
			auto_tier = int(value)
		"reserve": auto_reserve = clampi(int(value),1,10)
		"luck": auto_luck = bool(value)
		"combo":
			if count_kind("home")<1: return reject("买下第一座洞府后解锁自动技能组合。")
			auto_combo = bool(value)
		"recover":
			if count_kind("home")<2: return reject("买下第二座洞府后解锁自动修炼续航。")
			auto_recover = bool(value)
		_: return false
	commit()
	return true

func buy_auto_upgrade() -> bool:
	if run_over: return reject("本世已结束，请开启下一世。")
	if auto_level>=Catalog.config.automation_costs.size(): return reject("念力效率已满级。")
	if scratched<int(Catalog.config.automation_gates[auto_level]) or count_kind("home")<int(Catalog.config.automation_homes[auto_level]): return reject("刮票张数或洞府收藏不足。")
	var cost: int = int(Catalog.config.automation_costs[auto_level])
	if cash<cost: return reject("资金不足。")
	cash -= cost
	auto_level += 1
	commit()
	return true

func stop_auto(reason: String) -> void:
	auto_enabled = false
	auto_status = reason
	commit()
	notice.emit(reason)

func automation_tick(delta: float) -> void:
	if not auto_enabled or automation_paused or run_over: return
	if auto_wait>0:
		auto_wait = maxf(0.0,auto_wait-delta)
		return
	var cost: int = skill_cost(3)
	var wants_recovery: bool = spirit<float(cost) or (auto_combo and spirit<maxf(36.0,max_spirit()*0.25))
	if wants_recovery and auto_recover and count_kind("home")>=2:
		for i in range(Catalog.config.activities.size()-1,-1,-1):
			var a: Dictionary = Catalog.config.activities[i]
			var reserve: int = int(Catalog.tickets[auto_tier].price)*(auto_reserve+1)
			if activity_available(i) and cash>=activity_cost(i)+reserve:
				activity(i)
				auto_wait = float(a.duration)
				auto_status = "自动休息 · "+str(a.name)
				automation_event.emit(auto_status)
				return
	if not has_pending():
		var price: int = int(Catalog.tickets[auto_tier].price)
		if cash<price*(auto_reserve+1):
			stop_auto("自动暂停：已到 %d 张票的备用金线。" % auto_reserve)
			return
		if spirit<cost:
			auto_status = "精神耗尽 · 请主动修炼或开启自动修炼"
			return
		if auto_luck and luck_charges==0 and skill_unlocked(1) and spirit>=skill_cost(1)+cost+4: use_skill(1)
		if not buy_ticket(auto_tier):
			stop_auto("自动暂停：购票条件不足。")
			return
	if not bool(current.get("auto_paid",false)):
		cost = skill_cost(3)
		if spirit<cost:
			auto_status = "精神耗尽 · 修炼后继续 / 可手动刮完"
			return
		spirit -= cost
		current.auto_paid = true
		commit()
	if not bool(current.get("auto_prepared",false)):
		current.auto_prepared = true
		if untouched() and auto_combo and count_kind("home")>=1:
			if not current.seen and skill_error(0).is_empty(): use_skill(0)
			if current.seen:
				if skill_error(7).is_empty(): use_skill(7)
				if int(current.payout)==0 and skill_error(4).is_empty(): use_skill(4)
				if int(current.payout)>0 and skill_error(2).is_empty(): use_skill(2)
		start_scratching()
	auto_status = "自动刮票 · "+str(Catalog.tickets[int(current.tier)].name)
	auto_clock += delta
	if auto_clock>=automation_interval():
		auto_clock = 0.0 # Never generate unbounded catch-up loops after a stalled frame.
		for i in current.revealed.size():
			if not current.revealed[i]:
				reveal_cell(i)
				break

func work_pay() -> int:
	return maxi(25,int(Catalog.tickets[highest_tier()].price)*2)

func work() -> bool:
	if run_over: return reject("本世已结束，请开启下一世。")
	if work_cooldown > 0.0: return reject("稍微歇一会儿，再接下一单。")
	cash += work_pay()
	work_cooldown = 6.0
	commit()
	return true

func rest() -> bool:
	if run_over or rest_cooldown>0: return false
	spirit = minf(max_spirit(),spirit+rest_amount())
	rest_cooldown=4.0
	commit()
	return true

func reject(message: String) -> bool:
	notice.emit(message)
	return false

func commit() -> void:
	if not run_over and debt_stage==Catalog.config.debt_seals.size() and owned.size()==Catalog.config.assets.size() and realm==Catalog.config.realms.size()-1:
		_end_run(true,"债尽道成")
		return
	save()
	changed.emit()

func snapshot() -> Dictionary:
	var data: Dictionary = {"cash":cash,"spirit":spirit,"earned":earned,"scratched":scratched,"misses":misses,"resonance":resonance,"owned":owned.duplicate(),"current":current.duplicate(true),"luck_armed":luck_armed,"finished":finished,"rng_state":str(rng.state),"rng_seed":str(rng.seed),"muted":muted,"reduced_motion":reduced_motion,"hover_scratch":hover_scratch,"work_cooldown":work_cooldown}
	for key in ["luck_charges","chain_left","burst_armed","burst_ready_at","auto_tier","auto_level","auto_reserve","auto_luck","auto_combo","auto_recover","auto_tickets","auto_earned","skill_profit","biggest_win","realm","skulls","wards_used","debt_stage","run_over","run_number","meta_points","meta_total","rest_cooldown"]: data[key] = get(key)
	data.version=SaveStore.VERSION
	data.talents=talents.duplicate()
	data.last_run=last_run.duplicate(true)
	data.buffs = buffs.duplicate()
	data.unlocked_ids = unlocked_ids.duplicate()
	return data

func restore(data: Dictionary) -> void:
	data = SaveStore.migrate(data)
	talents=data.get("talents",{}).duplicate()
	last_run=data.get("last_run",{}).duplicate(true)
	for key in ["realm","skulls","wards_used","debt_stage","run_number","meta_points","meta_total"]: set(key,int(data.get(key,1 if key=="run_number" else 0)))
	run_over=bool(data.get("run_over",false))
	rest_cooldown=clampf(float(data.get("rest_cooldown",0)),0,4)
	cash = maxi(0,int(data.cash))
	earned = maxi(0,int(data.earned))
	scratched = maxi(0,int(data.scratched))
	misses = clampi(int(data.misses),0,int(Catalog.config.pity_losses))
	resonance = clampi(int(data.resonance),0,Catalog.config.upgrade_costs.size())
	owned = data.owned.duplicate()
	unlocked_ids = data.get("unlocked_ids",[]).duplicate()
	spirit = clampf(float(data.spirit),0.0,max_spirit())
	current = data.current.duplicate(true)
	if not current.is_empty():
		current.cells = current.board.cells
		Economy.recalculate(current)
	luck_charges = clampi(int(data.get("luck_charges",0)),0,3)
	luck_armed = luck_charges>0
	chain_left = clampi(int(data.get("chain_left",0)),0,5)
	burst_armed = bool(data.get("burst_armed",false))
	burst_ready_at = maxi(0,int(data.get("burst_ready_at",0)))
	buffs = data.get("buffs",{"focus":0,"flow":0,"inspired":0,"holiday":0}).duplicate()
	for key in ["focus","flow","inspired","holiday"]: buffs[key] = clampi(int(buffs.get(key,0)),0,24)
	auto_tier = clampi(int(data.get("auto_tier",0)),0,Catalog.tickets.size()-1)
	auto_level = clampi(int(data.get("auto_level",0)),0,Catalog.config.automation_costs.size())
	auto_reserve = clampi(int(data.get("auto_reserve",3)),1,10)
	for key in ["auto_luck","auto_combo","auto_recover"]: set(key,bool(data.get(key,false)))
	for key in ["auto_tickets","auto_earned","skill_profit","biggest_win"]: set(key,maxi(0,int(data.get(key,0))))
	auto_enabled = false # Reopening a save never starts spending without player input.
	auto_clock = 0.0
	auto_wait = 0.0
	finished = bool(data.get("finished",false))
	muted = bool(data.get("muted",false))
	reduced_motion = bool(data.get("reduced_motion",false))
	hover_scratch = bool(data.get("hover_scratch",false))
	work_cooldown = clampf(float(data.get("work_cooldown",0.0)),0.0,6.0)
	rng.seed = int(data.get("rng_seed","1"))
	rng.state = int(data.get("rng_state","1"))
	changed.emit()
	ticket_changed.emit()

func save() -> void:
	if not no_save: last_save_ok = SaveStore.write_snapshot(snapshot())

# Cultivation and reincarnation are transactions, independent of presentation.
func talent_level(id: String) -> int:
	return int(talents.get(id,0))

func skull_limit() -> int:
	return int(Catalog.config.skull_limit)+int(talent_bonus("lives"))

func skull_chance(tier: int) -> float:
	return float(Catalog.tickets[tier].skull_chance)*(1.0-talent_bonus("guard"))*(1.0-.03*debt_stage)

func rest_amount() -> int:
	return 20+int(talent_bonus("rest"))+5*count_kind("home")

func activity_available(index: int) -> bool:
	if index not in range(Catalog.config.activities.size()): return false
	var a: Dictionary = Catalog.config.activities[index]
	return realm>=int(a.realm) and count_kind(str(a.kind))>=int(a.assets)

func breakthrough_cost() -> int:
	if realm>=Catalog.config.realms.size()-1: return 0
	return ceili(float(Catalog.config.realms[realm+1].cost)*(1.0-talent_bonus("break")))

func breakthrough_error() -> String:
	if run_over: return "本世已经结束。"
	if realm>=Catalog.config.realms.size()-1: return "已达化神。"
	var r: Dictionary = Catalog.config.realms[realm+1]
	if earned<int(r.earned) or owned.size()<int(r.assets) or scratched<int(r.scratched):
		return "需累计奖金 %s、灵契 %d 件、刮票 %d 张。" % [Catalog.money(r.earned),r.assets,r.scratched]
	if cash<breakthrough_cost(): return "突破资金不足。"
	return ""

func breakthrough() -> bool:
	var error: String = breakthrough_error()
	if not error.is_empty(): return reject(error)
	cash-=breakthrough_cost()
	realm+=1
	commit()
	return true

func debt_paid() -> int:
	return 0 if debt_stage==0 else int(Catalog.config.debt_seals[debt_stage-1])

func debt_payment() -> int:
	return 0 if debt_stage>=Catalog.config.debt_seals.size() else int(Catalog.config.debt_seals[debt_stage])-debt_paid()

func repay_debt() -> bool:
	if run_over or debt_payment()==0: return false
	if realm<debt_stage+1: return reject("先突破对应境界，再解除这重债契。")
	if cash<debt_payment(): return reject("本重债契资金不足。")
	cash-=debt_payment()
	debt_stage+=1
	commit()
	return true

func prestige_reward() -> int:
	var base: int = floori(log(1.0+earned/100.0)/log(10.0)*2.0)+owned.size()*2
	return floori(base*(1.0+talent_bonus("merit")))

func _end_run(won: bool, reason: String) -> void:
	if run_over: return
	run_over=true; finished=won; auto_enabled=false
	var reward: int = prestige_reward()
	meta_points+=reward; meta_total+=reward
	last_run={"number":run_number,"reason":reason,"won":won,"earned":earned,"assets":owned.size(),"tickets":scratched,"points":reward,"skulls":skulls,"limit":skull_limit(),"debt_paid":debt_paid()}
	save() # Persist the award before any modal, reload, or signal can restart the run.
	changed.emit()
	run_ended.emit()
	if won: completed.emit()

func retire_run() -> bool:
	if run_over: return false
	if has_pending(): return reject("须先刮完已购票，不能弃掉劫印票。")
	if scratched<10: return reject("至少经历 10 张票后才能主动轮回。")
	_end_run(false,"主动入轮回")
	return true

func buy_talent(index: int) -> bool:
	if not run_over: return reject("天赋只能在本世结算后升级，下世生效。")
	if index not in range(Catalog.config.talents.size()): return false
	var t: Dictionary = Catalog.config.talents[index]
	var level: int = talent_level(t.id)
	if level>=t.costs.size(): return reject("此天赋已圆满。")
	if not str(t.prerequisite).is_empty() and talent_level(t.prerequisite)<int(t.requires): return reject("需前置天赋达到指定层数。")
	if meta_points<int(t.costs[level]): return reject("道行点数不足。")
	meta_points-=int(t.costs[level]); talents[t.id]=level+1
	commit()
	return true

func begin_next_run() -> bool:
	if not run_over: return false
	run_number+=1
	_reset_run()
	ticket_changed.emit()
	return true

func talent_bonus(id: String) -> float:
	for t in Catalog.config.talents:
		if t.id==id: return talent_level(id)*float(t.per_level)
	return 0.0
