extends SceneTree
## Seeded full careers through the production transactions. Not a human playtest.
var game: Node
var clock: float=0.0
var paid_rests: int=0
var free_rests: int=0
var jobs: int=0
func _init() -> void: call_deferred("run")
func advance(seconds: float) -> void:
	game._process(seconds); clock+=seconds
func recover(reserve: int) -> void:
	for i in range(Catalog.config.activities.size()-1,-1,-1):
		if game.activity_available(i) and game.cash>=game.activity_cost(i)+reserve:
			game.activity(i); advance(float(Catalog.config.activities[i].duration)); paid_rests+=1; return
	if game.rest_cooldown>0: advance(game.rest_cooldown)
	game.rest(); advance(4); free_rests+=1
func upgrade_meta() -> void:
	var priority: Array=[["cash",1],["spirit",1],["guard",2],["lives",1],["guard",5],["lives",2],["ward",1],["fortune",4],["focus",4],["rest",3],["break",3],["yield",3],["merit",2],["speed",3],["spirit",4],["cash",5]]
	for goal in priority:
		var index: int=-1
		for i in Catalog.config.talents.size():
			if Catalog.config.talents[i].id==goal[0]: index=i; break
		while game.talent_level(goal[0])<int(goal[1]):
			if not game.buy_talent(index): return
func one_run() -> Dictionary:
	var start_time: float=clock
	var milestones: Dictionary={}
	var start_points: int=game.meta_total
	for turn in 1800:
		if game.run_over: break
		var tier: int=game.highest_tier()
		while tier>0 and game.cash<int(Catalog.tickets[tier].price)*5: tier-=1
		var price: int=int(Catalog.tickets[tier].price)
		var reserve: int=price*5
		if game.breakthrough_error().is_empty() and game.cash>=game.breakthrough_cost()+reserve:
			game.breakthrough(); advance(1.8); milestones["realm_"+str(game.realm)]=game.scratched
		var asset_index: int=game.owned.size()
		if asset_index<10 and game.asset_available(asset_index) and game.cash>=int(Catalog.config.assets[asset_index].price)+reserve:
			game.buy_asset(asset_index); advance(2); milestones["asset_"+str(asset_index)]=game.scratched
		if game.realm>=1 and game.resonance<12 and game.scratched>=int(Catalog.config.upgrade_gates[game.resonance]) and game.cash>=int(Catalog.config.upgrade_costs[game.resonance])+reserve:
			game.buy_upgrade(); advance(1)
		if game.realm>game.debt_stage and game.debt_stage<5 and game.cash>=game.debt_payment()+reserve*10:
			game.repay_debt(); advance(1); milestones["debt_"+str(game.debt_stage)]=game.scratched
		if game.run_over: break
		if game.spirit<minf(game.max_spirit()*.75,110): recover(reserve)
		if game.cash<price:
			if game.work_cooldown>0: advance(game.work_cooldown)
			game.work(); advance(2); jobs+=1
		if game.skill_unlocked(6) and game.skill_error(6).is_empty() and game.spirit>140: game.use_skill(6)
		if game.skill_unlocked(5) and game.skill_error(5).is_empty() and game.spirit>100: game.use_skill(5)
		if game.skill_unlocked(1) and game.skill_error(1).is_empty() and game.spirit>45: game.use_skill(1)
		if game.buy_ticket(tier):
			if game.skill_error(0).is_empty(): game.use_skill(0)
			if game.current.seen:
				if game.skill_error(7).is_empty(): game.use_skill(7)
				if game.current.payout==0 and game.skill_error(4).is_empty(): game.use_skill(4)
				if game.current.payout>0 and game.skill_error(2).is_empty(): game.use_skill(2)
			for i in game.current.cells.size(): game.reveal_cell(i)
			advance(6.0)
	return {"number":game.run_number,"won":game.finished,"ended":game.run_over,"tickets":game.scratched,"earned":game.earned,"assets":game.owned.size(),"realm":game.realm,"skulls":game.skulls,"limit":game.skull_limit(),"wards_used":game.wards_used,"points":game.meta_total-start_points,"minutes_estimate":snappedf((clock-start_time)/60,.1),"milestones":milestones}
func run() -> void:
	game=root.get_node("Game"); game.no_save=true; game.set_process(false)
	var seed_count: int=100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="): seed_count=clampi(int(arg.get_slice("=",1)),1,100)
	var careers: Array=[]; var runs_to_win: Array=[]; var minutes: Array=[]; var initial_lengths: Array=[]
	var won: int=0; var first_win: int=0; var stalls: int=0
	for seed_value in range(1,seed_count+1):
		game.reset(); clock=0; paid_rests=0; free_rests=0; jobs=0
		var history: Array=[]
		for incarnation in 10:
			game.rng.seed=seed_value*1000+incarnation
			var result: Dictionary=one_run(); history.append(result)
			if incarnation==0:
				initial_lengths.append(game.scratched)
				if game.finished: first_win+=1
			if not game.run_over: stalls+=1; break
			if game.finished: won+=1; runs_to_win.append(incarnation+1); minutes.append(clock/60); break
			upgrade_meta(); game.begin_next_run()
		careers.append({"seed":seed_value,"won":game.finished,"runs":history,"minutes_estimate":snappedf(clock/60,.1),"paid_activities":paid_rests,"free_meditations":free_rests,"jobs":jobs,"talents":game.talents.duplicate()})
	initial_lengths.sort(); runs_to_win.sort(); minutes.sort()
	var report: Dictionary={"version":"0.3.0","seeds":seed_count,"wins_within_ten_runs":won,"first_run_wins":first_win,"stalled_runs":stalls,"median_first_run_tickets":initial_lengths[int(seed_count/2)],"min_first_run_tickets":initial_lengths[0],"max_first_run_tickets":initial_lengths[-1],"median_runs_to_win":runs_to_win[int(runs_to_win.size()/2)] if not runs_to_win.is_empty() else 0,"p90_runs_to_win":runs_to_win[maxi(0,ceili(runs_to_win.size()*.9)-1)] if not runs_to_win.is_empty() else 0,"median_career_minutes_estimate":snappedf(minutes[int(minutes.size()/2)],.1) if not minutes.is_empty() else 0,"policy":"actual transactions; reserve five face values; buy assets and realms at gates; paid recovery before skill chains; use sight and limited wards; defense-focused meta spending; six seconds per manual ticket; no passive recovery; at most ten runs","careers":careers}
	if seed_count==100:
		var file:=FileAccess.open("res://docs/balance-report.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"  ")); file.close()
	else: print(JSON.stringify(careers[0]))
	report.erase("careers"); print(JSON.stringify(report))
	quit(0 if won==seed_count and stalls==0 else 1)
