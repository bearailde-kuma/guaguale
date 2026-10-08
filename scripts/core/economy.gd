class_name Economy
extends RefCounted
## Pure reward generation: injected RNG makes simulations reproducible.
static func roll(rng: RandomNumberGenerator, tier: int, luck: bool, misses: int, fortune: float, first: bool = false) -> Dictionary:
	Catalog.load_data()
	var ticket: Dictionary = Catalog.tickets[tier]
	var chance: float = minf(0.92, float(ticket.chance) + (0.25 if luck else 0.0))
	var protected_win: bool = misses >= int(Catalog.config.pity_losses)
	var win: bool = first or protected_win or rng.randf() < chance
	var multiplier: float = 0.0
	if first:
		multiplier = 5.0
	elif win:
		var choice: float = rng.randf() * 100.0
		var weights: Array = Catalog.config.payout_weights
		for index in weights.size():
			choice -= float(weights[index])
			if choice <= 0.0:
				multiplier = float(ticket.jackpot) if index == 4 else float(Catalog.config.payout_multipliers[index])
				break
	var payout: int = int(round(float(ticket.price) * multiplier * fortune))
	var cells: Array = []
	var revealed: Array = []
	for i in int(ticket.cells):
		cells.append(0)
		revealed.append(false)
	if payout > 0:
		var parts: int = mini(int(ticket.cells), rng.randi_range(1, 3))
		var remaining: int = payout
		var available: Array = range(int(ticket.cells))
		for i in parts:
			var offset: int = rng.randi_range(0, available.size() - 1)
			var cell: int = available.pop_at(offset)
			var part: int = remaining if i == parts - 1 else int(payout / parts)
			cells[cell] = part
			remaining -= part
	return {"tier":tier,"payout":payout,"cells":cells,"revealed":revealed,"multiplier":multiplier,"boosted":false,"seen":false,"settled":false,"started":false,"protected":protected_win,"luck":luck,"first":first}
