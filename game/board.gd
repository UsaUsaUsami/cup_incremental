class_name Board
extends Node2D
## 盤面: カップ・ゲート・ペグ・玉の動きと描画。
## 玉がゲートやペグに当たったり回収されたりすると合図（シグナル）を出す。演出（音・粒子・文字）は main 側でつける。

signal gate_passed(idx: int, type: String, pos: Vector2)
signal gate_empty(idx: int)
signal peg_hit(pos: Vector2, speed: float)
signal ball_collected(val: float, pos: Vector2)
signal block_gained(amount: int, pos: Vector2)

const BOARD_L := 560.0
const BOARD_R := 1360.0
const BOARD_TOP := 100.0
const COLS := 4
const ROW_YS: Array[float] = [330.0, 480.0, 630.0]
const PEG_YS: Array[float] = [405.0, 555.0, 705.0]
const GATE_W := 160.0
const GATE_H := 52.0
const CUP_Y := 175.0
const COLLECT_Y := 760.0
const BALL_R := 10.0
const BALL_R_MAX := 34.0
const PEG_R := 7.0
const GRAVITY := 1100.0
const POUR_RATE := 7.0
const SUFFIX: Array[String] = ["", "K", "M", "B", "T", "Qa", "Qi"]
const BOUNCE_SPEED := 877.0  # 跳ね返しの打ち上げの速さ（45 度で縦横それぞれ約 620）
const CUP_MIN := BOARD_L + 40.0
const CUP_MAX := BOARD_R - 40.0

# 値・経路・盤面・守りの4系統。kind は表示の分類にだけ使う
const GATE_DEFS := {
	"add": {"label": "+3", "desc": "値 +3", "kind": "値", "color": Color(0.35, 0.75, 0.45)},
	"mul": {"label": "×2", "desc": "値 ×2", "kind": "値", "color": Color(0.35, 0.55, 0.92)},
	"sq": {"label": "x²", "desc": "値を2乗", "kind": "値", "color": Color(0.85, 0.42, 0.8)},
	"bounce": {"label": "跳ね", "desc": "上に打ち上げる", "kind": "経路", "color": Color(0.95, 0.58, 0.22)},
	"right": {"label": "→", "desc": "玉を右の列へ", "kind": "経路", "color": Color(0.28, 0.7, 0.75)},
	"left": {"label": "←", "desc": "玉を左の列へ", "kind": "経路", "color": Color(0.28, 0.7, 0.75)},
	"cheer": {"label": "応援", "desc": "隣の効果が2回", "kind": "盤面", "color": Color(0.88, 0.76, 0.28)},
	"charge": {"label": "充電", "desc": "隣の回数 +1", "kind": "盤面", "color": Color(0.58, 0.58, 0.92)},
	"shield": {"label": "盾", "desc": "通過でブロック+1", "kind": "守り", "color": Color(0.55, 0.62, 0.72)},
	# 次のターンの準備（効果の判定は main 側で数える）
	"power": {"label": "発電", "desc": "5回で次エネ+1", "kind": "準備", "color": Color(0.95, 0.5, 0.35)},
	"scout": {"label": "索敵", "desc": "3回で次+1枚", "kind": "準備", "color": Color(0.35, 0.65, 0.95)},
}

var slots: Array = []  # null か {type, uses, max, flash, empty_flash}
var balls: Array[Dictionary] = []  # {p, v, val, passed: Dictionary, pop: float}
var pegs: Array[Vector2] = []
var highlight := {}  # 置ける候補のマス番号 → true
var cup_x := (BOARD_L + BOARD_R) / 2.0
var sweeping := false  # 狙い中: カップが一定の速さで左右に往復し、止めた位置から注ぐ
var sweep_speed := 520.0  # ピクセル/秒
var sweep_dir := 1.0
var bounce_angle := 15.0  # 跳ね返しの角度（真上からの傾き、度。左右は玉ごとにランダム）
var add_bonus := 0.0  # レリックによる + のゲートの上乗せ
var mul_bonus := 0.0  # レリックによる × のゲートの上乗せ
var to_pour := 0
var pour_acc := 0.0
var ammo_shown := 0.0
var t := 0.0

var font: Font
var glow_tex: Texture2D
var gate_box: StyleBoxTexture
var glow_layer: Node2D


func _ready() -> void:
	font = load("res://assets/fonts/MPLUSRounded1c-Bold.ttf")
	glow_tex = load("res://assets/fx/light_01.png")
	gate_box = StyleBoxTexture.new()
	gate_box.texture = load("res://assets/ui/grey_rect.png")
	gate_box.set_texture_margin_all(14)
	slots.resize(COLS * ROW_YS.size())
	reset_pegs()
	# 玉の光は加算合成の別レイヤーで描く
	glow_layer = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_layer.material = mat
	glow_layer.draw.connect(_draw_glow)
	add_child(glow_layer)


static func fmt(x: float) -> String:
	if x < 1000.0:
		return "%d" % int(x)
	var e := int(floor(log(x) / log(1000.0)))
	if e < SUFFIX.size():
		return "%.2f%s" % [x / pow(1000.0, e), SUFFIX[e]]
	var e10 := int(floor(log(x) / log(10.0)))
	return "%.2fe%d" % [x / pow(10.0, e10), e10]


static func slot_rect(idx: int) -> Rect2:
	var col := idx % COLS
	var row := idx / COLS
	var col_w := (BOARD_R - BOARD_L) / COLS
	var cx := BOARD_L + (col + 0.5) * col_w
	return Rect2(cx - GATE_W / 2.0, ROW_YS[row] - GATE_H / 2.0, GATE_W, GATE_H)


static func neighbors(idx: int) -> Array[int]:
	var col := idx % COLS
	var row := idx / COLS
	var out: Array[int] = []
	if col > 0: out.append(idx - 1)
	if col < COLS - 1: out.append(idx + 1)
	if row > 0: out.append(idx - COLS)
	if row < ROW_YS.size() - 1: out.append(idx + COLS)
	return out


## ゲートに描く文字。+ と × は強化やレリックを反映した数字にする
func gate_label(g: Dictionary) -> String:
	match g["type"]:
		"add":
			return "+%d" % (g["val"] + add_bonus)
		"mul":
			var m: float = g["val"] + mul_bonus
			return "×%d" % m if is_equal_approx(m, roundf(m)) else "×%.1f" % m
	return GATE_DEFS[g["type"]]["label"]


func ball_radius(val: float) -> float:
	return minf(BALL_R + 5.0 * log(maxf(val, 1.0)) / log(10.0), BALL_R_MAX)


## ペグを標準の互い違いの並びに戻す
func reset_pegs() -> void:
	pegs.clear()
	for k in PEG_YS.size():
		var x := BOARD_L + (60.0 if k % 2 else 110.0)
		while x < BOARD_R - 30.0:
			pegs.append(Vector2(x, PEG_YS[k]))
			x += 100.0


## ペグの並びを行ごとにランダムにずらす（ボスの仕掛け）
func shuffle_pegs() -> void:
	pegs.clear()
	for k in PEG_YS.size():
		var x := BOARD_L + randf_range(30.0, 100.0)
		while x < BOARD_R - 30.0:
			pegs.append(Vector2(x, PEG_YS[k] + randf_range(-12.0, 12.0)))
			x += randf_range(70.0, 120.0)


func clear_board() -> void:
	slots.fill(null)
	balls.clear()
	highlight.clear()


## val はゲートの効き目（+3 の 3 など）、bonus はこのゲートだけの回数の上乗せ
func place(idx: int, type: String, uses: int, val := 0.0, bonus := 0) -> void:
	slots[idx] = {"type": type, "uses": uses + bonus, "max": uses + bonus, "val": val, "bonus": bonus,
		"sealed": false, "flash": 0.0, "empty_flash": 0.0, "pop": 0.35}


func refill(uses: int) -> void:
	for g in slots:
		if g != null:
			g["uses"] = uses + g["bonus"]
			g["max"] = uses + g["bonus"]
			g["sealed"] = false


## ゲートを1つ封じる（このターンは使えない）。封じたマス番号を返す（無ければ -1）
func seal_random() -> int:
	var cands := []
	for i in slots.size():
		if slots[i] != null:
			cands.append(i)
	if cands.is_empty():
		return -1
	var i: int = cands.pick_random()
	slots[i]["sealed"] = true
	slots[i]["uses"] = 0
	return i


func empty_slots() -> Array[int]:
	var out: Array[int] = []
	for i in slots.size():
		if slots[i] == null:
			out.append(i)
	return out


func slot_at(pos: Vector2) -> int:
	for i in slots.size():
		if slot_rect(i).grow(14.0).has_point(pos):
			return i
	return -1


# --- 動き ---

func _process(delta: float) -> void:
	t += delta
	if sweeping:
		cup_x += sweep_dir * sweep_speed * delta
		if cup_x > CUP_MAX:
			cup_x = CUP_MAX
			sweep_dir = -1.0
		elif cup_x < CUP_MIN:
			cup_x = CUP_MIN
			sweep_dir = 1.0

	if to_pour > 0:
		pour_acc += POUR_RATE * delta
		while pour_acc >= 1.0 and to_pour > 0:
			pour_acc -= 1.0
			to_pour -= 1
			balls.append({"p": Vector2(cup_x + randf_range(-12.0, 12.0), CUP_Y + 34.0),
				"v": Vector2(randf_range(-40.0, 40.0), 80.0), "val": 1.0, "passed": {}, "pop": 0.0})

	for g in slots:
		if g == null:
			continue
		g["flash"] = maxf(0.0, g["flash"] - delta)
		g["empty_flash"] = maxf(0.0, g["empty_flash"] - delta)
		g["pop"] = maxf(0.0, g["pop"] - delta)

	_update_balls(delta)
	queue_redraw()
	glow_layer.queue_redraw()


func _update_balls(delta: float) -> void:
	var col_w := (BOARD_R - BOARD_L) / COLS
	for i in range(balls.size() - 1, -1, -1):
		var b := balls[i]
		var v: Vector2 = b["v"]
		v.y += GRAVITY * delta
		var p: Vector2 = b["p"] + v * delta
		var rad := ball_radius(b["val"])
		if p.x < BOARD_L + rad:
			p.x = BOARD_L + rad
			v.x = absf(v.x) * 0.6
		elif p.x > BOARD_R - rad:
			p.x = BOARD_R - rad
			v.x = -absf(v.x) * 0.6
		for peg in pegs:
			var d := p - peg
			var dist := d.length()
			var min_d := rad + PEG_R
			if dist > 0.0 and dist < min_d:
				var n := d / dist
				p = peg + n * min_d
				var vn := v.dot(n)
				if vn < 0.0:
					v -= 1.5 * vn * n
					v.x += randf_range(-90.0, 90.0)  # 当たり方で左右に散らす
					peg_hit.emit(peg, -vn)
		b["p"] = p
		b["v"] = v
		b["pop"] = maxf(0.0, b["pop"] - delta)

		for row in ROW_YS.size():
			if absf(p.y - ROW_YS[row]) > GATE_H / 2.0:
				continue
			var col := clampi(int((p.x - BOARD_L) / col_w), 0, COLS - 1)
			var idx := row * COLS + col
			var gate = slots[idx]
			if gate != null and not b["passed"].has(idx) and slot_rect(idx).has_point(p):
				b["passed"][idx] = true
				_apply_gate(b, gate, idx)

		if b["p"].y >= COLLECT_Y:
			balls.remove_at(i)
			ball_collected.emit(b["val"], b["p"])


func _apply_gate(b: Dictionary, g: Dictionary, idx: int) -> void:
	if g["uses"] < 1:
		g["empty_flash"] = 0.25
		gate_empty.emit(idx)
		return
	g["uses"] -= 1
	g["flash"] = 0.18
	b["pop"] = 0.18
	# 隣に「応援」があると効果が2回かかる（応援どうしは重ならない）
	var times := 1
	if g["type"] != "cheer":
		for k in neighbors(idx):
			if slots[k] != null and slots[k]["type"] == "cheer":
				times = 2
				break
	for _n in times:
		_effect(b, g, idx)
	gate_passed.emit(idx, g["type"], slot_rect(idx).get_center())


func _effect(b: Dictionary, g: Dictionary, idx: int) -> void:
	var type: String = g["type"]
	match type:
		"add":
			b["val"] += g["val"] + add_bonus
		"mul":
			b["val"] *= g["val"] + mul_bonus
		"sq":
			b["val"] = b["val"] * b["val"]
		"bounce":
			# 真上から bounce_angle 度、左右どちらかにランダムに傾けて打ち上げる。ほかのゲートはもう一度通れる
			var a := deg_to_rad(bounce_angle)
			var side := 1.0 if randf() < 0.5 else -1.0
			b["v"] = Vector2(side * sin(a), -cos(a)) * BOUNCE_SPEED
			b["passed"] = {idx: true}
		"right", "left":
			var col := clampi(idx % COLS + (1 if type == "right" else -1), 0, COLS - 1)
			b["p"] = Vector2(BOARD_L + (col + 0.5) * (BOARD_R - BOARD_L) / COLS, b["p"].y)
			b["v"] = Vector2(0.0, b["v"].y)
		"charge":
			for k in neighbors(idx):
				if slots[k] != null and not slots[k]["sealed"]:
					slots[k]["uses"] = mini(slots[k]["max"], slots[k]["uses"] + int(g["val"]))
		"shield":
			block_gained.emit(int(g["val"]), slot_rect(idx).get_center())


# --- 描画 ---

func _draw() -> void:
	# 盤面の地と枠
	var area := Rect2(BOARD_L - 20, BOARD_TOP, BOARD_R - BOARD_L + 40, COLLECT_Y + 34 - BOARD_TOP)
	draw_rect(area, Color(0.1, 0.11, 0.16))
	draw_rect(area, Color(1, 1, 1, 0.08), false, 3.0)

	# 狙い中は、カップの通り道と落ちる位置の目安の線を見せる
	if sweeping:
		draw_line(Vector2(CUP_MIN, CUP_Y - 56.0), Vector2(CUP_MAX, CUP_Y - 56.0), Color(1, 1, 1, 0.15), 4.0)
		var y := CUP_Y + 50.0
		while y < COLLECT_Y:
			draw_line(Vector2(cup_x, y), Vector2(cup_x, minf(y + 14.0, COLLECT_Y)), Color(1.0, 0.9, 0.55, 0.35), 3.0)
			y += 28.0

	# カップ
	var lip := CUP_Y - 40.0
	var cup := PackedVector2Array([
		Vector2(cup_x - 54, lip), Vector2(cup_x + 54, lip),
		Vector2(cup_x + 38, CUP_Y + 38), Vector2(cup_x - 38, CUP_Y + 38)])
	draw_colored_polygon(cup, Color(0.96, 0.84, 0.5))
	draw_rect(Rect2(cup_x - 60, lip - 8, 120, 12), Color(1.0, 0.92, 0.65))
	draw_line(Vector2(cup_x - 30, lip + 14), Vector2(cup_x - 22, CUP_Y + 30), Color(1, 1, 1, 0.35), 5.0)
	if to_pour > 0:
		draw_string(font, Vector2(cup_x - 60, lip - 18), "あと %d" % to_pour, HORIZONTAL_ALIGNMENT_CENTER, 120, 22,
			Color(1, 1, 1, 0.8))

	# ペグ
	for peg in pegs:
		draw_circle(peg, PEG_R, Color(0.72, 0.75, 0.84))
		draw_circle(peg + Vector2(-2, -2), 2.5, Color(1, 1, 1, 0.7))

	# ゲート
	for i in slots.size():
		var r := slot_rect(i)
		var g = slots[i]
		if g == null:
			if highlight.has(i):
				var pulse := 0.55 + 0.45 * sin(t * 6.0)
				draw_rect(r, Color(1.0, 0.85, 0.3, 0.12 + 0.12 * pulse))
				draw_rect(r, Color(1.0, 0.85, 0.3, 0.6 + 0.4 * pulse), false, 4.0)
				draw_string(font, Vector2(r.position.x, r.get_center().y + 9), "ここに置く", HORIZONTAL_ALIGNMENT_CENTER,
					r.size.x, 24, Color(1.0, 0.88, 0.4))
			else:
				draw_rect(r, Color(1, 1, 1, 0.14), false, 2.0)
			continue
		var def: Dictionary = GATE_DEFS[g["type"]]
		var col: Color = def["color"]
		if g["uses"] < 1 or g["empty_flash"] > 0.0:
			col = col.darkened(0.6)
		elif g["flash"] > 0.0:
			col = col.lightened(0.45)
		var grow: float = 10.0 * (g["pop"] / 0.35) + 4.0 * (g["flash"] / 0.18)
		var rr := r.grow(grow)
		gate_box.modulate_color = col
		draw_style_box(gate_box, rr)
		var label: String = gate_label(g)
		draw_string_outline(font, Vector2(rr.position.x, rr.get_center().y + 13), label, HORIZONTAL_ALIGNMENT_CENTER,
			rr.size.x, 36, 6, Color(0, 0, 0, 0.35))
		draw_string(font, Vector2(rr.position.x, rr.get_center().y + 13), label, HORIZONTAL_ALIGNMENT_CENTER,
			rr.size.x, 36, Color.WHITE)
		if g["sealed"]:
			draw_line(rr.position, rr.end, Color(0.9, 0.3, 0.9), 5.0)
			draw_line(Vector2(rr.position.x, rr.end.y), Vector2(rr.end.x, rr.position.y), Color(0.9, 0.3, 0.9), 5.0)
			draw_string_outline(font, Vector2(rr.end.x - 40, rr.position.y + 4), "封", HORIZONTAL_ALIGNMENT_CENTER, 40, 30, 6,
				Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(rr.end.x - 40, rr.position.y + 4), "封", HORIZONTAL_ALIGNMENT_CENTER, 40, 30,
				Color(1.0, 0.5, 1.0))
		if g["type"] == "bounce":
			# 左右どちらにも飛ぶことを示す、上向きに開いた2本の矢印
			var base := Vector2(rr.end.x - 28.0, rr.get_center().y + 14.0)
			for d in [-1.0, 1.0]:
				var tip := base + Vector2(d * 16.0, -30.0)
				draw_line(base, tip, Color.WHITE, 4.0)
				draw_line(tip, tip + Vector2(-d * 1.0, 12.0), Color.WHITE, 4.0)
				draw_line(tip, tip + Vector2(-d * 11.0, 5.0), Color.WHITE, 4.0)
		# 残り回数は点で見せる
		var n: int = g["max"]
		var dot_w := 10.0
		var x0 := r.get_center().x - (n * dot_w) / 2.0
		for k in n:
			var c := Color(1, 1, 1, 0.85) if k < g["uses"] else Color(1, 1, 1, 0.15)
			draw_circle(Vector2(x0 + k * dot_w + dot_w / 2.0, r.end.y + 12.0), 3.2, c)

	# 回収口（弾倉へ送るベルト）
	var belt := Rect2(BOARD_L - 20, COLLECT_Y, BOARD_R - BOARD_L + 40, 34)
	draw_rect(belt, Color(0.55, 0.2, 0.2))
	var stripe := fmod(t * 120.0, 40.0)
	var x := belt.position.x - 40.0 + stripe
	while x < belt.end.x:
		draw_line(Vector2(maxf(x, belt.position.x), belt.position.y), Vector2(minf(x + 20.0, belt.end.x), belt.end.y),
			Color(1, 1, 1, 0.08), 8.0)
		x += 40.0
	draw_string(font, Vector2(belt.position.x + 14, belt.position.y + 26), "弾倉  %s" % fmt(ammo_shown),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

	# 玉
	for b in balls:
		var val: float = b["val"]
		var mag := log(maxf(val, 1.0)) / log(10.0)
		var c := Color.from_hsv(fmod(0.12 + mag * 0.11, 1.0), 0.62, 1.0)
		var rad: float = ball_radius(val) * (1.0 + 0.6 * b["pop"])
		draw_circle(b["p"], rad + 2.0, c.darkened(0.45))
		draw_circle(b["p"], rad, c)
		draw_circle(b["p"] + Vector2(-rad * 0.35, -rad * 0.35), rad * 0.28, Color(1, 1, 1, 0.55))
		if val >= 2.0:
			var fs := int(clampf(rad * 0.95, 12.0, 28.0))
			draw_string_outline(font, b["p"] + Vector2(-rad * 1.5, fs * 0.36), fmt(val), HORIZONTAL_ALIGNMENT_CENTER,
				rad * 3.0, fs, 4, Color(0, 0, 0, 0.5))
			draw_string(font, b["p"] + Vector2(-rad * 1.5, fs * 0.36), fmt(val), HORIZONTAL_ALIGNMENT_CENTER,
				rad * 3.0, fs, Color.WHITE)


func _draw_glow() -> void:
	for b in balls:
		var mag := log(maxf(b["val"], 1.0)) / log(10.0)
		var c := Color.from_hsv(fmod(0.12 + mag * 0.11, 1.0), 0.7, 1.0, 0.35 + 0.5 * b["pop"])
		var s := ball_radius(b["val"]) * 5.0
		glow_layer.draw_texture_rect(glow_tex, Rect2(b["p"] - Vector2(s, s) / 2.0, Vector2(s, s)), false, c)
	for i in slots.size():
		var g = slots[i]
		if g != null and g["flash"] > 0.0:
			var r := slot_rect(i).grow(40.0)
			var c: Color = GATE_DEFS[g["type"]]["color"]
			c.a = g["flash"] / 0.18 * 0.8
			glow_layer.draw_texture_rect(glow_tex, r, false, c)
