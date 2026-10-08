class_name Economy
extends RefCounted
## All randomness is injected; displays and audio never influence ticket outcomes.
static func roll(rng: RandomNumberGenerator, tier: int, luck: bool, misses: int, fortune: float, first: bool = false, jackpot: bool = false) -> Dictionary:
	Catalog.load_data()
	var t: Dictionary = Catalog.tickets[tier]
	var protected_win: bool = misses >= int(Catalog.config.pity_losses)
	var win: bool = first or jackpot or luck or protected_win or rng.randf() < float(t.chance)
	var grade: int = -1
	if jackpot: grade = 5
	elif first: grade = 2
	elif win:
		var choice: float = rng.randf()*100.0
		var weights: Array = Catalog.config.lucky_weights if luck else Catalog.config.payout_weights
		for i in weights.size():
			choice -= float(weights[i])
			if choice < 0.0:
				grade = i; break
	var board: Dictionary = TicketRules.make_board(t,grade,rng)
	var revealed: Array = []
	revealed.resize(board.cells.size()); revealed.fill(false)
	var result: Dictionary = {"tier":tier,"ticket_id":t.id,"board":board,"cells":board.cells,"revealed":revealed,"price":int(t.price),"fortune":fortune,"effect":1.0,"skill_factor":1,"boosted":false,"seen":false,"settled":false,"started":false,"protected":protected_win,"luck":luck,"first":first,"transmuted":false,"auto_paid":false,"auto_prepared":false,"payout":0,"multiplier":0.0}
	recalculate(result)
	return result

static func recalculate(ticket: Dictionary) -> void:
	var outcome: Dictionary = TicketRules.evaluate(ticket.board)
	ticket.base_prize = int(outcome.units)*int(ticket.price)
	ticket.multiplier = float(outcome.units)
	ticket.payout = int(round(float(ticket.base_prize)*float(ticket.fortune)*float(ticket.effect)*int(ticket.skill_factor)))
	ticket.detail = outcome.detail
	ticket.hits = outcome.hits
