class_name Catalog
extends RefCounted
## All economy data is editable JSON. No UI code is needed for balancing.
static var tickets: Array = []
static var config: Dictionary = {}

static func load_data() -> void:
	if not tickets.is_empty():
		return
	tickets = JSON.parse_string(FileAccess.get_file_as_string("res://data/tickets.json"))
	config = JSON.parse_string(FileAccess.get_file_as_string("res://data/progression.json"))
	assert(tickets.size() == 5, "Ticket catalog failed to load")
	assert(config.has("assets"), "Progression catalog failed to load")

static func money(value: float) -> String:
	if value >= 100000000:
		return "¥%.2f亿" % (value / 100000000.0)
	if value >= 10000:
		return "¥%.2f万" % (value / 10000.0)
	return "¥%d" % int(value)
