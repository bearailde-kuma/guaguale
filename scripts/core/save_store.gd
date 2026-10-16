class_name SaveStore
extends RefCounted
## Versioned, atomic saves. Keep a validated backup to recover interrupted writes.
const VERSION: int = 3
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
	if int(source.get("version",2))<3:
		# Old paid boards keep their exact symbols, multipliers and no new skull.
		data.realm=0
		for i in Catalog.config.realms.size():
			var r: Dictionary = Catalog.config.realms[i]
			if int(data.get("earned",0))>=int(r.earned) and data.get("owned",[]).size()>=int(r.assets) and int(data.get("scratched",0))>=int(r.scratched): data.realm=i
		var old_earned: Array = [0,350,4000,30000,200000,2000000,20000000,150000000]
		var old_counts: Array = [0,8,25,65,120,200,320,500]
		if not data.has("unlocked_ids"): data.unlocked_ids=[]
		for i in Catalog.tickets.size():
			if int(data.get("earned",0))>=int(old_earned[i]) and int(data.get("scratched",0))>=int(old_counts[i]) and Catalog.tickets[i].id not in data.unlocked_ids: data.unlocked_ids.append(Catalog.tickets[i].id)
		if data.get("finished",false):
			data.realm=5; data.debt_stage=5; data.run_over=true
			data.last_run={"number":1,"reason":"前世已达首富，功成入轮回","won":true,"earned":data.earned,"assets":data.owned.size(),"tickets":data.scratched,"points":0,"skulls":0,"debt_paid":100000000000}
		if not current.is_empty():
			current.skull_index=-1; current.skull_seen=false; current.skull_blocked=false
	data.version = VERSION
	return data

static func board_valid(board: Variant) -> bool:
	if not board is Dictionary or not board.get("cells",null) is Array or not board.get("grades",null) is Array or not board.get("prizes",null) is Array: return false
	var rule: String = str(board.get("rule",""))
	var sizes: Dictionary = {"match3":9,"numbers":8,"dragon":6,"collect":12,"lines":9,"sum":9,"pairs":8,"vault":12,"integral":6,"path":8,"limit":4,"circuit":9,"convolution":6}
	if rule == "legacy":
		if board.cells.size() not in [3,6,9,12,15]: return false
	else:
		if not sizes.has(rule) or board.cells.size()!=sizes[rule] or board.grades.size()!=6: return false
	for grade in board.grades:
		if not number_ok(grade,100000): return false
	var prizes_needed: int = 4 if rule=="pairs" else (3 if rule in ["sum","vault","circuit"] else 0)
	if board.prizes.size()!=prizes_needed: return false
	for prize in board.prizes:
		if not number_ok(prize,100000): return false
	if rule=="limit":
		for c in board.cells:
			if not number_ok(c,1000) or int(c)==0: return false
		if int(board.cells[1])>3 or int(board.cells[3])>3: return false
	if rule=="convolution":
		if not number_ok(board.get("target",null),100) or int(board.target)<1: return false
	for cell in board.cells:
		if rule=="integral":
			if not cell is Dictionary or not number_ok(cell.get("w",null),3) or int(cell.w)<1: return false
			if not (cell.get("h",null) is float or cell.get("h",null) is int) or not is_finite(float(cell.h)) or absf(float(cell.h))>100: return false
			continue
		if rule=="path" and (not number_ok(cell,1) or float(cell)!=int(cell)): return false
		if rule=="circuit" and not number_ok(cell,15): return false
		if rule=="convolution" and (not number_ok(cell,250) or int(cell)<1): return false
		if rule in ["numbers","dragon"]:
			if not cell is Dictionary or not number_ok(cell.get("n",null),100000): return false
			if rule=="dragon" and cell.get("op","") not in ["+","*"]: return false
			if rule=="numbers" and not number_ok(cell.get("prize",null),100000): return false
		else:
			if not number_ok(cell): return false
			if rule=="pairs" and int(cell) not in range(1,7): return false
	return true

static func is_valid(data: Variant) -> bool:
	if not data is Dictionary or int(data.get("version",0)) not in [1,2,VERSION]: return false
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
		var skull_index: Variant=current.get("skull_index",-1)
		if not (skull_index is int or skull_index is float) or not is_finite(float(skull_index)): return false
		if float(skull_index)!=int(skull_index) or int(skull_index)<-1 or int(skull_index)>=current.cells.size(): return false
		if current.has("risk_chance") and not number_ok(current.risk_chance,1): return false
		for key in ["skull_seen","skull_blocked","forfeited"]:
			if current.has(key) and not current[key] is bool: return false
		if current.get("skull_seen",false) and int(skull_index)<0: return false
		if int(skull_index)>=0 and bool(current.get("skull_seen",false))!=bool(current.revealed[int(skull_index)]): return false
		for key in ["settled","boosted","seen","first","protected","luck","started"]:
			if not current.get(key,null) is bool: return false
		for flag in current.revealed:
			if not flag is bool: return false
		if bool(current.get("forfeited",false)):
			if not bool(migrated.get("run_over",false)) or bool(current.settled) or int(skull_index)<0 or not bool(current.get("skull_seen",false)) or bool(current.get("skull_blocked",false)): return false
		else:
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
	for key in ["realm","skulls","wards_used","debt_stage","run_number","meta_points","meta_total","rest_cooldown"]:
		if migrated.has(key) and not number_ok(migrated[key]): return false
	if int(migrated.get("realm",0))>5 or int(migrated.get("debt_stage",0))>5: return false
	if migrated.has("run_over") and not migrated.run_over is bool: return false
	if not migrated.get("talents",{}) is Dictionary or not migrated.get("last_run",{}) is Dictionary: return false
	var known_talents: Dictionary = {}
	for t in Catalog.config.talents: known_talents[t.id]=t.costs.size()
	for key in migrated.get("talents",{}):
		if not known_talents.has(key) or not number_ok(migrated.talents[key],known_talents[key]): return false
	return true
