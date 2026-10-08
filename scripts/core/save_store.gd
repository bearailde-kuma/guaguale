class_name SaveStore
extends RefCounted
## Versioned, atomic saves. Keep a validated backup to recover interrupted writes.
const VERSION: int = 1
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

static func is_valid(data: Variant) -> bool:
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		return false
	for key in ["cash", "spirit", "earned", "scratched", "misses", "resonance"]:
		if not data.has(key) or not (data[key] is float or data[key] is int):
			return false
		if not is_finite(float(data[key])) or float(data[key]) < 0.0 or float(data[key]) > 9000000000000000:
			return false
	if not data.get("owned", null) is Array or not data.get("current", null) is Dictionary:
		return false
	Catalog.load_data()
	var known_ids: Array = []
	for asset in Catalog.config.assets: known_ids.append(asset.id)
	var seen: Array = []
	for owned_id in data.owned:
		if owned_id not in known_ids or owned_id in seen: return false
		seen.append(owned_id)
	var current: Dictionary = data.current
	if not current.is_empty():
		if int(current.get("tier", -1)) not in range(5):
			return false
		for key in ["payout", "cells", "revealed", "settled", "boosted", "seen", "multiplier", "first", "protected", "luck"]:
			if not current.has(key):
				return false
		if not current.cells is Array or not current.revealed is Array or current.cells.size() != current.revealed.size():
			return false
		if current.cells.size() != int(Catalog.tickets[int(current.tier)].cells): return false
		var sum: int = 0
		for i in current.cells.size():
			if not (current.cells[i] is int or current.cells[i] is float) or not current.revealed[i] is bool: return false
			if not is_finite(float(current.cells[i])) or float(current.cells[i]) < 0: return false
			sum += int(current.cells[i])
		if not (current.payout is float or current.payout is int) or sum != int(current.payout): return false
		for key in ["settled", "boosted", "seen", "first", "protected", "luck"]:
			if not current[key] is bool: return false
		if current.settled != (not false in current.revealed): return false
	return true
