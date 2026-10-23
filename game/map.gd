class_name RunMap
extends Control
## 1章ぶんの分岐する地図。下から上へ進み、最上段のボスを倒すとクリア。
## 3本の道を下から上へ伸ばし、通った点をつないで作る（Slay the Spire の地図と同じ考え方）。

signal node_chosen(node: Dictionary)

const ROWS := 11  # 0〜9 が道中、10 がボス
const LANES := 5
const TYPE_LABEL := {"battle": "戦", "elite": "強", "shop": "店", "rest": "休", "treasure": "宝", "boss": "王"}
const TYPE_NAME := {"battle": "戦闘", "elite": "強敵", "shop": "ショップ", "rest": "休憩", "treasure": "宝箱", "boss": "ボス"}
const TYPE_COLOR := {"battle": Color(0.75, 0.78, 0.86), "elite": Color(0.95, 0.45, 0.4), "shop": Color(0.95, 0.8, 0.35),
	"rest": Color(0.45, 0.85, 0.55), "treasure": Color(0.55, 0.75, 1.0), "boss": Color(0.9, 0.3, 0.6)}

var nodes := {}  # "row,lane" → {row, lane, type, next: Array[String]}
var current := ""  # いまいる点（"" ならまだ出発前）
var visited := {}
var font: Font
var t := 0.0
var hover_key := ""


func generate() -> void:
	nodes.clear()
	visited.clear()
	current = ""
	var boss_key := "%d,%d" % [ROWS - 1, LANES / 2]
	nodes[boss_key] = {"row": ROWS - 1, "lane": LANES / 2, "type": "boss", "next": []}
	var starts := [0, 2, 4]
	starts.shuffle()
	for path in 3:
		var lane: int = starts[path] if path < 2 else randi_range(0, LANES - 1)
		var prev := ""
		for row in ROWS - 1:
			var key := "%d,%d" % [row, lane]
			if not nodes.has(key):
				nodes[key] = {"row": row, "lane": lane, "type": _pick_type(row), "next": []}
			if prev != "" and not nodes[prev]["next"].has(key):
				nodes[prev]["next"].append(key)
			prev = key
			lane = clampi(lane + randi_range(-1, 1), 0, LANES - 1)
		if not nodes[prev]["next"].has(boss_key):
			nodes[prev]["next"].append(boss_key)
	_ensure_type("shop", 3, 7)
	_ensure_type("elite", 4, 8)
	queue_redraw()


func _pick_type(row: int) -> String:
	if row == 0:
		return "battle"
	if row == ROWS - 2:
		return "rest"
	var r := randf()
	if row >= 4 and r < 0.14:
		return "elite"
	if row >= 2 and r < 0.30:
		return "shop"
	if row >= 3 and r < 0.44:
		return "rest"
	if row >= 2 and r < 0.52:
		return "treasure"
	return "battle"


func _ensure_type(type: String, from_row: int, to_row: int) -> void:
	# 少なくとも1つはある、を保証する（無ければ道中の戦闘を1つ置き換える）
	for k in nodes:
		if nodes[k]["type"] == type:
			return
	var cands := []
	for k in nodes:
		var n: Dictionary = nodes[k]
		if n["type"] == "battle" and n["row"] >= from_row and n["row"] <= to_row:
			cands.append(k)
	if not cands.is_empty():
		nodes[cands.pick_random()]["type"] = type


func choices() -> Array:
	if current == "":
		var out := []
		for k in nodes:
			if nodes[k]["row"] == 0:
				out.append(k)
		return out
	return nodes[current]["next"]


func node_pos(n: Dictionary) -> Vector2:
	var x: float = 960.0 + (n["lane"] - (LANES - 1) / 2.0) * 170.0
	if n["type"] == "boss":
		x = 960.0
	var y: float = 1020.0 - n["row"] * 82.0
	return Vector2(x, y)


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	var m := get_local_mouse_position()
	hover_key = ""
	for k in choices():
		if node_pos(nodes[k]).distance_to(m) < 36.0:
			hover_key = k
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and hover_key != "":
		var k := hover_key
		current = k
		visited[k] = true
		accept_event()
		node_chosen.emit(nodes[k])


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.11, 0.97))
	draw_string(font, Vector2(60, 120), "地図", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color(1.0, 0.9, 0.5))
	draw_string(font, Vector2(60, 170), "光っている場所から、次に進む先を選ぶ", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.75))
	# 凡例
	var lx := 1500.0
	var ly := 300.0
	for type in ["battle", "elite", "shop", "rest", "treasure", "boss"]:
		draw_circle(Vector2(lx, ly), 20.0, TYPE_COLOR[type])
		draw_string(font, Vector2(lx - 20, ly + 9), TYPE_LABEL[type], HORIZONTAL_ALIGNMENT_CENTER, 40, 22, Color(0.1, 0.1, 0.14))
		draw_string(font, Vector2(lx + 34, ly + 9), TYPE_NAME[type], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.85))
		ly += 56.0
	# 道
	var avail := choices()
	for k in nodes:
		var n: Dictionary = nodes[k]
		for nk in n["next"]:
			var a := node_pos(n)
			var b := node_pos(nodes[nk])
			var lit: bool = (k == current and avail.has(nk)) or (visited.has(k) and visited.has(nk))
			var c := Color(1.0, 0.9, 0.5, 0.9) if lit else Color(1, 1, 1, 0.16)
			var seg := 14.0
			var d := a.distance_to(b)
			var s := 0.0
			while s < d:
				draw_line(a.lerp(b, s / d), a.lerp(b, minf(s + seg * 0.6, d) / d), c, 4.0)
				s += seg
	# 点
	for k in nodes:
		var n: Dictionary = nodes[k]
		var p := node_pos(n)
		var r := 44.0 if n["type"] == "boss" else 28.0
		var col: Color = TYPE_COLOR[n["type"]]
		if visited.has(k) and k != current:
			col = col.darkened(0.55)
		if avail.has(k):
			var pulse := 0.5 + 0.5 * sin(t * 5.0)
			r += 4.0 * pulse + (6.0 if k == hover_key else 0.0)
			draw_circle(p, r + 8.0, Color(1.0, 0.9, 0.5, 0.25 + 0.25 * pulse))
		draw_circle(p, r, col)
		if k == current:
			draw_arc(p, r + 8.0, 0, TAU, 32, Color.WHITE, 4.0)
		draw_string(font, Vector2(p.x - r, p.y + r * 0.36), TYPE_LABEL[n["type"]], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0,
			int(r * 0.95), Color(0.1, 0.1, 0.14))
	if hover_key != "":
		var hp := node_pos(nodes[hover_key])
		draw_string(font, hp + Vector2(48, 10), TYPE_NAME[nodes[hover_key]["type"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
