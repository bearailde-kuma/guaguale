extends SceneTree
## Real rule engines, transactions, save migrations and failure/rebirth boundaries.
var checks: int = 0
var failures: int = 0
var game: Node
func _init() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("FAILED: "+label)
func finish_ticket() -> void:
	for i in game.current.cells.size(): game.reveal_cell(i)
func rich_fixture() -> void:
	game.reset(); game.cash=200000000000; game.earned=200000000000; game.scratched=1500; game.realm=5
	for a in Catalog.config.assets: game.owned.append(a.id)
	game.spirit=game.max_spirit()
func force_skull(index: int) -> void:
	game.current.skull_index=index; game.current.skull_seen=false; game.current.skull_blocked=false
func run() -> void:
	game=root.get_node("Game"); game.no_save=true; game.set_process(false)
	Catalog.load_data()
	var rng:=RandomNumberGenerator.new(); rng.seed=8462
	for t in Catalog.tickets:
		var valid: bool=true
		for grade in range(-1,6):
			for attempt in 120:
				var board: Dictionary=TicketRules.make_board(t,grade,rng)
				var expected: int=0 if grade<0 else int(t.grades[grade])
				valid=valid and int(TicketRules.evaluate(board).units)==expected and SaveStore.board_valid(board)
				var roundtrip: Dictionary=JSON.parse_string(JSON.stringify(board))
				valid=valid and int(TicketRules.evaluate(roundtrip).units)==expected and SaveStore.board_valid(roundtrip)
		check(valid,"6720 boards: grade, loss, validator and JSON roundtrip "+str(t.id))
	var grades: Array=[1,2,5,12,25,50]
	check(TicketRules.evaluate({"rule":"match3","cells":[1,1,1,2,2,2,5,6,5],"grades":grades}).units==3,"matching triples add")
	check(TicketRules.evaluate({"rule":"numbers","cells":[{"n":8,"prize":0},{"n":9,"prize":0},{"n":8,"prize":12},{"n":6,"prize":50}]}).units==12,"bamboo only matching numbers pay")
	var dragon: Dictionary={"rule":"dragon","cells":[{"op":"+","n":10},{"op":"*","n":5},{"op":"+","n":8},{"op":"*","n":2},{"op":"+","n":5},{"op":"*","n":0}]}
	check(TicketRules.evaluate(dragon).units==0,"dragon final zero erases subtotal")
	dragon.cells[5].n=2
	check(TicketRules.evaluate(dragon).units==242,"dragon left to right calculation")
	check(MysticRules.path_info([1,0,1,0,1,0,1,0]).valid and MysticRules.path_info([1,0,1,0,1,0,1,0]).area==4,"Dyck return path exact area")
	check(not MysticRules.path_info([0,1,1,1,1,0,0,0]).valid,"returning to origin does not excuse an earlier underflow")
	check(MysticRules.coefficient([1,1,1,1,1,1],3)==20,"polynomial coefficient C(6,3)")
	check(MysticRules.coefficient([2,4,6,8,10,12],5)==0,"odd target cannot use all even stones")
	var circuit: Dictionary={"rule":"circuit","cells":[0,0,0,10,10,10,0,0,0],"prizes":[2,5,12],"grades":grades}
	check(MysticRules.evaluate(circuit).units==5,"pipe connects source to middle exit")
	circuit.cells[4]=2
	check(MysticRules.evaluate(circuit).units==0,"both sides of a pipe must connect")
	for values in [[2,2,1,2],[2,1,1,2],[2,3,1,2]]:
		check(MysticRules.evaluate({"rule":"limit","cells":values,"grades":grades}).units==(2 if values[1]==2 else 0),"finite, zero and divergent limits "+str(values))
	var integral: Dictionary={"rule":"integral","cells":[{"w":3,"h":5},{"w":3,"h":-4},{"w":1,"h":3}],"grades":grades}
	check(MysticRules.evaluate(integral).units==1,"signed area adds and subtracts exactly")
	game.reset()
	check(game.cash==80 and game.realm==0 and game.max_spirit()==60,"mortal initial state")
	check(not game.buy_ticket(7) and not game.use_skill(1),"realm gates apply even with actions")
	check(game.buy_ticket(0) and game.cash==70,"pay before reveal")
	check(game.current.skull_index==-1,"tutorial grace applies to entire ticket")
	check(not game.buy_ticket(0),"pending ticket cannot be discarded")
	check(game.use_skill(0) and game.spirit==56,"mortal sight costs four")
	check(not game.use_skill(0) and game.spirit==56,"sight is single use")
	var snap: Dictionary=game.snapshot(); var random_next: int=game.rng.randi()
	game.restore(snap); check(game.rng.randi()==random_next,"exact RNG state roundtrip")
	game.restore(snap); finish_ticket()
	check(game.cash==120 and game.earned==50 and game.scratched==1,"tutorial triple gives five face values")
	finish_ticket(); check(game.cash==120,"settlement idempotent")
	game.spirit=0; game._process(10000)
	check(game.spirit==0 and game.regen_rate()==0,"no passive or offline spirit, even over long tick")
	check(game.rest() and game.spirit==20 and not game.rest(),"free rest is explicit and has a cooldown")
	game._process(4); check(game.rest() and game.spirit==40,"rest cooldown expires without giving energy")
	game.cash=999999999999
	check(not game.buy_asset(9) and not game.breakthrough(),"cash cannot skip asset and realm gates")
	game.scratched=5
	check(game.breakthrough() and game.realm==1 and game.skill_unlocked(3),"five-ticket qi breakthrough opens automation")
	check(game.spirit==40,"breakthrough expands capacity without healing")
	game.spirit=game.max_spirit()
	check(game.use_skill(1) and game.luck_charges==3,"qi prayer arms three tickets")
	for i in 3:
		game.buy_ticket(0); check(game.current.payout>=50 and game.current.luck,"prayer guarantees real grade >=3"); finish_ticket()
	game.buy_ticket(0); game.start_scratching()
	check(not game.use_skill(0) and not game.use_skill(2),"first foil damage freezes interventions")
	game.restore(game.snapshot()); check(not game.untouched(),"partial scratch lock survives load"); finish_ticket()
	rich_fixture(); game.buy_ticket(2)
	game.current.board=TicketRules.make_board(Catalog.tickets[2],-1,rng); game.current.cells=game.current.board.cells; Economy.recalculate(game.current)
	force_skull(4)
	check(not game.use_skill(4) and not game.use_skill(7),"alterations require paid sight")
	game.use_skill(0)
	check(game.use_skill(4) and game.current.board.cells[5].n==2 and game.current.payout>0,"alchemy turns dragon zero to two")
	check(game.current.skull_index==4,"alchemy never rerolls the skull")
	var base: int=game.current.payout
	check(game.use_skill(2) and game.current.payout==base*16,"five spirit cars strengthen multiplier")
	check(game.use_skill(7) and game.wards_used==1 and game.current.skull_blocked,"ward consumes scarce per-run charge")
	var fixed: Dictionary=game.snapshot(); game.restore(JSON.parse_string(JSON.stringify(fixed)))
	check(game.current.payout==base*16 and game.current.skull_blocked,"skill outcome and ward persist")
	finish_ticket(); check(game.skulls==0 and game.current.skull_seen,"blocked skull reveals without adding danger")
	for tier in Catalog.tickets.size():
		game.buy_ticket(tier); force_skull(-1)
		game.current.board=TicketRules.make_board(Catalog.tickets[tier],-1,rng); game.current.cells=game.current.board.cells; Economy.recalculate(game.current)
		game.spirit=game.max_spirit(); game.use_skill(0); game.use_skill(4)
		check(game.current.payout>0,"alchemy respects new rule "+str(tier)); finish_ticket()
	game.spirit=game.max_spirit(); game.use_skill(5)
	for factor in range(2,7):
		game.buy_ticket(0); force_skull(-1); check(game.current.skill_factor==factor,"chain factor "+str(factor)); finish_ticket()
	game.spirit=game.max_spirit(); check(game.use_skill(6),"yuan ying edict unlocked")
	game.buy_ticket(7); force_skull(-1); check(game.current.multiplier==Catalog.tickets[7].jackpot,"edict constructs highest legal mathematical prize"); finish_ticket()
	check(not game.use_skill(6),"edict obeys eighteen-ticket cooldown")
	game.misses=7; game.buy_ticket(0); force_skull(-1); check(game.current.payout>0 and game.current.protected,"eight-ticket drought protection"); finish_ticket()
	game.spirit=0; var before_cash: int=game.cash; var fee: int=game.activity_cost(0)
	check(game.activity(0) and game.spirit==game.max_spirit()*.6 and game.cash==before_cash-fee,"home capacity and paid activity recovery")
	check(game.buffs.focus==6 and game.skill_cost(0)==3,"tea prepares discount")
	game.spirit=0; check(game.activity(5) and game.buffs.flow==24 and game.buffs.focus==24 and game.buffs.holiday==24,"realm five ritual refreshes all three buffs")
	game.buy_ticket(0); force_skull(-1); check(game.current.effect==3,"activity reward frozen at purchase"); finish_ticket()
	var assets: Array=game.owned.duplicate(); game.owned.clear()
	check(not game.activity_available(5) and game.activity_cost(0)>fee,"activities gate on estate count; cars reduce cost")
	game.owned=assets
	# Fatal revelation happens immediately and can never award this ticket.
	game.buy_ticket(0); force_skull(0); game.skulls=2; game.spirit=game.max_spirit(); game.use_skill(0)
	check(not game.use_skill(7),"spent ward cannot be refilled by activities")
	before_cash=game.cash; var prior_earned: int=game.earned
	game.reveal_cell(0)
	check(game.run_over and not game.finished and game.skulls==3,"third skull ends the run at the revealed cell")
	check(game.cash==before_cash and game.earned==prior_earned and not game.current.settled,"fatal partial ticket pays nothing")
	check(game.meta_points==game.prestige_reward() and game.meta_points>0,"money and assets award persistent points")
	var points: int=game.meta_points; var end_snapshot: Dictionary=game.snapshot()
	finish_ticket(); game._end_run(false,"duplicate"); game.restore(end_snapshot)
	check(game.meta_points==points and game.run_over,"reload and repeated end cannot award twice")
	check(SaveStore.is_valid(end_snapshot),"fatal partial ticket is a valid schema-three save")
	check(not game.buy_ticket(0) and not game.work() and not game.rest() and not game.activity(0),"all economy actions stop on death")
	check(not game.buy_talent(1),"talent prerequisite enforced")
	check(game.buy_talent(0) and game.buy_talent(0) and game.buy_talent(1),"root levels unlock a dependent talent")
	check(game.buy_talent(4),"wealth branch initial money talent")
	var kept_points: int=game.meta_points
	check(game.begin_next_run() and game.run_number==2 and game.cash==180 and game.owned.is_empty() and game.realm==0,"rebirth resets run but applies start-money inheritance")
	check(game.meta_points==kept_points and game.skull_limit()==4 and is_equal_approx(game.skull_chance(0),.008),"talents persist and alter real risk and tolerance")
	check(not game.buy_talent(0) and not game.retire_run(),"no mid-run upgrades or immediate retirement farming")
	game.scratched=10; game.buy_ticket(0)
	check(not game.retire_run(),"retirement cannot discard an unfavourable purchased ticket")
	finish_ticket(); check(game.retire_run(),"voluntary run end uses same one-time award transaction")
	# Fatal last cell must also withhold payout and stop auto.
	rich_fixture(); game.buy_ticket(0); force_skull(game.current.cells.size()-1); game.skulls=2; game.auto_enabled=true
	before_cash=game.cash; finish_ticket()
	check(game.run_over and game.cash==before_cash and not game.auto_enabled,"fatal last cell pays nothing and disables automation")
	check(SaveStore.is_valid(game.snapshot()),"fatal fully revealed but forfeited ticket survives validation")
	var final_cell_snapshot: Dictionary=JSON.parse_string(JSON.stringify(game.snapshot()))
	game.restore(final_cell_snapshot)
	check(game.run_over and game.current.forfeited and not game.current.settled,"fatal last cell remains ended and unpaid after reload")
	# Paid automation, reserves, menu pause and lack of regen.
	game.reset(); game.realm=1; game.scratched=5; game.cash=500; game.spirit=60
	check(not game.set_auto_option("combo",true) and not game.set_auto_option("recover",true),"home gates for automation strategy")
	check(game.use_skill(3),"qi automation toggle")
	game.automation_paused=true; game.automation_tick(100)
	check(game.current.is_empty(),"menus pause automation")
	game.automation_paused=false; game.automation_tick(.1)
	check(game.has_pending() and game.spirit==58,"automatic purchase drains spirit once")
	var paid_spirit: float=game.spirit
	for i in 5: game.automation_tick(.1)
	check(game.spirit==paid_spirit,"revealing cells never charges ticket fee twice")
	var paid: Dictionary=game.snapshot(); game.restore(paid); game.use_skill(3); game.automation_tick(.1)
	check(game.spirit==paid_spirit,"reloaded paid card is not charged again")
	for i in 80: game.automation_tick(.2)
	check(game.auto_tickets>=2,"automatic continuous settlement")
	game.stop_auto("test"); finish_ticket(); game.cash=30; game.use_skill(3); game.auto_wait=0; game.automation_tick(1)
	check(not game.auto_enabled and game.cash==30,"selected ticket reserve stops purchase")
	game.cash=100; game.spirit=0; game.use_skill(3); game.automation_tick(100)
	check(game.cash==100 and game.spirit==0,"no spirit means no purchase or implicit healing")
	game.restore(game.snapshot()); check(not game.auto_enabled,"load never silently resumes spending")
	rich_fixture(); game.spirit=0; game.auto_recover=true; game.auto_combo=true; game.auto_luck=true; game.use_skill(3)
	game.automation_tick(.1)
	check(game.spirit>0 and game.auto_wait>0 and game.cash<200000000000,"automatic recovery is an actual paid activity")
	for i in 180: game.automation_tick(.1)
	check(game.auto_tickets>0 and game.auto_earned>0,"paid recovery skill purchase scratch loop")
	game.stop_auto("test"); finish_ticket(); game.spirit=0; game.cash=0
	check(game.work() and game.spirit==0 and not game.work(),"bankruptcy fallback gives cash, not passive spirit")
	# Save validation and both historical migrations.
	var path: String="user://v03-test.json"
	check(SaveStore.write_snapshot(game.snapshot(),path),"atomic write")
	check(not SaveStore.read_snapshot(path).is_empty(),"schema three disk roundtrip")
	SaveStore.write_snapshot(game.snapshot(),path)
	var broken:=FileAccess.open(path,FileAccess.WRITE); broken.store_string("{broken"); broken.close()
	check(not SaveStore.read_snapshot(path).is_empty(),"invalid primary falls back to validated backup")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	var legacy: Dictionary={"version":1,"cash":100,"spirit":50,"earned":500,"scratched":30,"misses":0,"resonance":1,"owned":["car_1"],"luck_armed":true,"current":{"tier":3,"payout":300,"cells":[300,0,0,0,0,0,0,0,0,0,0,0],"revealed":[true,false,false,false,false,false,false,false,false,false,false,false],"settled":false,"seen":true,"boosted":true,"multiplier":3,"protected":false,"first":false,"luck":false}}
	check(SaveStore.is_valid(legacy),"schema one accepted")
	game.restore(legacy); finish_ticket()
	check(game.cash==400 and game.current.board.rule=="legacy" and game.current.skull_index==-1,"v0.1 paid amount and no new skull retained")
	rich_fixture(); game.buy_ticket(3)
	var old_ticket: Dictionary=game.snapshot(); old_ticket.version=2
	var old_catalog: Dictionary=Catalog.tickets[3].duplicate(); old_catalog.rule="collect"
	old_ticket.current.board=TicketRules.make_board(old_catalog,3,rng); old_ticket.current.cells=old_ticket.current.board.cells
	old_ticket.current.revealed=[]; old_ticket.current.revealed.resize(12); old_ticket.current.revealed.fill(false)
	Economy.recalculate(old_ticket.current)
	var original: int=old_ticket.current.payout
	check(SaveStore.is_valid(old_ticket),"v0.2 replaced gameplay remains valid")
	game.restore(old_ticket); finish_ticket()
	check(game.current.payout==original and game.current.board.rule=="collect" and game.realm==5,"v0.2 preserves old board and grants earned realm")
	var invalid: Dictionary=game.snapshot(); invalid.current.payout+=1
	check(not SaveStore.is_valid(invalid),"modified reward without matching board rejected")
	invalid=game.snapshot(); invalid.talents={"guard":999}
	check(not SaveStore.is_valid(invalid),"invalid talent cap rejected")
	check(not SaveStore.is_valid({"version":99}) and not SaveStore.is_valid({"version":3,"cash":"NaN"}),"unknown schema and nonnumeric values rejected")
	# Distribution checks use the production generator without pity.
	var wins: int=0; var natural_top: int=0; var lucky_top: int=0; var lucky_ok: bool=true
	for i in 10000:
		var natural: Dictionary=Economy.roll(rng,0,false,0,1)
		var lucky: Dictionary=Economy.roll(rng,0,true,0,1)
		wins+=1 if natural.payout>0 else 0
		natural_top+=1 if natural.multiplier==50 else 0
		lucky_top+=1 if lucky.multiplier==50 else 0
		lucky_ok=lucky_ok and lucky.payout>=50
	check(wins>2400 and wins<2800,"natural chance matches 26%, lower than v0.2")
	check(lucky_ok and lucky_top>natural_top*10,"prayer materially raises floor and jackpot frequency")
	# Risk is one independent badge per ticket, never per scratch cell.
	rich_fixture(); game.rng.seed=20261016
	for tier in [0,7]:
		var skull_cards: int=0
		for i in 10000:
			game.current.clear(); game.buy_ticket(tier)
			if int(game.current.skull_index)>=0: skull_cards+=1
		check(skull_cards>=(70 if tier==0 else 175) and skull_cards<=(135 if tier==0 else 265),"per-ticket skull rate sample tier "+str(tier)+" = "+str(skull_cards))
	game.current.clear(); game.buy_ticket(0); force_skull(2)
	var skull_save: Dictionary=game.snapshot(); game.restore(skull_save); game.reveal_cell(2)
	check(game.skulls==1,"saved skull increments only on its reveal")
	game.restore(game.snapshot()); game.reveal_cell(2)
	check(game.skulls==1,"reloaded revealed skull cannot count twice")
	invalid=game.snapshot(); invalid.current.skull_index="broken"
	check(not SaveStore.is_valid(invalid),"invalid skull field rejected without evaluating an arithmetic expression")
	rich_fixture()
	for i in 5: check(game.repay_debt(),"debt seal payment "+str(i))
	check(game.finished and game.run_over and game.debt_paid()==100000000000,"realm + estates + actually paid debt win")
	check(game.cash==100000000000,"debt deducted from wallet, not merely net worth")
	print("TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
