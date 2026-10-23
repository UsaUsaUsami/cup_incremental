extends Node2D
## 試作 第2版（芯だけ）: 注いだ玉の価値を弾倉に溜め、最後にミニガンで敵の HP を削る。
## 1ラウンドで注げる玉は決まった数。勝てばショップでゲートを買って並べ替え、負けたら最初から。
## ゲートは 1ラウンドに働く回数が決まっていて、使い切ると玉は何も起きずに素通りする。
## 玉は価値が大きいほど大きく描き、画面の玉が多いときの ×2 は分裂でなく中の数字の倍化になる。
## PC 向けの横長（1920×1080）: 左に敵と状況、中央に盤面、右にショップ。カップはマウスに追従する。

const W := 1920.0
const H := 1080.0
const BOARD_L := 560.0
const BOARD_R := 1360.0
const BOARD_TOP := 110.0
const COLS := 4
const ROW_YS: Array[float] = [360.0, 560.0, 760.0]
const GATE_W := 160.0
const GATE_H := 52.0
const CUP_Y := 190.0
const COLLECT_Y := 930.0
const BALL_R := 8.0
const BALL_R_MAX := 30.0
const BALL_CAP := 80  # 画面に出す玉の上限。超えたら ×2 は分裂でなく価値の倍化になる
const GRAVITY := 1000.0
const POUR_RATE := 6.0
const GUN_POS := Vector2(960.0, 1010.0)
const HP_BAR := Rect2(560.0, 48.0, 800.0, 26.0)
const LEFT_X := 60.0
const RIGHT_X := 1460.0
const RIGHT_W := 400.0
const FIRE_TIME := 2.5  # 弾倉を撃ち切るまでの秒数（弾の数によらず一定）
const BULLET_RATE := 45.0  # 見た目の弾を 1秒に出す数
const BULLET_SPEED := 2600.0
const SUFFIX: Array[String] = ["", "K", "M", "B", "T", "Qa", "Qi"]

const GATE_DEFS := {
	"add": {"label": "+3", "name": "+3", "base_cost": 6.0, "color": Color(0.35, 0.75, 0.45)},
	"mul": {"label": "×2", "name": "×2", "base_cost": 14.0, "color": Color(0.35, 0.55, 0.9)},
	"sq": {"label": "x²", "name": "x²", "base_cost": 30.0, "color": Color(0.85, 0.45, 0.8)},
}

var state := "shop"  # shop / play / fire / over
var round_no := 1
var enemy_hp := 0.0
var enemy_hp_max := 0.0
var coins := 0.0
var last_reward := 0.0
var balls_left := 0
var ammo := 0.0  # 弾倉に溜まった価値の合計
var fire_t := 0.0
var fire_hp_start := 0.0
var bullet_acc := 0.0
var bullets: Array[Dictionary] = []  # {p: Vector2, v: Vector2}
var gun_spin := 0.0
var hit_shake := 0.0
var balls: Array[Dictionary] = []  # {p: Vector2, v: Vector2, val: float, passed: Dictionary}
var slots: Array = []  # null か {type, uses, flash, block}
var inventory := {}
var bought := {}
var selected := ""
var ball_level := 0
var use_level := 0
var pour_acc := 0.0
var cup_x := (BOARD_L + BOARD_R) / 2.0
var time := 0.0
var demo := false

var ui := {}
var font: Font

# 撮影モード（-- --shots=<dir> で起動）
var shots_dir := ""
var next_shot := 0.0
var shot_index := 0
const SHOT_START := 1.0
const SHOT_END := 8.0
const SHOT_INTERVAL := 0.1


func _ready() -> void:
	font = ThemeDB.fallback_font
	_build_ui()
	_new_run()
	_parse_args()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(shots_dir)
			next_shot = SHOT_START
		elif arg == "--demo":
			_setup_demo()


func _setup_demo() -> void:
	# 順番で結果が変わる盤面: 左列 +3 → x²、右列 x² → +3、中央に ×2
	demo = true
	round_no = 3
	_place(0 * COLS + 0, "add")
	_place(1 * COLS + 0, "sq")
	_place(0 * COLS + 3, "sq")
	_place(1 * COLS + 3, "add")
	_place(0 * COLS + 1, "mul")
	_place(2 * COLS + 1, "add")
	_place(1 * COLS + 2, "mul")
	_place(2 * COLS + 2, "sq")
	inventory["add"] = 0
	_start_round()


func _new_run() -> void:
	state = "shop"
	round_no = 1
	coins = 10.0
	last_reward = 0.0
	ball_level = 0
	use_level = 0
	balls.clear()
	slots.clear()
	slots.resize(COLS * ROW_YS.size())
	inventory = {"add": 1, "mul": 0, "sq": 0}
	bought = {"add": 0, "mul": 0, "sq": 0}
	selected = "add"
	enemy_hp_max = hp_for(round_no)
	enemy_hp = enemy_hp_max


# --- 数値 ---

func hp_for(r: int) -> float:
	return roundf(30.0 * pow(1.55, r - 1))


func reward_for(r: int) -> float:
	return 8.0 + 4.0 * r


func balls_per_round() -> int:
	return 20 + ball_level * 5


func gate_uses() -> int:
	return 8 + use_level * 2


func gate_cost(t: String) -> float:
	return roundf(GATE_DEFS[t]["base_cost"] * pow(1.25, bought[t]))


func ball_cost() -> float:
	return roundf(12.0 * pow(1.6, ball_level))


func use_cost() -> float:
	return roundf(10.0 * pow(1.6, use_level))


func fmt(x: float) -> String:
	if x < 1000.0:
		return "%.0f" % x
	var e := int(floor(log(x) / log(1000.0)))
	if e < SUFFIX.size():
		return "%.2f%s" % [x / pow(1000.0, e), SUFFIX[e]]
	var e10 := int(floor(log(x) / log(10.0)))
	return "%.2fe%d" % [x / pow(10.0, e10), e10]


# --- ラウンドの流れ ---

func _start_round() -> void:
	state = "play"
	enemy_hp_max = hp_for(round_no)
	enemy_hp = enemy_hp_max
	balls_left = balls_per_round()
	pour_acc = 0.0
	ammo = 0.0
	for gate in slots:
		if gate != null:
			gate["uses"] = gate_uses()


func _start_fire() -> void:
	state = "fire"
	fire_t = 0.0
	fire_hp_start = enemy_hp
	bullet_acc = 0.0


func _update_fire(delta: float) -> void:
	# 弾倉の中身を FIRE_TIME かけて一定の速さで撃ち出す。敵が倒れたらそこで止める
	fire_t += delta
	var fired := ammo * minf(fire_t / FIRE_TIME, 1.0)
	enemy_hp = fire_hp_start - fired
	gun_spin += delta * 40.0
	hit_shake = 6.0
	bullet_acc += BULLET_RATE * delta
	while bullet_acc >= 1.0:
		bullet_acc -= 1.0
		var dir := Vector2(randf_range(-0.06, 0.06), -1.0).normalized()
		bullets.append({"p": GUN_POS + dir * 40.0, "v": dir * BULLET_SPEED})
	if enemy_hp <= 0.0 or fire_t >= FIRE_TIME:
		_end_round()


func ammo_left() -> float:
	if state != "fire":
		return ammo
	return maxf(ammo * (1.0 - fire_t / FIRE_TIME), 0.0)


func _end_round() -> void:
	ammo = 0.0
	if enemy_hp <= 0.0:
		last_reward = reward_for(round_no)
		coins += last_reward
		round_no += 1
		enemy_hp_max = hp_for(round_no)
		enemy_hp = enemy_hp_max
		state = "shop"
	else:
		state = "over"


func _on_action() -> void:
	match state:
		"shop":
			_start_round()
		"over":
			_new_run()


# --- 盤面 ---

func slot_rect(idx: int) -> Rect2:
	var col := idx % COLS
	var row := idx / COLS
	var col_w := (BOARD_R - BOARD_L) / COLS
	var cx := BOARD_L + (col + 0.5) * col_w
	return Rect2(cx - GATE_W / 2.0, ROW_YS[row] - GATE_H / 2.0, GATE_W, GATE_H)


func _place(idx: int, t: String) -> void:
	slots[idx] = {"type": t, "uses": gate_uses(), "flash": 0.0, "block": 0.0}


func _tap_slot(idx: int) -> void:
	if slots[idx] != null:
		var t: String = slots[idx]["type"]
		inventory[t] += 1
		slots[idx] = null
		selected = t
	elif selected != "" and inventory[selected] > 0:
		_place(idx, selected)
		inventory[selected] -= 1


func _apply_gate(ball: Dictionary, gate: Dictionary) -> void:
	if gate["uses"] <= 0:
		gate["block"] = 0.2
		return
	gate["uses"] -= 1
	gate["flash"] = 0.15
	match gate["type"]:
		"add":
			ball["val"] += 3.0
		"sq":
			ball["val"] = ball["val"] * ball["val"]
		"mul":
			if balls.size() < BALL_CAP:
				var v: Vector2 = ball["v"]
				var clone := {"p": ball["p"], "v": Vector2(v.x - randf_range(60.0, 120.0), v.y),
					"val": ball["val"], "passed": ball["passed"].duplicate()}
				ball["v"] = Vector2(v.x + randf_range(60.0, 120.0), v.y)
				balls.append(clone)
			else:
				ball["val"] *= 2.0


# --- 毎フレーム ---

func _process(delta: float) -> void:
	time += delta
	if demo:
		cup_x = (BOARD_L + BOARD_R) / 2.0 + sin(time * 1.3) * 320.0

	if state == "play":
		pour_acc += POUR_RATE * delta
		while pour_acc >= 1.0 and balls_left > 0:
			pour_acc -= 1.0
			balls_left -= 1
			balls.append({"p": Vector2(cup_x + randf_range(-10.0, 10.0), CUP_Y + 30.0),
				"v": Vector2(randf_range(-30.0, 30.0), 60.0), "val": 1.0, "passed": {}})

	for gate in slots:
		if gate == null:
			continue
		gate["flash"] = maxf(0.0, gate["flash"] - delta)
		gate["block"] = maxf(0.0, gate["block"] - delta)

	_update_balls(delta)
	_update_bullets(delta)
	hit_shake = maxf(0.0, hit_shake - delta * 30.0)

	if state == "play" and balls_left == 0 and balls.is_empty():
		_start_fire()
	elif state == "fire":
		_update_fire(delta)

	_update_ui()
	queue_redraw()

	if shots_dir != "" and time >= next_shot:
		next_shot += SHOT_INTERVAL
		if time > SHOT_END:
			get_tree().quit()
		else:
			_save_shot()


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
		b["p"] = p
		b["v"] = v

		for row in ROW_YS.size():
			if absf(p.y - ROW_YS[row]) > GATE_H / 2.0:
				continue
			var col := int((p.x - BOARD_L) / col_w)
			var idx := row * COLS + clampi(col, 0, COLS - 1)
			var gate = slots[idx]
			if gate != null and not b["passed"].has(idx) and slot_rect(idx).has_point(p):
				b["passed"][idx] = true
				_apply_gate(b, gate)

		if p.y >= COLLECT_Y:
			ammo += b["val"]
			balls.remove_at(i)


func _update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bl := bullets[i]
		bl["p"] += bl["v"] * delta
		if bl["p"].y < HP_BAR.end.y:
			bullets.remove_at(i)


func ball_radius(val: float) -> float:
	return minf(BALL_R + 4.0 * log(maxf(val, 1.0)) / log(10.0), BALL_R_MAX)


# --- 入力 ---

func _unhandled_input(event: InputEvent) -> void:
	# カップは盤面の上にあるマウスの横位置に追従する。デモ中はマウスを無視する
	if event is InputEventMouseMotion and not demo:
		if event.position.x > BOARD_L - 40.0 and event.position.x < BOARD_R + 40.0:
			_move_cup(event.position.x)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state == "shop":
			for idx in slots.size():
				if slot_rect(idx).grow(12.0).has_point(event.position):
					_tap_slot(idx)
					break


func _move_cup(x: float) -> void:
	cup_x = clampf(x, BOARD_L + 30.0, BOARD_R - 30.0)


# --- UI ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# 左: 敵と状況
	var left := VBoxContainer.new()
	left.position = Vector2(LEFT_X, 60)
	left.custom_minimum_size = Vector2(420, 0)
	left.add_theme_constant_override("separation", 14)
	layer.add_child(left)

	var head := Label.new()
	head.add_theme_font_size_override("font_size", 44)
	left.add_child(head)
	ui["head"] = head

	var hp := Label.new()
	hp.add_theme_font_size_override("font_size", 30)
	hp.modulate = Color(1.0, 0.6, 0.55)
	left.add_child(hp)
	ui["hp"] = hp

	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", 24)
	sub.modulate = Color(1, 1, 1, 0.8)
	left.add_child(sub)
	ui["sub"] = sub

	var msg := Label.new()
	msg.add_theme_font_size_override("font_size", 24)
	msg.custom_minimum_size = Vector2(420, 0)
	msg.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	left.add_child(msg)
	ui["msg"] = msg

	# 右: ショップ
	var panel := PanelContainer.new()
	panel.position = Vector2(RIGHT_X, 60)
	panel.custom_minimum_size = Vector2(RIGHT_W, 960)
	layer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "ショップ"
	title.add_theme_font_size_override("font_size", 32)
	vb.add_child(title)

	for t in GATE_DEFS:
		ui["buy_" + t] = _make_button(vb, _buy_gate.bind(t), Vector2(RIGHT_W, 84))
	ui["balls"] = _make_button(vb, _buy_balls, Vector2(RIGHT_W, 84))
	ui["uses"] = _make_button(vb, _buy_uses, Vector2(RIGHT_W, 84))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	ui["action"] = _make_button(vb, _on_action, Vector2(RIGHT_W, 110))
	ui["action"].add_theme_font_size_override("font_size", 30)


func _make_button(parent: Control, cb: Callable, min_size: Vector2) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 26)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn


func _buy_gate(t: String) -> void:
	var cost := gate_cost(t)
	if state != "shop" or coins < cost:
		return
	coins -= cost
	bought[t] += 1
	inventory[t] += 1
	selected = t


func _buy_balls() -> void:
	var cost := ball_cost()
	if state == "shop" and coins >= cost:
		coins -= cost
		ball_level += 1


func _buy_uses() -> void:
	var cost := use_cost()
	if state == "shop" and coins >= cost:
		coins -= cost
		use_level += 1


func _update_ui() -> void:
	ui["head"].text = "ラウンド %d" % round_no
	ui["hp"].text = "敵 HP %s / %s" % [fmt(maxf(enemy_hp, 0.0)), fmt(enemy_hp_max)]
	ui["sub"].text = "コイン %s\n残りの玉 %d / %d\nゲート回数 %d" % [
		fmt(coins), balls_left if state == "play" else balls_per_round(), balls_per_round(), gate_uses()]

	var held := []
	for t in GATE_DEFS:
		held.append("%s ×%d" % [GATE_DEFS[t]["label"], inventory[t]])
	match state:
		"shop":
			var won := "勝利！ +%s コイン\n\n" % fmt(last_reward) if last_reward > 0.0 else ""
			ui["msg"].text = "%s置くゲート: %s\n手持ち: %s\n\n空きマスをクリックで置く／置いたゲートをクリックで回収" % [
				won, GATE_DEFS[selected]["label"] if selected != "" else "なし", "   ".join(held)]
			ui["action"].text = "ラウンド %d 開始\n敵 HP %s" % [round_no, fmt(enemy_hp_max)]
		"play":
			ui["msg"].text = "マウスを左右に動かしてカップで狙う"
			ui["action"].text = "注いでいる…"
		"fire":
			ui["msg"].text = "発射！ 残弾 %s" % fmt(ammo_left())
			ui["action"].text = "撃っている…"
		"over":
			ui["msg"].text = "敗北… ラウンド %d で HP が %s 残った" % [round_no, fmt(enemy_hp)]
			ui["action"].text = "最初から"
	ui["action"].disabled = state == "play" or state == "fire"

	var in_shop := state == "shop"
	for t in GATE_DEFS:
		var btn: Button = ui["buy_" + t]
		btn.text = "%s ゲートを買う   %s" % [GATE_DEFS[t]["name"], fmt(gate_cost(t))]
		btn.disabled = not in_shop or coins < gate_cost(t)
	ui["balls"].text = "玉 +5   %s" % fmt(ball_cost())
	ui["balls"].disabled = not in_shop or coins < ball_cost()
	ui["uses"].text = "ゲート回数 +2   %s" % fmt(use_cost())
	ui["uses"].disabled = not in_shop or coins < use_cost()


# --- 描画 ---

func _draw() -> void:
	# 敵の HP バー
	var shake := Vector2(randf_range(-hit_shake, hit_shake), randf_range(-hit_shake, hit_shake))
	var hp_bar := Rect2(HP_BAR.position + shake, HP_BAR.size)
	draw_rect(hp_bar, Color(1, 1, 1, 0.12))
	var ratio := clampf(enemy_hp / enemy_hp_max, 0.0, 1.0) if enemy_hp_max > 0.0 else 0.0
	draw_rect(Rect2(hp_bar.position, Vector2(hp_bar.size.x * ratio, hp_bar.size.y)), Color(0.9, 0.3, 0.3))

	# 盤面の地
	draw_rect(Rect2(BOARD_L, BOARD_TOP, BOARD_R - BOARD_L, COLLECT_Y - BOARD_TOP), Color(1, 1, 1, 0.03))
	var cup := PackedVector2Array([
		Vector2(cup_x - 48, CUP_Y - 36), Vector2(cup_x + 48, CUP_Y - 36),
		Vector2(cup_x + 34, CUP_Y + 36), Vector2(cup_x - 34, CUP_Y + 36)])
	draw_colored_polygon(cup, Color(0.95, 0.85, 0.55))

	for idx in slots.size():
		var r := slot_rect(idx)
		var gate = slots[idx]
		if gate == null:
			draw_rect(r, Color(1, 1, 1, 0.18), false, 2.0)
			draw_string(font, Vector2(r.position.x, r.get_center().y + 8), "空き",
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, Color(1, 1, 1, 0.3))
			continue
		var col: Color = GATE_DEFS[gate["type"]]["color"]
		if gate["uses"] <= 0 or gate["block"] > 0.0:
			col = col.darkened(0.6)
		elif gate["flash"] > 0.0:
			col = col.lightened(0.35)
		draw_rect(r, col)
		draw_string(font, Vector2(r.position.x, r.get_center().y + 13), GATE_DEFS[gate["type"]]["label"],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 36, Color.WHITE)
		draw_string(font, Vector2(r.position.x, r.end.y + 26), "残り %d" % gate["uses"],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color(1, 1, 1, 0.6))

	# 弾倉（回収口）とミニガン
	draw_rect(Rect2(BOARD_L, COLLECT_Y, BOARD_R - BOARD_L, 34), Color(0.9, 0.3, 0.3, 0.35))
	draw_string(font, Vector2(BOARD_L + 12, COLLECT_Y + 26), "弾倉 %s" % fmt(ammo_left()),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	_draw_gun()

	for bl in bullets:
		var tail: Vector2 = bl["p"] - bl["v"].normalized() * 26.0
		draw_line(tail, bl["p"], Color(1.0, 0.85, 0.4), 3.0)

	for b in balls:
		var val: float = b["val"]
		var mag := log(maxf(val, 1.0)) / log(10.0)
		var c := Color.from_hsv(fmod(0.12 + mag * 0.11, 1.0), 0.65, 1.0)
		var rad := ball_radius(val)
		draw_circle(b["p"], rad, c)
		if val >= 2.0:
			var fs := int(clampf(rad * 0.9, 9.0, 22.0))
			draw_string(font, b["p"] + Vector2(-rad, fs * 0.35), fmt(val),
				HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0, fs, Color(0.1, 0.1, 0.15))


func _draw_gun() -> void:
	# 銃身を回して見せる: 3本の線の横位置を回転角でずらす
	var base := Rect2(GUN_POS + Vector2(-44, 0), Vector2(88, 40))
	draw_rect(base, Color(0.35, 0.37, 0.42))
	for k in 3:
		var off := sin(gun_spin + k * TAU / 3.0) * 12.0
		var x := GUN_POS.x + off
		draw_line(Vector2(x, GUN_POS.y), Vector2(x, GUN_POS.y - 40), Color(0.6, 0.62, 0.68), 6.0)
	if state == "fire":
		draw_circle(GUN_POS + Vector2(0, -48), randf_range(10.0, 18.0), Color(1.0, 0.8, 0.3, 0.9))


func _save_shot() -> void:
	var n := shot_index
	shot_index += 1
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/frame_%03d.png" % [shots_dir, n])
