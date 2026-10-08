extends SceneTree
## Run: godot --headless --path . --script tests/run_tests.gd -- --test
var checks: int = 0
var failures: int = 0
var game: Node

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)

func finish_ticket() -> void:
	for i in game.current.cells.size(): game.reveal_cell(i)

func run() -> void:
	game = root.get_node("Game")
	game.no_save = true
	game.reset()
	check(game.cash == 80 and game.max_spirit() == 60, "fresh start")
	check(not game.buy_ticket(4) and game.cash == 80, "locked tier cannot buy")
	check(not game.use_skill(0) and game.spirit == 60, "no skill spend without ticket")
	check(game.buy_ticket(0) and game.cash == 70, "purchase charges once")
	check(not game.buy_ticket(0) and game.cash == 70, "cannot replace pending ticket")
	check(game.use_skill(0) and game.spirit == 52, "xray consumes spirit")
	check(not game.use_skill(0) and game.spirit == 52, "xray cannot charge twice")
	check(not game.use_skill(1) and not game.use_skill(2), "locked skills rejected")
	var snapshot: Dictionary = game.snapshot()
	var next_random: int = game.rng.randi()
	game.restore(snapshot)
	check(game.rng.randi() == next_random, "RNG sequence survives save exactly")
	game.restore(snapshot)
	finish_ticket()
	check(game.cash == 120 and game.scratched == 1 and game.earned == 50, "tutorial settles visible total")
	finish_ticket()
	check(game.cash == 120 and game.scratched == 1, "settlement is idempotent")
	game.cash = 999999999999
	check(not game.buy_asset(9) and not game.buy_upgrade(), "wealth alone cannot bypass progression gates")
	game.scratched = 40
	game.earned = 100000
	check(game.use_skill(1), "arm luck before buying")
	check(game.buy_ticket(0) and game.current.luck and not game.luck_armed, "luck applies exactly once")
	check(not game.use_skill(1), "cannot reroll bought outcome with luck")
	game.start_scratching()
	check(not game.use_skill(0), "first foil damage locks skills before any cell resolves")
	var partial: Dictionary = game.snapshot()
	game.restore(partial)
	check(not game.untouched(), "partial foil lock survives save")
	game.reveal_cell(0)
	check(not game.use_skill(0), "cannot peek after reveal")
	finish_ticket()
	game.scratched = 50
	check(game.buy_asset(0) and game.buy_asset(1) and game.max_spirit() == 110, "assets increase max spirit")
	game.spirit = 110
	game.misses = 4
	check(game.buy_ticket(0) and game.current.payout > 0 and game.current.protected, "four-loss protection")
	var before: int = game.current.payout
	check(game.use_skill(2) and game.current.payout == before * 3, "multiplier triples total")
	var total: int = 0
	for cell in game.current.cells: total += int(cell)
	check(total == game.current.payout, "displayed cells sum to boosted reward")
	check(not game.use_skill(2), "cannot stack multiplier")
	finish_ticket()
	check(game.misses == 0, "win resets pity")
	game.spirit = 0
	var cash_before: int = game.cash
	check(game.activity(0) and game.spirit == 20 and game.cash == cash_before-20, "activity transaction")
	game.spirit = 0
	game.cash = 0
	check(not game.activity(0), "cannot buy unaffordable activity")
	check(game.work() and game.cash > 0, "bankruptcy recovery")
	check(not game.work(), "work cooldown cannot be spammed")
	game.rest()
	check(game.spirit == 18, "free rest fallback")
	var test_path: String = "user://test-progress.json"
	check(SaveStore.write_snapshot(game.snapshot(),test_path), "atomic save")
	var loaded: Dictionary = SaveStore.read_snapshot(test_path)
	check(not loaded.is_empty() and loaded.cash == game.cash, "save roundtrip")
	check(SaveStore.write_snapshot(game.snapshot(),test_path), "backup created")
	var broken := FileAccess.open(test_path,FileAccess.WRITE)
	broken.store_string("{broken"); broken.close()
	check(not SaveStore.read_snapshot(test_path).is_empty(), "corrupt primary recovers backup")
	check(not SaveStore.is_valid({"version":1,"cash":"NaN"}), "invalid data rejected")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(test_path+suffix): DirAccess.remove_absolute(test_path+suffix)
	# Prize distribution uses independent RNG, not global presentation randomness.
	var random := RandomNumberGenerator.new()
	random.seed = 20261008
	var wins: int = 0
	var payouts: int = 0
	for i in 20000:
		var ticket: Dictionary = Economy.roll(random,0,false,0,1.0)
		wins += 1 if ticket.payout > 0 else 0
		payouts += int(ticket.payout)
	check(absf(float(wins)/20000.0 - 0.52) < 0.02, "observed win probability")
	check(float(payouts)/200000.0 > 1.1, "base expected return remains positive")
	game.scratched = 300
	game.cash = int(Catalog.config.goal)
	game.owned.clear()
	for asset in Catalog.config.assets: game.owned.append(asset.id)
	game.commit()
	check(game.finished, "all collections plus net-worth completes game")
	print("TESTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
