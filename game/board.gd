class_name Board
extends Node2D
## 盤面: カップ・ゲート・ペグ・玉の動きと描画。
## 玉がゲートやペグに当たったり回収されたりすると合図（シグナル）を出す。演出（音・粒子・文字）は main 側でつける。

signal gate_passed(idx: int, type: String, pos: Vector2)
signal gate_empty(idx: int)
signal peg_hit(pos: Vector2, speed: float)
signal ball_collected(val: float, pos: Vector2, mult: float)
signal chip_gained(amount: int, pos: Vector2)

# 台（画面の主役）: 上段に敵、その下にカップ、4列×5行のゲート、底に倍率つきの受け皿
const BOARD_L := 680.0
const BOARD_R := 1640.0
const BOARD_TOP := 64.0  # 台の枠の上端
const BOARD_BOTTOM := 1072.0  # 台の枠の下端
const DIVIDER_Y := 250.0  # 上段（敵）と盤面の仕切り
const COLS := 4
# 4列×5行。行が深いほど「順番で結果が変わる」が効く。ペグはゲートの行の間に置く
const ROW_YS: Array[float] = [400.0, 500.0, 600.0, 700.0, 800.0]
const PEG_YS: Array[float] = [450.0, 550.0, 650.0, 750.0, 850.0]
const GATE_W := 190.0
const GATE_H := 44.0
# 底の受け皿: 落ちた場所で倍率が変わる（真ん中ほど高い）
const BUCKETS: Array[float] = [0.5, 1.0, 2.0, 1.0, 0.5]
const BUCKET_TOP := 960.0
const MIN_VAL := 0.001  # 玉の値の下限（÷ や 1/x で 0 や無限大にならないように）
const CUP_Y := 310.0
const COLLECT_Y := 975.0  # 玉がここまで落ちたら受け皿に入る
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
	"inv": {"label": "C/x", "desc": "値を 6÷値 に", "kind": "関数", "color": Color(0.62, 0.35, 0.85)},
	"chip": {"label": "刻み", "desc": "通るたび弾倉+2", "kind": "弾", "color": Color(0.55, 0.62, 0.72)},
	# 次のターンの準備（効果の判定は main 側で数える）
	"power": {"label": "発電", "desc": "5回で次エネ+1", "kind": "準備", "color": Color(0.95, 0.5, 0.35)},
	"scout": {"label": "索敵", "desc": "3回で次+1枚", "kind": "準備", "color": Color(0.35, 0.65, 0.95)},
	# 敵が置くデメリットゲート（プレイヤーは上に置けない）
	"div2": {"label": "÷2", "desc": "値 ÷2", "kind": "敵", "color": Color(0.55, 0.16, 0.2), "enemy": true},
	"minus": {"label": "−5", "desc": "値 −5", "kind": "敵", "color": Color(0.5, 0.2, 0.16), "enemy": true},
	"root": {"label": "√", "desc": "値を平方根に", "kind": "敵", "color": Color(0.45, 0.16, 0.35), "enemy": true},
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
var bucket_flash: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]  # 玉が入った受け皿を一瞬光らせる
var t := 0.0

var font: Font
var glow_tex: Texture2D
var gate_box: StyleBoxFlat
var glow_layer: Node2D


func _ready() -> void:
	font = Style.font()
	glow_tex = load("res://assets/fx/light_01.png")
	gate_box = Style.box(Style.PANEL, 8, 4, Style.PANEL_DARK, 5)
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
	if x <= 0.0:
		return "0"
	if x < 1.0:
		# 1 未満は小数で（0.5、0.03 など）。末尾の 0 は落とす
		var s := "%.3f" % x
		return s.rstrip("0").rstrip(".") if s != "0.000" else "0.001"
	if x < 100.0 and not is_equal_approx(x, roundf(x)):
		return "%.1f" % x
	if x < 1000.0:
		return "%d" % int(roundf(x))
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
		"inv":
			return "%d/x" % g["val"]
	return GATE_DEFS[g["type"]]["label"]


## 玉の半径は値の対数で決める。1 未満の玉は小さくなる（反転で巨大化する見せ場のため）
func ball_radius(val: float) -> float:
	return clampf(BALL_R + 5.0 * log(maxf(val, MIN_VAL)) / log(10.0), 4.0, BALL_R_MAX)


## x の位置にある受け皿の番号
static func bucket_at(x: float) -> int:
	var w := (BOARD_R - BOARD_L) / BUCKETS.size()
	return clampi(int((x - BOARD_L) / w), 0, BUCKETS.size() - 1)


## ペグを標準の互い違いの並びに戻す
func reset_pegs() -> void:
	pegs.clear()
	for k in PEG_YS.size():
		var x := BOARD_L + (60.0 if k % 2 else 120.0)
		while x < BOARD_R - 30.0:
			pegs.append(Vector2(x, PEG_YS[k]))
			x += 120.0


## ペグの並びを行ごとにランダムにずらす（ボスの仕掛け）
func shuffle_pegs() -> void:
	pegs.clear()
	for k in PEG_YS.size():
		var x := BOARD_L + randf_range(30.0, 120.0)
		while x < BOARD_R - 30.0:
			pegs.append(Vector2(x, PEG_YS[k] + randf_range(-12.0, 12.0)))
			x += randf_range(85.0, 140.0)


func clear_board() -> void:
	slots.fill(null)
	balls.clear()
	highlight.clear()


## val はゲートの効き目（+3 の 3 など）、bonus はこのゲートだけの回数の上乗せ
func place(idx: int, type: String, uses: int, val := 0.0, bonus := 0) -> void:
	slots[idx] = {"type": type, "uses": uses + bonus, "max": uses + bonus, "val": val, "bonus": bonus,
		"flash": 0.0, "empty_flash": 0.0, "pop": 0.35}


## 回数を 1ターン分に戻す（敵のデメリットゲートも同じ回数で、使い切ると素通りになる）
func refill(uses: int) -> void:
	for g in slots:
		if g != null:
			g["uses"] = uses + g["bonus"]
			g["max"] = uses + g["bonus"]


static func is_enemy_gate(g) -> bool:
	return g != null and GATE_DEFS[g["type"]].get("enemy", false)


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
	for k in bucket_flash.size():
		bucket_flash[k] = maxf(0.0, bucket_flash[k] - delta)
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
			var k := bucket_at(b["p"].x)
			bucket_flash[k] = 0.25
			ball_collected.emit(b["val"], b["p"], BUCKETS[k])


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
				if slots[k] != null:
					slots[k]["uses"] = mini(slots[k]["max"], slots[k]["uses"] + int(g["val"]))
		"chip":
			chip_gained.emit(int(g["val"]), slot_rect(idx).get_center())
		"inv":
			b["val"] = g["val"] / maxf(b["val"], MIN_VAL)
		"div2":
			b["val"] /= 2.0
		"minus":
			b["val"] -= 5.0
		"root":
			b["val"] = sqrt(maxf(b["val"], 0.0))
	b["val"] = maxf(b["val"], MIN_VAL)


# --- 描画 ---

func _draw() -> void:
	# 盤面の地と枠
	var area := Rect2(BOARD_L - 40, BOARD_TOP, BOARD_R - BOARD_L + 80, BOARD_BOTTOM - BOARD_TOP)
	draw_style_box(Style.box(Style.PANEL_DARK, 22, 8, Style.PANEL.lightened(0.15), 12), area)
	# 上段（敵のいる場所）は少し明るくして、仕切りの線を引く
	draw_rect(Rect2(area.position + Vector2(8, 8), Vector2(area.size.x - 16, DIVIDER_Y - BOARD_TOP - 8)), Color(1, 1, 1, 0.04))
	draw_line(Vector2(area.position.x + 8, DIVIDER_Y), Vector2(area.end.x - 8, DIVIDER_Y), Style.PANEL.lightened(0.15), 6.0)

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
		draw_rect(Rect2(peg - Vector2(PEG_R, PEG_R) + Vector2(0, 3), Vector2(PEG_R, PEG_R) * 2), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(peg - Vector2(PEG_R, PEG_R), Vector2(PEG_R, PEG_R) * 2), Style.INK.darkened(0.25))
		draw_rect(Rect2(peg - Vector2(PEG_R, PEG_R), Vector2(PEG_R, 4)), Style.INK)

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
		gate_box.bg_color = col
		gate_box.border_color = col.darkened(0.5)
		draw_style_box(gate_box, rr)
		var label: String = gate_label(g)
		draw_string_outline(font, Vector2(rr.position.x, rr.get_center().y + 11), label, HORIZONTAL_ALIGNMENT_CENTER,
			rr.size.x, 30, 6, Color(0, 0, 0, 0.35))
		draw_string(font, Vector2(rr.position.x, rr.get_center().y + 11), label, HORIZONTAL_ALIGNMENT_CENTER,
			rr.size.x, 30, Color.WHITE)
		if def.get("enemy", false):
			# 敵のデメリットゲート: 赤い縁と「敵」の札
			draw_rect(rr.grow(3.0), Color(1.0, 0.35, 0.35, 0.9), false, 3.0)
			var tag := Rect2(rr.position + Vector2(-6, -12), Vector2(34, 24))
			draw_rect(tag, Color(0.85, 0.2, 0.2))
			draw_string(font, Vector2(tag.position.x, tag.position.y + 19), "敵", HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 18,
				Color.WHITE)
		if g["type"] == "bounce":
			# 左右どちらにも飛ぶことを示す、上向きに開いた2本の矢印
			var base := Vector2(rr.end.x - 28.0, rr.get_center().y + 11.0)
			for d in [-1.0, 1.0]:
				var tip := base + Vector2(d * 14.0, -24.0)
				draw_line(base, tip, Color.WHITE, 4.0)
				draw_line(tip, tip + Vector2(-d * 1.0, 12.0), Color.WHITE, 4.0)
				draw_line(tip, tip + Vector2(-d * 11.0, 5.0), Color.WHITE, 4.0)
		# 残り回数は点で見せる
		var n: int = g["max"]
		var dot_w := 10.0
		var x0 := r.get_center().x - (n * dot_w) / 2.0
		for k in n:
			var c := Color(1, 1, 1, 0.85) if k < g["uses"] else Color(1, 1, 1, 0.15)
			draw_circle(Vector2(x0 + k * dot_w + dot_w / 2.0, r.end.y + 9.0), 3.0, c)

	# 底の受け皿（場所ごとの倍率）
	var bw := (BOARD_R - BOARD_L) / BUCKETS.size()
	for k in BUCKETS.size():
		var m: float = BUCKETS[k]
		var r := Rect2(BOARD_L + k * bw + 4, BUCKET_TOP, bw - 8, BOARD_BOTTOM - 20 - BUCKET_TOP)
		var col := Style.GOLD if m >= 2.0 else (Style.TEAL.darkened(0.2) if m >= 1.0 else Style.PANEL.lightened(0.1))
		if bucket_flash[k] > 0.0:
			col = col.lightened(0.4 * bucket_flash[k] / 0.25)
		draw_style_box(Style.box(col, 10, 4, col.darkened(0.55), 4), r)
		var lbl := "×%s" % ("%.1f" % m).trim_suffix(".0")
		var ink := Style.CARD_INK if m >= 2.0 else Style.INK
		draw_string(font, Vector2(r.position.x, r.get_center().y + 14), lbl, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 40, ink)
	# 受け皿の仕切り（ペグと同じドットの柱）
	for k in range(1, BUCKETS.size()):
		var x := BOARD_L + k * bw
		draw_rect(Rect2(x - 4, BUCKET_TOP - 40, 8, 40), Style.INK.darkened(0.25))

	# 玉
	for b in balls:
		var val: float = b["val"]
		var mag := log(maxf(val, MIN_VAL)) / log(10.0)
		var c := Color.from_hsv(fposmod(0.12 + mag * 0.11, 1.0), 0.62, 1.0)
		var rad: float = ball_radius(val) * (1.0 + 0.6 * b["pop"])
		draw_circle(b["p"], rad + 2.0, c.darkened(0.45))
		draw_circle(b["p"], rad, c)
		draw_circle(b["p"] + Vector2(-rad * 0.35, -rad * 0.35), rad * 0.28, Color(1, 1, 1, 0.55))
		if val >= 2.0 or val < 0.99:
			# 小さい玉は数字が入らないので、玉の上に書く
			var fs := int(clampf(rad * 0.95, 16.0, 28.0))
			var at: Vector2 = b["p"] + (Vector2(-60, fs * 0.36) if rad >= 12.0 else Vector2(-60, -rad - 4.0))
			draw_string_outline(font, at, fmt(val), HORIZONTAL_ALIGNMENT_CENTER, 120, fs, 5, Color(0, 0, 0, 0.6))
			draw_string(font, at, fmt(val), HORIZONTAL_ALIGNMENT_CENTER, 120, fs, Color.WHITE)


func _draw_glow() -> void:
	for b in balls:
		var mag := log(maxf(b["val"], MIN_VAL)) / log(10.0)
		var c := Color.from_hsv(fposmod(0.12 + mag * 0.11, 1.0), 0.7, 1.0, 0.35 + 0.5 * b["pop"])
		var s := ball_radius(b["val"]) * 5.0
		glow_layer.draw_texture_rect(glow_tex, Rect2(b["p"] - Vector2(s, s) / 2.0, Vector2(s, s)), false, c)
	for i in slots.size():
		var g = slots[i]
		if g != null and g["flash"] > 0.0:
			var r := slot_rect(i).grow(40.0)
			var c: Color = GATE_DEFS[g["type"]]["color"]
			c.a = g["flash"] / 0.18 * 0.8
			glow_layer.draw_texture_rect(glow_tex, r, false, c)
