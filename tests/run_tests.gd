extends SceneTree
## Tests execute the real rule engine and transactions; no test-only economy.
var checks: int = 0
var failures: int = 0
var game: Node
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1; push_error("FAILED: "+label)
func finish_ticket() -> void:
	for i in game.current.cells.size(): game.reveal_cell(i)
func rich_fixture() -> void:
	game.reset(); game.cash = 100000000000; game.earned = 100000000000; game.scratched = 1500
	for a in Catalog.config.assets: game.owned.append(a.id)
	game.spirit = game.max_spirit()
func run() -> void:
	game = root.get_node("Game"); game.no_save = true; game.set_process(false)
	Catalog.load_data()
	var rng := RandomNumberGenerator.new(); rng.seed = 8462
	for t in Catalog.tickets:
		var valid: bool = true
		for grade in range(-1,6):
			for attempt in 120:
				var board: Dictionary = TicketRules.make_board(t,grade,rng)
				var expected: int = 0 if grade<0 else int(t.grades[grade])
				valid = valid and int(TicketRules.evaluate(board).units)==expected and SaveStore.board_valid(board)
				var from_json: Dictionary = JSON.parse_string(JSON.stringify(board))
				valid = valid and int(TicketRules.evaluate(from_json).units)==expected
		check(valid,"all generated grades and losing boards match rule: "+str(t.id))
	check(TicketRules.evaluate({"rule":"match3","cells":[1,1,1,2,2,2,5,6,5],"grades":[2,4,10,24,60,80]}).units==6,"two triple sets add, pairs do not pay")
	check(TicketRules.evaluate({"rule":"lines","cells":[1,2,1,2,1,2,1,2,1],"grades":[2,4,10,24,60,80]}).units==4,"two diagonals add without false row wins")
	check(TicketRules.evaluate({"rule":"pairs","cells":[1,1,2,2,3,4,5,6],"prizes":[10,20,100,200]}).units==30,"only complete matching pairs award row prize")
	check(TicketRules.evaluate({"rule":"sum","cells":[5,6,7,9,9,9,2,8,8],"prizes":[10,200,30]}).units==40,"exactly eighteen, not merely large numbers")
	check(TicketRules.evaluate({"rule":"vault","cells":[1,2,3,3,2,1,1,2,8,1,2,3],"prizes":[5,99,10]}).units==15,"vault needs all three keys, partial row never pays")
	var dragon: Dictionary = {"rule":"dragon","cells":[{"op":"+","n":10},{"op":"*","n":5},{"op":"+","n":8},{"op":"*","n":2},{"op":"+","n":5},{"op":"*","n":0}]}
	check(TicketRules.evaluate(dragon).units==0,"late dragon zero wipes a large subtotal")
	dragon.cells[5].n = 2
	check(TicketRules.evaluate(dragon).units==242,"dragon calculates strictly left to right")
	var concealed: Dictionary = {"board":{"rule":"match3","cells":[1,1,1,2,3,4,5,6,2],"grades":[2,4,10,24,60,80]},"revealed":[true,true,false,false,false,false,false,false,false]}
	check(TicketRules.visible_hits(concealed).is_empty(),"partial feedback cannot reveal an unseen third match")
	concealed.revealed[2]=true
	check(TicketRules.visible_hits(concealed).size()==3,"matching line lights up before the remaining foil is cleared")
	game.reset()
	check(game.cash==80 and game.max_spirit()==60,"fresh start preserved")
	check(not game.buy_ticket(7) and game.cash==80,"wealth gate and ticket lock")
	check(not game.use_skill(0),"preview requires purchased ticket")
	check(game.buy_ticket(0) and game.cash==70,"purchase charges once")
	check(not game.buy_ticket(0),"cannot overwrite pending ticket")
	check(game.use_skill(0) and game.spirit==56,"preview costs spirit and exposes precise result")
	check(not game.use_skill(0) and game.spirit==56,"preview cannot spend twice")
	var snap: Dictionary = game.snapshot()
	var random_next: int = game.rng.randi()
	game.restore(snap)
	check(game.rng.randi()==random_next,"full RNG state preserved")
	game.restore(snap); finish_ticket()
	check(game.cash==120 and game.earned==50 and game.scratched==1,"tutorial rule awards five times face price")
	finish_ticket(); check(game.cash==120,"settlement cannot repeat")
	game.cash = 999999999999
	check(not game.buy_asset(9) and not game.buy_upgrade(),"cash cannot skip progression gates")
	game.scratched = 12
	game.spirit = 60
	check(game.use_skill(1) and game.luck_charges==3,"luck creates three charges")
	for i in 3:
		game.buy_ticket(0)
		check(game.current.payout>=50 and game.current.luck,"luck ticket is third grade or better")
		finish_ticket()
	check(game.luck_charges==0,"luck consumed once per purchase")
	game.buy_ticket(0); game.start_scratching()
	check(not game.use_skill(0) and not game.use_skill(2) and not game.use_skill(4),"first foil damage locks alterations")
	game.restore(game.snapshot()); check(not game.untouched(),"partial scratch lock survives reload")
	finish_ticket()
	rich_fixture()
	game.buy_ticket(2)
	# A real generated losing dragon, including the normal persisted state flags.
	game.current.board = TicketRules.make_board(Catalog.tickets[2],-1,rng)
	game.current.cells = game.current.board.cells; Economy.recalculate(game.current)
	check(not game.use_skill(4),"alchemy requires paid sight, no free outcome oracle")
	check(game.use_skill(0),"sight identifies dragon risk")
	check(game.use_skill(4) and game.current.payout>0 and game.current.board.cells[5].n==2,"alchemy replaces zero on actual dragon board")
	var base: int = game.current.payout
	check(game.use_skill(2) and game.current.payout==base*game.boost_factor(),"cars strengthen actual skill payout")
	check(not game.use_skill(4) and not game.use_skill(2),"interventions limited to once per ticket")
	var fixed: Dictionary = game.snapshot(); game.restore(fixed)
	check(game.current.payout==base*game.boost_factor(),"modified symbols and reward survive reload")
	finish_ticket()
	check(game.biggest_win>0 and game.skill_profit>0,"reward feedback stats record benefits")
	for tier in Catalog.tickets.size():
		if tier==2: continue
		game.buy_ticket(tier); game.current.board = TicketRules.make_board(Catalog.tickets[tier],-1,rng)
		game.current.cells = game.current.board.cells; Economy.recalculate(game.current)
		game.spirit = game.max_spirit(); game.use_skill(0); game.use_skill(4)
		check(game.current.payout>0 and int(TicketRules.evaluate(game.current.board).units)==int(Catalog.tickets[tier].grades[2]),"alchemy still obeys rule: "+str(tier))
		finish_ticket()
	game.spirit = game.max_spirit()
	check(game.use_skill(5),"arm five-ticket chain")
	for factor in range(2,7):
		game.buy_ticket(0); check(game.current.skill_factor==factor,"chain applies ascending factor "+str(factor)); finish_ticket()
	game.buy_ticket(0); check(game.current.skill_factor==1,"chain expires"); finish_ticket()
	game.spirit = game.max_spirit(); check(game.use_skill(6),"arm burst jackpot")
	game.buy_ticket(7); check(game.current.multiplier==Catalog.tickets[7].jackpot,"burst produces legal top prize board"); finish_ticket()
	check(not game.use_skill(6),"burst cooldown cannot be bypassed")
	game.misses = 4; game.buy_ticket(0); check(game.current.payout>0 and game.current.protected,"pity still guarantees a win"); finish_ticket()
	game.spirit = 0; var cash_before: int = game.cash; var cost: int = game.activity_cost(0)
	check(game.activity(0) and game.spirit==game.max_spirit()*.4 and game.cash==cash_before-cost,"activities scale restoration to capacity")
	check(game.buffs.focus==6 and game.skill_cost(0)==3,"tea reduces skill cost for six new tickets")
	game.buy_ticket(0); check(game.buffs.focus==5 and game.current.focused,"activity charge frozen on purchased ticket"); finish_ticket()
	game.spirit = 0; check(game.activity(2) and game.activity(3),"travel and holiday are both available")
	game.buy_ticket(0); check(game.current.effect==3.0,"travel reward buffs use stronger value instead of multiplying forever"); finish_ticket()
	check(game.regen_rate()>.4 and game.boost_factor()==18,"asset perks improve recovery and active play")
	var fee_with_cars: int = game.activity_cost(3)
	var old_owned: Array = game.owned.duplicate()
	game.owned.clear()
	check(game.activity_cost(3)>fee_with_cars,"cars reduce the same activity price")
	game.owned=old_owned
	# Automation uses the same transactions and respects stop conditions.
	game.reset(); game.scratched=12; game.cash=500; game.spirit=60
	check(not game.set_auto_option("combo",true) and not game.set_auto_option("recover",true),"home gates protect advanced automation")
	check(game.use_skill(3) and game.auto_enabled,"automation unlocks after twelve tickets")
	check(not game.buy_auto_upgrade(),"automation efficiency cannot skip its progression gate")
	game.automation_paused=true
	game.automation_tick(10); check(game.current.is_empty(),"menus pause automation")
	game.automation_paused=false
	game.automation_tick(.1); check(game.has_pending() and game.spirit==58,"automation buys and charges once per card")
	var paid_spirit: float = game.spirit
	for i in 6: game.automation_tick(.1)
	check(game.spirit==paid_spirit,"per-cell ticks do not drain per-ticket fee again")
	for i in 80: game.automation_tick(.2)
	check(game.auto_tickets>=2 and game.auto_earned>=0,"continuous automated settlement")
	game.stop_auto("test"); if game.has_pending(): finish_ticket()
	game.cash = 30; game.use_skill(3); game.automation_tick(1); game.automation_tick(1)
	check(not game.auto_enabled and game.cash==30,"cash reserve stops before spending reserved money")
	game.cash=100; game.spirit=0; game.use_skill(3); game.automation_tick(1)
	check(game.cash==100 and not game.has_pending() and game.spirit==0,"zero-spirit automation waits without overdraft")
	game.restore(game.snapshot()); check(not game.auto_enabled,"reload never silently resumes spending")
	rich_fixture(); game.spirit=0; game.auto_tier=0; game.auto_combo=true; game.auto_luck=true; game.auto_recover=true; game.use_skill(3)
	game.automation_tick(.1); check(game.spirit>0 and game.auto_wait>0,"home automation buys recovery and waits for activity")
	for i in 150: game.automation_tick(.1)
	check(game.auto_tickets>0 and game.auto_earned>0,"fully connected auto recovery skill scratch loop")
	game.stop_auto("test"); if game.has_pending(): finish_ticket()
	game.spirit=0; game.cash=0
	check(not game.activity(0) and game.work() and game.cash>0,"bankruptcy job fallback")
	check(not game.work(),"work cooldown prevents spam")
	game.rest(); check(game.spirit==18,"free recovery fallback")
	# Disk validation, corrupt backup and schema migration.
	var path: String = "user://v02-test.json"
	check(SaveStore.write_snapshot(game.snapshot(),path),"atomic save writes")
	check(not SaveStore.read_snapshot(path).is_empty(),"schema two save roundtrip")
	check(SaveStore.write_snapshot(game.snapshot(),path),"validated backup created")
	var broken := FileAccess.open(path,FileAccess.WRITE); broken.store_string("{broken"); broken.close()
	check(not SaveStore.read_snapshot(path).is_empty(),"broken primary recovers validated backup")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	var legacy: Dictionary = {"version":1,"cash":100,"spirit":50,"earned":500,"scratched":30,"misses":0,"resonance":1,"owned":["car_1"],"luck_armed":true,"current":{"tier":3,"payout":300,"cells":[300,0,0,0,0,0,0,0,0,0,0,0],"revealed":[true,false,false,false,false,false,false,false,false,false,false,false],"settled":false,"seen":true,"boosted":true,"multiplier":3,"protected":false,"first":false,"luck":false}}
	check(SaveStore.is_valid(legacy),"v0.1 save accepted")
	game.restore(legacy)
	check(game.current.tier==2 and game.current.ticket_id=="dragon" and game.current.board.rule=="legacy","old tier remapped by stable ID")
	check(game.current.payout==300 and game.current.revealed[0] and game.luck_charges==1 and game.owned==["car_1"],"legacy assets, skill and partial result retained")
	finish_ticket(); check(game.cash==400 and game.earned==800,"legacy ticket awards exactly its original result")
	var veteran: Dictionary = legacy.duplicate(true)
	veteran.earned=20000000; veteran.scratched=140; veteran.current={}
	game.restore(veteran)
	check(game.unlocked(7) and game.unlocked(3),"v0.1 earned ticket unlocks are not removed by new gates")
	game.restore(legacy); finish_ticket()
	var invalid: Dictionary = game.snapshot(); invalid.version=2; invalid.current.payout+=1
	check(not SaveStore.is_valid(invalid),"mismatched board and prize rejected")
	check(not SaveStore.is_valid({"version":3}) and not SaveStore.is_valid({"version":2,"cash":"NaN"}),"unknown schema and invalid numeric types rejected")
	var normal_jackpots: int = 0; var lucky_jackpots: int = 0; var lucky_valid: bool = true
	for i in 10000:
		var normal: Dictionary = Economy.roll(rng,0,false,0,1)
		var lucky: Dictionary = Economy.roll(rng,0,true,0,1)
		normal_jackpots+=1 if normal.multiplier==50 else 0
		lucky_jackpots+=1 if lucky.multiplier==50 else 0
		lucky_valid = lucky_valid and lucky.payout>=50
	check(lucky_valid and lucky_jackpots>normal_jackpots*8,"luck materially changes floor and jackpot frequency")
	rich_fixture(); game.commit(); check(game.finished,"collection and net-worth ending remains reachable")
	print("TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
