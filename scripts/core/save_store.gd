class_name SaveStore
extends RefCounted
## Versioned, atomic saves. Keep a validated backup to recover interrupted writes.
const VERSION: int = 2
const PATH: String = "user://progress.json"

static func write_snapshot(snapshot: Dictionary, path: String = PATH) -> bool:
	var payload: Dictionary = snapshot.duplicate(true)
	payload["version"] = VERSION
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload))
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		var previous := JSON.new()
		if previous.parse(FileAccess.get_file_as_string(path)) == OK and is_valid(previous.data):
			DirAccess.copy_absolute(path, path + ".bak")
	return DirAccess.rename_absolute(path + ".tmp", path) == OK

static func read_snapshot(path: String = PATH) -> Dictionary:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed := JSON.new()
		if parsed.parse(FileAccess.get_file_as_string(candidate)) == OK and is_valid(parsed.data):
			return parsed.data
	return {}

static func number_ok(value: Variant, maximum: float = 9000000000000000.0) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=0.0 and float(value)<=maximum

static func migrate(source: Dictionary) -> Dictionary:
	var data: Dictionary = source.duplicate(true)
	if int(data.get("version",VERSION))==1:
		data.unlocked_ids = []
		var old_ids: Array = ["joy","bamboo","gold","dragon","fortune"]
		for i in 5:
			if int(data.get("earned",0))>=[0,1000,30000,800000,20000000][i] and int(data.get("scratched",0))>=[0,15,40,80,140][i]: data.unlocked_ids.append(old_ids[i])
	if not data.has("luck_charges"): data.luck_charges = 1 if data.get("luck_armed",false) else 0
	var current: Dictionary = data.get("current",{})
	if not current.is_empty() and not current.has("board"):
		var old_ids: Array = ["joy","bamboo","gold","dragon","fortune"]
		current.ticket_id = old_ids[int(current.tier)]
		current.tier = Catalog.tier_for_id(current.ticket_id)
		current.board = {"rule":"legacy","cells":current.cells.duplicate(),"grades":[],"prizes":[]}
		current.price = 1
		current.fortune = 1.0
		current.effect = 1.0
		current.skill_factor = 1
		current.original_payout = int(current.payout)
		current.started = bool(current.get("started",true in current.revealed))
		current.transmuted = false
		current.auto_paid = false
		current.auto_prepared = false
		Economy.recalculate(current)
	data.version = VERSION
	return data

static func board_valid(board: Variant) -> bool:
	if not board is Dictionary or not board.get("cells",null) is Array or not board.get("grades",null) is Array or not board.get("prizes",null) is Array: return false
	var rule: String = str(board.get("rule",""))
	var sizes: Dictionary = {"match3":9,"numbers":8,"dragon":6,"collect":12,"lines":9,"sum":9,"pairs":8,"vault":12}
	if rule == "legacy":
		if board.cells.size() not in [3,6,9,12,15]: return false
	else:
		if not sizes.has(rule) or board.cells.size()!=sizes[rule] or board.grades.size()!=6: return false
	for grade in board.grades:
		if not number_ok(grade,100000): return false
	var prizes_needed: int = 4 if rule=="pairs" else (3 if rule in ["sum","vault"] else 0)
	if board.prizes.size()!=prizes_needed: return false
	for prize in board.prizes:
		if not number_ok(prize,100000): return false
	for cell in board.cells:
		if rule in ["numbers","dragon"]:
			if not cell is Dictionary or not number_ok(cell.get("n",null),100000): return false
			if rule=="dragon" and cell.get("op","") not in ["+","*"]: return false
			if rule=="numbers" and not number_ok(cell.get("prize",null),100000): return false
		else:
			if not number_ok(cell): return false
			if rule=="pairs" and int(cell) not in range(1,7): return false
	return true

static func is_valid(data: Variant) -> bool:
	if not data is Dictionary or int(data.get("version",0)) not in [1,VERSION]: return false
	for key in ["cash","spirit","earned","scratched","misses","resonance"]:
		if not number_ok(data.get(key,null)): return false
	if not data.get("owned",null) is Array or not data.get("current",null) is Dictionary: return false
	Catalog.load_data()
	var known_ids: Array = []
	for asset in Catalog.config.assets: known_ids.append(asset.id)
	var seen: Array = []
	for owned_id in data.owned:
		if owned_id not in known_ids or owned_id in seen: return false
		seen.append(owned_id)
	if data.has("unlocked_ids"):
		if not data.unlocked_ids is Array: return false
		for id in data.unlocked_ids:
			if not id is String or Catalog.tier_for_id(id)<0: return false
	var current: Dictionary = data.current
	if not current.is_empty() and not current.has("board"):
		# Validate legacy before accessing or migrating its fields.
		if int(current.get("tier",-1)) not in range(5): return false
		if not current.get("cells",null) is Array or not current.get("revealed",null) is Array: return false
		if current.cells.size()!=[3,6,9,12,15][int(current.tier)]: return false
		if not number_ok(current.get("payout",null)): return false
		var legacy_total: int = 0
		for value in current.cells:
			if not number_ok(value): return false
			legacy_total += int(value)
		if legacy_total!=int(current.payout): return false
	var migrated: Dictionary = migrate(data)
	current = migrated.current
	if not current.is_empty():
		if int(current.get("tier",-1)) not in range(Catalog.tickets.size()): return false
		if current.get("ticket_id","")!=Catalog.tickets[int(current.tier)].id: return false
		if not board_valid(current.get("board",null)): return false
		if not current.get("cells",null) is Array or current.cells!=current.board.cells: return false
		if not current.get("revealed",null) is Array or current.cells.size()!=current.revealed.size(): return false
		for key in ["settled","boosted","seen","first","protected","luck","started"]:
			if not current.get(key,null) is bool: return false
		for flag in current.revealed:
			if not flag is bool: return false
		if current.settled != (not false in current.revealed): return false
		if true in current.revealed and not current.started: return false
		for key in ["price","fortune","effect","skill_factor"]:
			if not number_ok(current.get(key,null),1000000): return false
		if not number_ok(current.get("payout",null)): return false
		var computed: Dictionary = current.duplicate(true)
		Economy.recalculate(computed)
		if int(computed.payout)!=int(current.payout): return false
	for key in ["luck_charges","chain_left","burst_ready_at","auto_tier","auto_level","auto_reserve","auto_tickets","auto_earned","skill_profit","biggest_win"]:
		if migrated.has(key) and not number_ok(migrated[key]): return false
	if migrated.has("buffs"):
		if not migrated.buffs is Dictionary: return false
		for value in migrated.buffs.values():
			if not number_ok(value,24): return false
	return true
