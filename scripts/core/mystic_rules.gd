class_name MysticRules
extends RefCounted
## v0.3 mathematical tickets. Exact integer evaluation; no executable formula strings.
const RULES: Array = ["integral","path","limit","circuit","convolution"]
const AREA_LEVELS: Array = [6,10,16,24,36,54]
const PATH_LEVELS: Array = [4,6,8,10,12,14]
const LIMIT_LEVELS: Array = [1,2,3,5,8,13]
const WAYS_LEVELS: Array = [1,2,4,6,10,15]
const DIRS: Array = [Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0)]
static var paths: Array = []

static func level_for(value: int, thresholds: Array) -> int:
	var result: int = -1
	for i in thresholds.size():
		if value>=int(thresholds[i]): result=i
	return result

static func path_info(cells: Array) -> Dictionary:
	var height: int = 0
	var area: int = 0
	var legal: bool = true
	for step in cells:
		height += 1 if int(step)==1 else -1
		area += height
		if height<0: legal=false
	return {"valid":legal and height==0,"height":height,"area":area}

static func coefficient(cells: Array, target: int) -> int:
	var counts: Array = []
	counts.resize(target+1); counts.fill(0); counts[0]=1
	for value in cells:
		var weight: int = int(value)
		for j in range(target,weight-1,-1): counts[j] = int(counts[j])+int(counts[j-weight])
	return int(counts[target])

static func reachable(cells: Array) -> Array:
	if (int(cells[3]) & 8)==0: return []
	var visited: Array = [3]
	var cursor: int = 0
	while cursor<visited.size():
		var i: int = visited[cursor]; cursor+=1
		var p := Vector2i(i%3,int(i/3))
		for d in 4:
			if (int(cells[i]) & (1<<d))==0: continue
			var q: Vector2i = p+DIRS[d]
			if q.x<0 or q.x>2 or q.y<0 or q.y>2: continue
			var j: int = q.y*3+q.x
			if (int(cells[j]) & (1<<((d+2)%4)))!=0 and j not in visited: visited.append(j)
	return visited

static func make_board(t: Dictionary, grade: int, rng: RandomNumberGenerator) -> Dictionary:
	var b: Dictionary = {"rule":t.rule,"cells":[],"grades":t.grades.duplicate(),"prizes":[]}
	var cells: Array = b.cells
	var units: int = 0 if grade<0 else int(t.grades[grade])
	match str(t.rule):
		"integral":
			var target: int = AREA_LEVELS[grade] if grade>=0 else rng.randi_range(-6,5)
			var partial: int = 0
			for i in 5:
				var w: int = rng.randi_range(1,3)
				var h: int = rng.randi_range(-3,5)
				cells.append({"w":w,"h":h}); partial+=w*h
			cells.append({"w":1,"h":target-partial})
			TicketRules.shuffle_with(cells,rng)
		"path":
			if paths.is_empty():
				for bits in 256:
					var steps: Array = []
					for i in 8: steps.append((bits>>i)&1)
					var info: Dictionary = path_info(steps)
					if info.valid: paths.append(steps)
			if grade>=0:
				var options: Array = []
				for path in paths:
					if level_for(int(path_info(path).area),PATH_LEVELS)==grade: options.append(path)
				cells.append_array(options[rng.randi_range(0,options.size()-1)])
			else:
				for i in 8: cells.append(rng.randi_range(0,1))
				while path_info(cells).valid:
					for i in 8: cells[i]=rng.randi_range(0,1)
		"limit":
			var denominator: int = rng.randi_range(1,5)
			var degree: int = rng.randi_range(1,3)
			cells.append_array([denominator*(LIMIT_LEVELS[grade] if grade>=0 else rng.randi_range(1,13)),degree,denominator,degree if grade>=0 else (degree%3+1)])
		"circuit":
			var row: int = rng.randi_range(0,2)
			for r in 3: b.prizes.append(units if r==row and grade>=0 else int(t.grades[rng.randi_range(0,5)]))
			for i in 9: cells.append(0)
			# An authored connected path, with random branches and masks, verified below.
			for attempt in 200:
				for i in 9: cells[i]=rng.randi_range(0,15)
				for exit_row in 3: cells[exit_row*3+2]=int(cells[exit_row*3+2]) & 13
				var path: Array = [3,4,5] if row==1 else ([3,0,1,2] if row==0 else [3,6,7,8])
				cells[3]=int(cells[3]) | 8
				for j in range(path.size()-1):
					var a: int = path[j]; var z: int = path[j+1]
					var d: int = 1 if z==a+1 else (0 if z==a-3 else 2)
					cells[a]=int(cells[a]) | (1<<d)
					cells[z]=int(cells[z]) | (1<<((d+2)%4))
				cells[row*3+2]=int(cells[row*3+2]) | 2
				if grade<0: cells[path[rng.randi_range(0,path.size()-1)]]=0
				if int(evaluate(b).units)==units: break
			# The source can always be disconnected for a losing board.
			if grade<0 and int(evaluate(b).units)>0: cells[3]=0
		"convolution":
			var scale: int = rng.randi_range(1,3)
			var templates: Array = [[1,2,4,8,16,32],[1,1,3,9,27,81],[1,1,1,1,9,27],[1,1,1,1,9,27],[1,1,1,1,1,27],[1,1,1,1,1,1]]
			if grade>=0:
				for value in templates[grade]: cells.append(int(value)*scale)
				b.target = [5,1,1,2,2,3][grade]*scale
			else:
				for i in 6: cells.append(rng.randi_range(1,5)*2)
				b.target = rng.randi_range(1,5)*2+1
			TicketRules.shuffle_with(cells,rng)
	return b

static func evaluate(b: Dictionary) -> Dictionary:
	var cells: Array = b.cells
	var level: int = -1
	var units: int = 0
	var detail: String = ""
	var hits: Array = []
	match str(b.rule):
		"integral":
			var area: int = 0
			for c in cells: area+=int(c.w)*int(c.h)
			level=level_for(area,AREA_LEVELS)
			detail="净灵气 ∫f(x)dx = %d · %s" % [area,"炼成" if level>=0 else "不足 6，丹炉熄灭"]
		"path":
			var info: Dictionary = path_info(cells)
			if info.valid: level=level_for(info.area,PATH_LEVELS)
			detail="归位且未入地 · 剑气面积 %d" % info.area if info.valid else "剑途断绝：越过地面或未回到原点"
		"limit":
			if int(cells[1])==int(cells[3]):
				var ratio: int = int(cells[0])/int(cells[2])
				if int(cells[0])%int(cells[2])==0: level=LIMIT_LEVELS.find(ratio)
				detail="同阶收敛 · 极限 = %d/%d" % [cells[0],cells[2]]
			else: detail="极限为 0，灵气散尽" if int(cells[1])<int(cells[3]) else "极限发散，无穷过载 · 空奖"
		"circuit":
			var visited: Array = reachable(cells)
			var exits: int = 0
			for row in 3:
				var i: int = row*3+2
				if i in visited and (int(cells[i]) & 2)!=0:
					units+=int(b.prizes[row]); exits+=1
			if units>0: hits=visited
			detail="灵源连通 %d 座阵眼" % exits
		"convolution":
			var count: int = coefficient(cells,int(b.target))
			level=level_for(count,WAYS_LEVELS)
			detail="[x^%d] 组合系数 = %d 种" % [b.target,count]
	if level>=0:
		units=int(b.grades[level]); hits=range(cells.size())
	return {"units":units,"hits":hits,"detail":detail}

static func cell_text(b: Dictionary, i: int) -> String:
	match str(b.rule):
		"integral": return "%d×%d" % [b.cells[i].w,b.cells[i].h]
		"path": return "升 +1" if int(b.cells[i])==1 else "降 -1"
		"limit": return ["a = ","p = ","b = ","q = "][i]+str(int(b.cells[i]))
		"circuit": return "" # Directions are rendered as pipes, not opaque bitmasks.
	return str(int(b.cells[i]))
