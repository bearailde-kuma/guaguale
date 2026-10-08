class_name TicketRules
extends RefCounted
## Pure rule engine. Visible symbols are the only source of the base prize.
## Generation may choose a grade, but settlement always re-evaluates the board.
const LINES: Array = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]]

static func shuffle_with(values: Array, rng: RandomNumberGenerator) -> Array:
	for i in range(values.size()-1, 0, -1):
		var j: int = rng.randi_range(0,i)
		var item: Variant = values[i]
		values[i] = values[j]
		values[j] = item
	return values

static func make_board(t: Dictionary, grade: int, rng: RandomNumberGenerator) -> Dictionary:
	var units: int = 0 if grade < 0 else int(t.grades[grade])
	var cells: Array = []
	var board: Dictionary = {"rule":t.rule,"cells":cells,"prizes":[],"grades":t.grades.duplicate()}
	match str(t.rule):
		"match3":
			var counts: Dictionary = {}
			if grade >= 0:
				for i in 3: cells.append(grade+1)
				counts[grade+1] = 3
			while cells.size() < 9:
				var n: int = rng.randi_range(1,6)
				if int(counts.get(n,0)) >= 2: continue
				cells.append(n)
				counts[n] = int(counts.get(n,0))+1
			shuffle_with(cells,rng)
		"numbers":
			var pool: Array = shuffle_with(range(1,40),rng)
			cells.append({"n":pool[0],"prize":0})
			cells.append({"n":pool[1],"prize":0})
			for i in 6: cells.append({"n":pool[i+2],"prize":int(t.grades[rng.randi_range(0,5)])})
			if units > 0:
				var hit: int = rng.randi_range(2,7)
				cells[hit] = {"n":pool[rng.randi_range(0,1)],"prize":units}
		"dragon":
			var target: int = units if units > 0 else int(t.grades[rng.randi_range(2,5)])
			var factors: Array = [1]
			for factor in [2,3,4,5,6,10,12]:
				if target % factor == 0 and target / factor >= 2: factors.append(factor)
			var m: int = factors[rng.randi_range(0,factors.size()-1)]
			var base: int = int(target / m)
			var a: int = rng.randi_range(1,base-1)
			cells.append({"op":"+","n":a})
			cells.append({"op":"+","n":base-a})
			cells.append({"op":"*","n":1})
			cells.append({"op":"+","n":0})
			cells.append({"op":"*","n":m})
			cells.append({"op":"*","n":1 if units > 0 else 0})
		"collect":
			var count: int = grade+3 if grade >= 0 else rng.randi_range(0,2)
			for i in 12: cells.append(1 if i < count else 0)
			shuffle_with(cells,rng)
		"lines":
			# Rejection sampling prevents accidental winning lines on losing cards.
			for i in 9: cells.append(rng.randi_range(1,6))
			while int(evaluate(board).units) > 0:
				for i in 9: cells[i] = rng.randi_range(1,6)
			if units > 0:
				var chosen_line: Array = LINES[rng.randi_range(0,7)]
				var accepted: bool = false
				while not accepted:
					for i in 9: cells[i] = rng.randi_range(1,6)
					for i in chosen_line: cells[i] = grade+1
					var result: Dictionary = evaluate(board)
					accepted = int(result.units)==units and result.hits.size()==3

		"sum":
			var hit_row: int = rng.randi_range(0,2) if units > 0 else -1
			for row in 3:
				var a: int = rng.randi_range(3,8)
				var b: int = rng.randi_range(3,8)
				var c: int = 18-a-b if row == hit_row else rng.randi_range(1,9)
				if row != hit_row and a+b+c == 18: c = 1 if c == 9 else c+1
				cells.append(a); cells.append(b); cells.append(c)
				board.prizes.append(units if row == hit_row else int(t.grades[rng.randi_range(0,5)]))
		"pairs":
			var hit_row: int = rng.randi_range(0,3) if units > 0 else -1
			for row in 4:
				var a: int = rng.randi_range(1,6)
				cells.append(a)
				cells.append(a if row == hit_row else a%6+1)
				board.prizes.append(units if row == hit_row else int(t.grades[rng.randi_range(0,5)]))
		"vault":
			var pool: Array = shuffle_with(range(1,30),rng)
			cells.append_array(pool.slice(0,3))
			var hit_row: int = rng.randi_range(0,2) if units > 0 else -1
			for row in 3:
				var keys: Array = shuffle_with(pool.slice(0,3),rng)
				if row!=hit_row:
					var positions: Array = shuffle_with([0,1,2],rng)
					for i in rng.randi_range(1,3): keys[positions[i]] = pool[3+row*3+i]
				cells.append_array(keys)
				board.prizes.append(units if row == hit_row else int(t.grades[rng.randi_range(0,5)]))
	return board

static func evaluate(board: Dictionary) -> Dictionary:
	var cells: Array = board.cells.duplicate()
	# JSON stores numbers as floats; normalize before Array.count/membership.
	for i in cells.size():
		if cells[i] is float: cells[i] = int(cells[i])
	var total: int = 0
	var hits: Array = []
	var detail: String = "未达到中奖条件"
	match str(board.rule):
		"legacy":
			for i in cells.size():
				total += int(cells[i])
				if int(cells[i]) > 0: hits.append(i)
			detail = "v0.1 已购票 · 原金额保留"
		"match3":
			for n in range(1,7):
				if cells.count(n) >= 3:
					total += int(board.grades[n-1])
					for i in cells.size():
						if cells[i] == n: hits.append(i)
					detail = "凑齐 3 个 %d" % n
		"numbers":
			for i in range(2,cells.size()):
				if cells[i].n == cells[0].n or cells[i].n == cells[1].n:
					total += int(cells[i].prize); hits.append(i)
			if total > 0: detail = "幸运号码命中 %d 格" % hits.size()
		"dragon":
			for i in cells.size():
				if cells[i].op == "+": total += int(cells[i].n)
				else: total *= int(cells[i].n)
				hits.append(i)
			detail = "龙舟抵达终点" if total > 0 else "末位 ×0 · 龙舟奖金清零"
		"collect":
			var count: int = cells.count(1)
			if count >= 3:
				total = int(board.grades[mini(count-3,5)])
				for i in cells.size():
					if cells[i] == 1: hits.append(i)
			detail = "集得 %d 个元宝" % count
		"lines":
			var count: int = 0
			for line in LINES:
				var n: int = int(cells[line[0]])
				if n in range(1,7) and n == int(cells[line[1]]) and n == int(cells[line[2]]):
					total += int(board.grades[n-1]); hits.append_array(line); count += 1
			detail = "点亮 %d 条同号灯线" % count
		"sum":
			for row in 3:
				if int(cells[row*3])+int(cells[row*3+1])+int(cells[row*3+2]) == 18:
					total += int(board.prizes[row]); hits.append_array([row*3,row*3+1,row*3+2])
			if total > 0: detail = "十八点路线通关"
		"pairs":
			for row in 4:
				if cells[row*2] == cells[row*2+1]:
					total += int(board.prizes[row]); hits.append_array([row*2,row*2+1])
			if total > 0: detail = "同色同字脸谱配对成功"
		"vault":
			var keys: Array = cells.slice(0,3)
			for row in 3:
				var first: int = 3+row*3
				if cells[first] in keys and cells[first+1] in keys and cells[first+2] in keys:
					total += int(board.prizes[row]); hits.append_array([first,first+1,first+2])
			if total > 0: detail = "三把钥匙齐全 · 宝库开启"
	return {"units":total,"hits":hits,"detail":detail}

static func cell_text(board: Dictionary, i: int) -> String:
	var value: Variant = board.cells[i]
	match str(board.rule):
		"legacy": return Catalog.money(float(value)) if int(value)>0 else "空奖"
		"numbers": return "%02d" % int(value.n)
		"dragon": return ("+" if value.op == "+" else "×")+str(int(value.n))
		"collect": return "宝" if value == 1 else "铜"
		"pairs": return ["生","旦","净","末","丑","武"][int(value)-1]
	return "%02d" % int(value)

static func visible_hits(ticket: Dictionary) -> Array:
	var board: Dictionary = ticket.board.duplicate(true)
	if board.rule=="dragon": return []
	for i in board.cells.size():
		if ticket.revealed[i]: continue
		match str(board.rule):
			"numbers": board.cells[i] = {"n":-1000-i,"prize":0}
			"collect","legacy": board.cells[i] = 0
			_: board.cells[i] = -1000-i
	return evaluate(board).hits
