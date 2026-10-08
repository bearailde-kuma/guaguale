extends SceneTree
## Seeded player policy; calls real game transactions and real automation ticks.
## Virtual play time is an estimate, not a human playtest measurement.
var game: Node
var clock: float = 0.0
func _init() -> void: call_deferred("run")
func advance(seconds: float, paused: bool = false) -> void:
	game.automation_paused = paused
	game._process(seconds)
	clock += seconds
	game.automation_paused = false
func recover(reserve: int) -> bool:
	for i in range(Catalog.config.activities.size()-1,-1,-1):
		if game.earned>=int(Catalog.config.activities[i].unlock) and game.cash>=game.activity_cost(i)+reserve:
			game.activity(i); advance(float(Catalog.config.activities[i].duration),true); return true
	return false
func run() -> void:
	game = root.get_node("Game"); game.no_save=true; game.set_process(false)
	var runs: Array = []
	var tickets: Array = []; var minutes: Array = []
	var completions: int = 0
	var seed_count: int = 100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="): seed_count = clampi(int(arg.get_slice("=",1)),1,100)
	for seed_value in range(1,seed_count+1):
		game.reset(); game.rng.seed=seed_value; clock=0.0
		var works: int = 0; var paid_rests: int = 0; var free_rests: int = 0
		var milestones: Dictionary = {}
		for turn in 6000:
			var tier: int = game.highest_tier()
			while tier>0 and game.cash<int(Catalog.tickets[tier].price)*5: tier-=1
			var price: int = int(Catalog.tickets[tier].price)
			var reserve: int = price*5
			var asset_index: int = game.owned.size()
			if asset_index<Catalog.config.assets.size() and game.asset_available(asset_index) and game.cash>=int(Catalog.config.assets[asset_index].price)+reserve:
				game.buy_asset(asset_index); advance(2.0,true)
				milestones["asset_"+str(asset_index)] = game.scratched
			if game.resonance<Catalog.config.upgrade_costs.size() and game.scratched>=int(Catalog.config.upgrade_gates[game.resonance]) and game.cash>=int(Catalog.config.upgrade_costs[game.resonance])+reserve:
				game.buy_upgrade(); advance(1.0,true)
			if game.auto_level<3 and game.scratched>=int(Catalog.config.automation_gates[game.auto_level]) and game.count_kind("home")>=int(Catalog.config.automation_homes[game.auto_level]) and game.cash>=int(Catalog.config.automation_costs[game.auto_level])+reserve:
				game.buy_auto_upgrade(); advance(1.0,true)
			# Manual recovery until the second home unlocks automatic entertainment.
			if game.spirit<36 and game.count_kind("home")<2:
				if recover(reserve): paid_rests+=1
				elif game.spirit<8:
					game.rest(); advance(4.0,true); free_rests+=1
			if game.cash<reserve:
				if game.work_cooldown>0: advance(game.work_cooldown,true)
				game.work(); advance(2.0,true); works+=1
			if game.skill_unlocked(6) and game.skill_error(6).is_empty() and game.spirit>120: game.use_skill(6)
			if game.skill_unlocked(5) and game.skill_error(5).is_empty() and game.spirit>110: game.use_skill(5)
			var before: int = game.scratched
			if game.skill_unlocked(3):
				game.set_auto_option("tier",tier); game.set_auto_option("luck",true)
				if game.count_kind("home")>=1: game.set_auto_option("combo",true)
				if game.count_kind("home")>=2: game.set_auto_option("recover",true)
				if not game.auto_enabled: game.use_skill(3)
				for tick in 1600:
					advance(.1)
					if game.scratched>before or not game.auto_enabled: break
			else:
				if game.skill_unlocked(1) and game.skill_error(1).is_empty() and game.spirit>=28: game.use_skill(1)
				if game.buy_ticket(tier):
					if game.skill_error(0).is_empty(): game.use_skill(0)
					if game.current.seen and game.current.payout>0 and game.skill_error(2).is_empty(): game.use_skill(2)
					for i in game.current.cells.size(): game.reveal_cell(i)
					advance(6.0,true)
			if game.scratched==before and game.has_pending():
				# Preserve a bought card; recover manually if an automated batch stalls.
				game.rest(); advance(4.0,true); free_rests+=1
			if not milestones.has(str(game.highest_tier())): milestones[str(game.highest_tier())]=game.scratched
			if not milestones.has("wealth_goal") and game.net_worth()>=int(Catalog.config.goal): milestones.wealth_goal = game.scratched
			if game.finished: break
		completions += 1 if game.finished else 0
		tickets.append(game.scratched); minutes.append(clock/60.0)
		runs.append({"seed":seed_value,"finished":game.finished,"tickets":game.scratched,"minutes_estimate":snappedf(clock/60.0,.1),"works":works,"manual_activities":paid_rests,"free_rests":free_rests,"auto_tickets":game.auto_tickets,"owned":game.owned.size(),"net_worth":game.net_worth(),"milestones":milestones})
	tickets.sort(); minutes.sort()
	var report: Dictionary = {"version":"0.2.0","seeds":seed_count,"completed":completions,"min_tickets":tickets[0],"median_tickets":tickets[int(seed_count/2)],"p90_tickets":tickets[maxi(0,ceili(seed_count*.9)-1)],"max_tickets":tickets[-1],"min_minutes_estimate":snappedf(minutes[0],.1),"median_minutes_estimate":snappedf(minutes[int(seed_count/2)],.1),"p90_minutes_estimate":snappedf(minutes[maxi(0,ceili(seed_count*.9)-1)],.1),"max_minutes_estimate":snappedf(minutes[-1],.1),"policy":"five-ticket reserve; assets and upgrades at gates; auto at 12; home automation; active chain/burst; 6 seconds/manual card, 0.1s auto ticks and activity durations; no offline earnings","runs":runs}
	if seed_count==100:
		var file := FileAccess.open("res://docs/balance-report.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ")); file.close()
	if seed_count<100: print(JSON.stringify(runs[0]))
	report.erase("runs"); print(JSON.stringify(report)); quit(0 if completions==seed_count else 1)
