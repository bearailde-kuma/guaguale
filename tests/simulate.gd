extends SceneTree
## Uses the actual game transactions and actual Godot RNG, not a duplicate model.
var game: Node

func _init() -> void:
	call_deferred("run")

func run() -> void:
	game = root.get_node("Game")
	game.no_save = true
	var outcomes: Array = []
	var details: Array = []
	for seed_value in range(1,101):
		game.reset()
		game.rng.seed = seed_value
		var works: int = 0
		var activities: int = 0
		var milestones: Dictionary = {}
		for turn in 10000:
			# Five seconds of scratching per ticket for an explicit pacing estimate.
			game.spirit = minf(game.max_spirit(),game.spirit+2.0)
			var tier: int = game.highest_tier()
			while tier > 0 and game.cash < int(Catalog.tickets[tier].price)*4: tier -= 1
			var reserve: int = int(Catalog.tickets[tier].price)*5
			if game.resonance < 12:
				var cost: int = int(Catalog.config.upgrade_costs[game.resonance])
				if game.cash >= cost+reserve and game.scratched >= int(Catalog.config.upgrade_gates[game.resonance]): game.buy_upgrade()
			var next_asset: int = game.owned.size()
			if next_asset < 10 and game.asset_available(next_asset) and game.cash >= int(Catalog.config.assets[next_asset].price)+reserve: game.buy_asset(next_asset)
			if game.spirit < 40:
				for i in range(3,-1,-1):
					var activity: Dictionary = Catalog.config.activities[i]
					if game.earned >= int(activity.unlock) and game.cash > int(activity.cost)*10 + reserve and game.max_spirit()-game.spirit >= minf(float(activity.restore),50.0):
						game.activity(i)
						activities += 1
						break
			if game.skill_unlocked(1) and game.spirit >= 54: game.use_skill(1)
			if game.cash < int(Catalog.tickets[tier].price):
				game.work_cooldown = 0
				game.work()
				works += 1
			if not game.buy_ticket(tier):
				push_error("Simulation could not buy")
				quit(1)
				return
			if game.skill_unlocked(2) and game.spirit >= 36:
				game.use_skill(0)
				if game.current.payout > 0: game.use_skill(2)
			for i in game.current.cells.size(): game.reveal_cell(i)
			if not milestones.has(str(game.highest_tier())): milestones[str(game.highest_tier())] = game.scratched
			if game.finished: break
		outcomes.append(game.scratched if game.finished else -1)
		details.append({"seed":seed_value,"tickets":game.scratched,"finished":game.finished,"work_sessions":works,"activities":activities,"resonance":game.resonance,"tier_milestones":milestones,"net_worth":game.net_worth()})
	outcomes.sort()
	var report: Dictionary = {"seeds":100,"completed":100-outcomes.count(-1),"min_tickets":outcomes[0],"median_tickets":outcomes[50],"p90_tickets":outcomes[89],"max_tickets":outcomes[-1],"assumed_seconds_per_ticket":5,"policy":"reinvest with five-ticket reserve; restorative activities; peek then boost; no idle earnings","runs":details}
	var file := FileAccess.open("res://docs/balance-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	var summary: Dictionary = report.duplicate()
	summary.erase("runs")
	print(JSON.stringify(summary))
	quit(0 if outcomes[0] != -1 else 1)
