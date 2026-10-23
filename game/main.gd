extends Node2D
## カップ×ゲート×ミニガンのデッキ構築ローグライト（PC 向け 1920×1080）。
## ランの流れ: タイトル → 地図 → 戦闘・強敵・ショップ・休憩・宝箱 → … → ボス → クリア。
## 戦闘: 毎ターン手札を引き、エネルギーを払ってカードを出す。ゲートのカードは光った候補マスに置く。
## 「注ぐ」でカップが左右に動き出し、止めた位置から玉を注ぐ。玉は弾倉に溜まり、ミニガンが敵を撃つ。
## 敵が残れば敵の番（攻撃・守り・強化・妨害）。盤面は戦闘ごとにリセットし、デッキはランを通して育つ。

const HAND_SIZE := 5
const HAND_MAX := 9
const ENERGY := 4
const CANDIDATES := 5  # ゲートを置ける候補として光るマスの数
const BALLS_PER_TURN := 10
const GATE_USES := 6
const FIRE_TIME := 2.0
const START_HP := 60
const START_GOLD := 99
const SWEEP_SPEED := 520.0
const REMOVE_PRICE := 75
const GUN_POS := Vector2(1450.0, 800.0)
const ENEMY_POS := Vector2(1665.0, 340.0)
const ENEMY_R := 110.0
const BULLET_SPEED := 2600.0
const BULLET_RATE := 32.0
const DECK_POS := Vector2(110.0, 980.0)
const DISCARD_POS := Vector2(1810.0, 1040.0)

var R := {}  # ラン全体: hp, max_hp, gold, deck, relics, floor
var S := {}  # いまの戦闘
var screen := "title"
var board: Board
var fx: Fx
var cam: Camera2D
var font: Font
var run_map: RunMap
var ui := {}
var hand_cards: Array = []
var panel: Control  # いま開いている画面（報酬・ショップ・休憩など）
var visible_world := false  # 敵・銃・弾を描くか（戦闘中だけ）

var fire_t := 0.0
var fire_hp_start := 0.0
var fire_block_start := 0.0
var bullet_acc := 0.0
var bullets: Array[Dictionary] = []
var gun_spin := 0.0
var recoil := 0.0
var enemy_flash := 0.0
var enemy_offset := Vector2.ZERO
var enemy_scale := 1.0
var hp_trail := 0.0
var dmg_window := 0.0
var dmg_window_t := 0.0
var shake := 0.0
var phase_timer := 0.0
var time := 0.0
var pass_counts := {}  # このターンにゲート（マス番号）を玉が通った回数

var demo := false
var demo_kind := ""
var shots_dir := ""
var next_shot := 0.0
var shot_index := 0
const SHOT_START := 0.3
const SHOT_END := 10.5
const SHOT_INTERVAL := 0.1


func _ready() -> void:
	font = load("res://assets/fonts/MPLUSRounded1c-Bold.ttf")
	cam = Camera2D.new()
	cam.position = Vector2(960, 540)
	add_child(cam)
	cam.make_current()

	board = Board.new()
	add_child(board)
	fx = Fx.new()
	add_child(fx)
	board.gate_passed.connect(_on_gate_passed)
	board.peg_hit.connect(_on_peg_hit)
	board.ball_collected.connect(_on_ball_collected)
	board.block_gained.connect(_on_block_gained)

	_build_hud()
	_build_top_bar()
	run_map = RunMap.new()
	run_map.font = font
	run_map.size = Vector2(1920, 1080)
	run_map.node_chosen.connect(_on_map_node)
	ui["screens"].add_child(run_map)
	ui["screens"].move_child(run_map, 0)

	R = _new_run()
	S = _empty_battle()
	_parse_args()
	if not demo:
		_show_title()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(shots_dir)
			next_shot = SHOT_START
		elif arg.begins_with("--demo"):
			demo = true
			demo_kind = arg.trim_prefix("--demo").trim_prefix("-")
	if demo:
		_run_demo()


# ============================================================
# ラン
# ============================================================

func _new_run() -> Dictionary:
	return {"hp": START_HP, "max_hp": START_HP, "gold": START_GOLD, "deck": Data.START_DECK.duplicate(),
		"relics": [], "floor": 0, "removed": false}


func has_relic(id: String) -> bool:
	return R["relics"].has(id)


func _start_run() -> void:
	R = _new_run()
	run_map.generate()
	_show_map()


func _show_title() -> void:
	screen = "title"
	_set_battle_visible(false)
	run_map.visible = false
	ui["top"].visible = false
	var p := _open_panel("")
	var t := _label(p, Vector2(0, 250), 96, Color(1.0, 0.88, 0.5))
	t.text = "カップ × ゲート × ミニガン"
	t.size = Vector2(1920, 120)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label(p, Vector2(0, 400), 32, Color(1, 1, 1, 0.75))
	sub.text = "玉を注いで、ゲートで増やして、撃ち抜くデッキ構築ローグライト（試作）"
	sub.size = Vector2(1920, 50)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(p, Vector2(760, 560), Vector2(400, 110), "はじめる", _start_run, "blue")
	_button(p, Vector2(760, 700), Vector2(400, 90), "音量", _toggle_volume, "grey")
	var help := _label(p, Vector2(0, 900), 24, Color(1, 1, 1, 0.5))
	help.text = "カードをクリック → 光ったマスに置く　／　スペースかボタンで注ぐ → もう一度で止める　／　右クリックで選択取り消し"
	help.size = Vector2(1920, 40)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _show_map() -> void:
	_close_panel()
	screen = "map"
	_set_battle_visible(false)
	ui["top"].visible = true
	run_map.visible = true
	run_map.queue_redraw()


func _on_map_node(node: Dictionary) -> void:
	fx.sound("click")
	R["floor"] = node["row"] + 1
	run_map.visible = false
	match node["type"]:
		"battle":
			var pool := Data.EASY_POOL if node["row"] < 3 else Data.NORMAL_POOL
			_start_battle(pool.pick_random())
		"elite":
			_start_battle(Data.ELITE_POOL.pick_random())
		"boss":
			_start_battle("pegking")
		"shop":
			_show_shop()
		"rest":
			_show_rest()
		"treasure":
			_show_treasure()


# ============================================================
# 戦闘の流れ
# ============================================================

func _empty_battle() -> Dictionary:
	return {"phase": "none", "block": 0, "draw": [], "discard": [], "exhaust": [], "hand": [], "energy": 0,
		"balls": 0, "ammo": 0.0, "ammo_mul": 1.0, "per_ball": 0, "next_energy": 0, "next_draw": 0,
		"enemy": Data.scaled_enemy("slime", 1), "selected": -1, "turn": 0, "debuff": {}}


func _start_battle(enemy_id: String) -> void:
	_close_panel()
	screen = "battle"
	run_map.visible = false
	ui["top"].visible = true
	_set_battle_visible(true)
	S = _empty_battle()
	S["enemy"] = Data.scaled_enemy(enemy_id, R["floor"])
	S["draw"] = R["deck"].duplicate()
	S["draw"].shuffle()
	board.clear_board()
	board.reset_pegs()
	board.add_bonus = 1.0 if has_relic("whetstone") else 0.0
	board.mul_bonus = 0.5 if has_relic("double") else 0.0
	hp_trail = S["enemy"]["hp"]
	enemy_scale = 0.0
	enemy_offset = Vector2.ZERO
	create_tween().tween_property(self, "enemy_scale", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var kind := "ボス" if S["enemy"].get("boss", false) else ("強敵" if S["enemy"].get("elite", false) else "戦闘")
	ui["title"].text = "%s — %s" % [kind, S["enemy"]["name"]]
	_start_turn()
	if S["enemy"].has("rule"):
		fx.float_text(Vector2(960, 400), S["enemy"]["rule"], Color(1.0, 0.6, 0.9), 40, 40.0, 2.0)


func _start_turn() -> void:
	S["turn"] += 1
	S["phase"] = "turn"
	S["energy"] = ENERGY + S["next_energy"] + (1 if has_relic("hourglass") and S["turn"] == 1 else 0)
	S["balls"] = BALLS_PER_TURN + (2 if has_relic("heavy_cup") else 0)
	S["block"] = 3 if has_relic("iron") else 0
	S["ammo"] = 0.0
	S["ammo_mul"] = 1.2 if has_relic("belt") else 1.0
	S["per_ball"] = 0
	S["selected"] = -1
	var draw_n: int = HAND_SIZE + S["next_draw"] + (1 if has_relic("pocket") else 0)
	S["next_energy"] = 0
	S["next_draw"] = 0
	pass_counts.clear()
	board.highlight.clear()

	# 敵の妨害は、このターンだけ効く
	var debuff: Dictionary = S["debuff"]
	var uses := GATE_USES + (2 if has_relic("oil") else 0) - int(debuff.get("drain", 0))
	board.refill(maxi(uses, 1))
	board.sweep_speed = SWEEP_SPEED * (0.65 if has_relic("scope") else 1.0) * (1.7 if debuff.get("fast", false) else 1.0)
	var notes := []
	if debuff.get("seal", false):
		var i := board.seal_random()
		if i >= 0:
			notes.append("ゲートが1つ封じられた")
	if debuff.get("drain", 0) > 0:
		notes.append("ゲートの回数 -%d" % debuff["drain"])
	if debuff.get("fast", false):
		notes.append("カップが速い")
	S["debuff"] = {}
	if S["enemy"].get("boss", false):
		board.shuffle_pegs()
		notes.append("ペグの並びが変わった")

	_rebuild_hand()
	_draw_cards(draw_n)
	var base := "カードを選ぶ。ゲートは光ったマスに置く（右クリックで取り消し）"
	_say(base if notes.is_empty() else "【妨害】" + "・".join(notes) + "\n" + base)


## 山札から n 枚引いて手札に加える。山札が尽きたら捨て札を混ぜて山札にする
func _draw_cards(n: int) -> void:
	var drawn := 0
	for k in n:
		if S["hand"].size() >= HAND_MAX:
			break
		if S["draw"].is_empty():
			S["draw"] = S["discard"].duplicate()
			S["draw"].shuffle()
			S["discard"] = []
		if S["draw"].is_empty():
			break
		var id: String = S["draw"].pop_back()
		S["hand"].append(id)
		var card := _make_hand_card(id)
		card.position = DECK_POS - Card.SIZE / 2.0
		card.scale = Vector2.ONE * 0.3
		card.modulate.a = 0.0
		drawn += 1
	_layout_hand()
	var first := hand_cards.size() - drawn
	for k in drawn:
		var card: Card = hand_cards[first + k]
		var tw := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position", card.base_pos, 0.35).set_delay(k * 0.07)
		tw.tween_property(card, "scale", Vector2.ONE, 0.35).set_delay(k * 0.07)
		tw.tween_property(card, "modulate:a", 1.0, 0.2).set_delay(k * 0.07)
		get_tree().create_timer(k * 0.07).timeout.connect(fx.sound.bind("tap", -14.0, 1.2))


func _play_card(i: int) -> void:
	if S["phase"] != "turn" or i < 0 or i >= S["hand"].size():
		return
	var id: String = S["hand"][i]
	var card := Data.info(id)
	if S["energy"] < card["cost"]:
		_say("エネルギーが足りない")
		return
	if not card.has("gate"):
		# 先に手札から出してから効果を出す（引く効果で手札の並びが変わるため）
		S["energy"] -= card["cost"]
		_discard_card(i, true, DISCARD_POS, card.get("exhaust", false))
		_instant(id)
		fx.sound("tap")
		return
	if S["selected"] == i:
		_cancel_select()
		return
	var empty := board.empty_slots()
	if empty.is_empty():
		_say("盤面が埋まっていて置けない")
		return
	# 候補マスはカード1枚ごとに一度だけ抽選する（選び直しても変わらない）。埋まったマスは外し、全部埋まったときだけ引き直す
	var card_node: Card = hand_cards[i]
	var cands: Array = card_node.candidates.filter(func(k): return board.slots[k] == null)
	if cands.is_empty():
		empty.shuffle()
		cands = empty.slice(0, CANDIDATES)
		card_node.candidates = cands
	S["selected"] = i
	board.highlight.clear()
	for k in cands:
		board.highlight[k] = true
	fx.sound("click")
	_say("%s：%s\n光ったマスを選ぶ" % [card["name"], Data.gate_desc(id)])


func _cancel_select() -> void:
	S["selected"] = -1
	board.highlight.clear()
	_say("カードを選ぶ。ゲートは光ったマスに置く（右クリックで取り消し）")


func _place_selected(slot: int) -> void:
	var i: int = S["selected"]
	var id: String = S["hand"][i]
	var card := Data.info(id)
	S["energy"] -= card["cost"]
	board.place(slot, card["gate"], GATE_USES + (2 if has_relic("oil") else 0), card.get("val", 0.0), card.get("uses_bonus", 0))
	board.highlight.clear()
	S["selected"] = -1
	var c: Color = Board.GATE_DEFS[card["gate"]]["color"]
	fx.burst(Board.slot_rect(slot).get_center(), c, 18, 380.0, 34.0, 0.4, "star_06")
	fx.sound("tink", -4.0, 0.8)
	_discard_card(i, false, Board.slot_rect(slot).get_center())
	_say("カードを選ぶ。ゲートは光ったマスに置く（右クリックで取り消し）")


func _instant(id: String) -> void:
	var v: float = Data.info(id)["val"]
	match Data.base_id(id):
		"more":
			S["balls"] += int(v)
			fx.float_text(Vector2(board.cup_x, Board.CUP_Y - 70), "玉 +%d" % v, Color(1.0, 0.9, 0.5))
		"guard":
			_add_block(int(v), Vector2(280, 230))
		"heal":
			R["hp"] = mini(R["max_hp"], R["hp"] + int(v))
			fx.float_text(Vector2(280, 170), "+%d" % v, Color(0.5, 1.0, 0.6), 40)
		"load":
			S["ammo_mul"] *= v
			fx.float_text(Vector2(960, 730), "弾倉 ×%.1f" % v, Color(1.0, 0.75, 0.4))
		"burst":
			S["per_ball"] += int(v)
			fx.float_text(Vector2(960, 730), "玉ごと +%d" % v, Color(1.0, 0.6, 0.4))
		"focus":
			S["energy"] += int(v)
			fx.float_text(Vector2(125, 330), "+%d" % v, Color(1.0, 0.75, 0.35), 44)
			_punch(ui["energy"])
		"refill", "prep":
			_draw_cards(int(v))
		"save":
			S["next_energy"] += int(v)
			fx.float_text(Vector2(125, 330), "次ターン +%d" % v, Color(1.0, 0.75, 0.35), 30)


func _add_block(n: int, pos: Vector2) -> void:
	S["block"] += n
	fx.float_text(pos, "ブロック +%d" % n, Color(0.6, 0.8, 1.0), 30, 50.0, 0.6)
	_punch(ui["block"])


## ターン終了: 手札を捨て、カップが左右に動き出す（狙い）。クリックかスペースで止めると注ぐ
func _pour() -> void:
	if S["phase"] != "turn":
		return
	S["phase"] = "aim"
	_cancel_select()
	for i in range(S["hand"].size() - 1, -1, -1):
		_discard_card(i, false)
	board.sweeping = true
	fx.sound("click")
	_say("カップが動いている。\nクリックかスペースで止めると、そこから注ぐ")


func _lock_cup() -> void:
	if S["phase"] != "aim":
		return
	S["phase"] = "pour"
	board.sweeping = false
	board.to_pour = S["balls"]
	fx.sound("tink", -4.0, 0.7)
	fx.burst(Vector2(board.cup_x, Board.CUP_Y - 40.0), Color(1.0, 0.9, 0.55), 14, 300.0, 28.0, 0.35, "star_06", 0.0)
	_say("注いでいる…")


func _on_pour_button() -> void:
	if S["phase"] == "turn":
		_pour()
	elif S["phase"] == "aim":
		_lock_cup()


func _discard_card(i: int, instant_fx: bool, target := DISCARD_POS, exhaust := false) -> void:
	if exhaust:
		S["exhaust"].append(S["hand"][i])
	else:
		S["discard"].append(S["hand"][i])
	S["hand"].remove_at(i)
	var card: Card = hand_cards[i]
	hand_cards.remove_at(i)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := card.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if instant_fx:
		tw.tween_property(card, "position:y", card.position.y - 160, 0.3)
		tw.tween_property(card, "modulate:a", 0.0, 0.3)
	else:
		tw.tween_property(card, "position", target - Card.SIZE / 2.0, 0.28)
		tw.tween_property(card, "scale", Vector2.ONE * 0.3, 0.28)
		tw.tween_property(card, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(card.queue_free)
	_layout_hand()


func _process(delta: float) -> void:
	time += delta
	if demo and S["phase"] == "aim":
		# デモでは2列目の真上に来たところで止める
		var target := Board.BOARD_L + 1.5 * (Board.BOARD_R - Board.BOARD_L) / Board.COLS
		if absf(board.cup_x - target) < 12.0:
			_lock_cup()

	if screen == "battle":
		match S["phase"]:
			"pour":
				if board.to_pour == 0 and board.balls.is_empty():
					_start_fire()
			"fire":
				_update_fire(delta)
			"enemy":
				phase_timer -= delta
				if phase_timer <= 0.0:
					if R["hp"] <= 0:
						R["hp"] = 0
						S["phase"] = "over"
						_show_game_over()
					else:
						_start_turn()

	_update_bullets(delta)
	gun_spin += delta * (40.0 if S["phase"] == "fire" else 2.0)
	recoil = maxf(0.0, recoil - delta * 60.0)
	enemy_flash = maxf(0.0, enemy_flash - delta * 6.0)
	shake = maxf(0.0, shake - delta * 50.0)
	cam.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	var e: Dictionary = S["enemy"]
	hp_trail = move_toward(hp_trail, maxf(e["hp"], 0.0), e["max"] * delta * 0.7) if hp_trail > e["hp"] else maxf(e["hp"], 0.0)
	board.ammo_shown = _ammo_left()
	_update_ui()
	queue_redraw()

	if shots_dir != "" and time >= next_shot:
		next_shot += SHOT_INTERVAL
		if time > SHOT_END:
			get_tree().quit()
		else:
			_save_shot()


# --- 撃つ ---

func _start_fire() -> void:
	S["ammo"] *= S["ammo_mul"]
	S["phase"] = "fire"
	fire_t = 0.0
	fire_hp_start = S["enemy"]["hp"]
	fire_block_start = S["enemy"]["block"]
	bullet_acc = 0.0
	dmg_window = 0.0
	dmg_window_t = 0.0
	_say("発射！")
	if S["ammo"] <= 0.0:
		fire_t = FIRE_TIME


func _ammo_left() -> float:
	if S.get("phase", "") == "fire":
		return maxf(S["ammo"] * (1.0 - fire_t / FIRE_TIME), 0.0)
	return S.get("ammo", 0.0)


func _update_fire(delta: float) -> void:
	var before: float = S["enemy"]["hp"]
	fire_t += delta
	# 撃った量は、まず敵のブロックを削り、残りが HP に入る
	var fired: float = S["ammo"] * minf(fire_t / FIRE_TIME, 1.0)
	S["enemy"]["block"] = maxf(fire_block_start - fired, 0.0)
	S["enemy"]["hp"] = fire_hp_start - maxf(fired - fire_block_start, 0.0)
	dmg_window += before - S["enemy"]["hp"]
	dmg_window_t += delta

	if S["ammo"] > 0.0:
		var dir := (ENEMY_POS - GUN_POS).normalized()
		bullet_acc += BULLET_RATE * delta
		while bullet_acc >= 1.0:
			bullet_acc -= 1.0
			var d := dir.rotated(randf_range(-0.05, 0.05))
			var muzzle := GUN_POS + dir * 145.0
			bullets.append({"p": muzzle, "v": d * BULLET_SPEED})
			fx.flash(muzzle, "muzzle_0%d" % randi_range(1, 2), 120.0, dir.angle() + PI / 2.0, 0.06, Color(1.0, 0.8, 0.4))
			fx.sound("gun", -8.0, 1.1)
			recoil = 10.0
			shake = maxf(shake, 3.0)
		if dmg_window_t > 0.12 and dmg_window > 0.0:
			fx.float_text(ENEMY_POS + Vector2(randf_range(-80, 80), randf_range(-60, 20)), Board.fmt(dmg_window),
				Color(1.0, 0.95, 0.6), 34, 80.0, 0.7)
			dmg_window = 0.0
			dmg_window_t = 0.0

	if S["enemy"]["hp"] <= 0.0 or fire_t >= FIRE_TIME:
		S["ammo"] = 0.0
		if S["enemy"]["hp"] <= 0.0:
			S["enemy"]["hp"] = 0.0
			_enemy_defeated()
		else:
			_enemy_turn()


func _update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bl := bullets[i]
		bl["p"] += bl["v"] * delta
		if bl["p"].distance_to(ENEMY_POS) < ENEMY_R * 0.8:
			bullets.remove_at(i)
			var blocked: bool = S["enemy"]["block"] > 0.0
			fx.burst(bl["p"], Color(0.6, 0.8, 1.0) if blocked else Color(1.0, 0.75, 0.35), 5, 260.0, 20.0, 0.25,
				"spark_04", 200.0)
			fx.sound("block" if blocked else "hit", -16.0 if blocked else -10.0)
			enemy_flash = 1.0
		elif bl["p"].y < -50.0 or bl["p"].x > 2000.0:
			bullets.remove_at(i)


func _enemy_defeated() -> void:
	S["phase"] = "won"
	# ヒットストップ: 一瞬だけ時間を止めてから倒れる
	Engine.time_scale = 0.05
	get_tree().create_timer(0.1, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
	shake = 22.0
	fx.burst(ENEMY_POS, Color(1.0, 0.85, 0.4), 40, 700.0, 60.0, 0.9, "star_06", 300.0)
	fx.burst(ENEMY_POS, Color.from_hsv(S["enemy"]["hue"], 0.6, 1.0), 30, 500.0, 70.0, 0.8, "circle_05", 200.0)
	fx.sound("win", -2.0)
	create_tween().tween_property(self, "enemy_scale", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_say("勝利！")
	get_tree().create_timer(1.0).timeout.connect(_after_victory)


## 敵の番: ブロックが消えてから、予告していた行動をする
func _enemy_turn() -> void:
	S["phase"] = "enemy"
	phase_timer = 1.2
	var e: Dictionary = S["enemy"]
	e["block"] = 0.0
	var move := _current_move()
	e["move_i"] += 1
	match move["t"]:
		"atk", "multi":
			var per: int = move["n"] + e["atk_bonus"]
			var hits: int = move.get("k", 1)
			var total := per * hits
			var dmg := maxi(0, total - S["block"])
			var blocked: int = total - dmg
			S["block"] = maxi(0, S["block"] - total)
			var tw := create_tween()
			tw.tween_property(self, "enemy_offset", Vector2(-120, 30), 0.12).set_ease(Tween.EASE_IN)
			tw.tween_callback(_on_enemy_hit.bind(dmg, blocked))
			tw.tween_property(self, "enemy_offset", Vector2.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			var what := "%d" % per if hits == 1 else "%d×%d" % [per, hits]
			_say("敵の攻撃 %s！" % what + ("（ブロックで %d 防いだ）" % blocked if blocked > 0 else ""))
		"def":
			e["block"] = float(move["n"])
			fx.float_text(ENEMY_POS + Vector2(0, -40), "ブロック %d" % move["n"], Color(0.6, 0.8, 1.0), 36)
			fx.sound("block", -4.0)
			_say("敵は身を守った（次の発射はまずブロックを削る）")
		"buff":
			e["atk_bonus"] += move["n"]
			fx.float_text(ENEMY_POS + Vector2(0, -40), "攻撃力 +%d" % move["n"], Color(1.0, 0.5, 0.4), 36)
			_say("敵の攻撃力が上がった")
		"fast", "seal", "drain":
			S["debuff"][move["t"]] = move.get("n", true)
			var desc := {"fast": "次のターン、カップが速くなる", "seal": "次のターン、ゲートが1つ封じられる",
				"drain": "次のターン、ゲートの回数 -%d" % move.get("n", 0)}
			fx.float_text(ENEMY_POS + Vector2(0, -40), "妨害", Color(0.9, 0.5, 1.0), 40)
			_say("【妨害】" + desc[move["t"]])
	var hop := create_tween()
	hop.tween_property(self, "enemy_scale", 1.12, 0.1)
	hop.tween_property(self, "enemy_scale", 1.0, 0.15)


func _current_move() -> Dictionary:
	var moves: Array = S["enemy"]["moves"]
	return moves[S["enemy"]["move_i"] % moves.size()]


func _intent_text() -> Array:
	var m := _current_move()
	var bonus: int = S["enemy"]["atk_bonus"]
	match m["t"]:
		"atk":
			return ["攻撃  %d" % (m["n"] + bonus), Color(1.0, 0.5, 0.45)]
		"multi":
			return ["攻撃  %d×%d" % [m["n"] + bonus, m["k"]], Color(1.0, 0.5, 0.45)]
		"def":
			return ["守り  %d" % m["n"], Color(0.6, 0.8, 1.0)]
		"buff":
			return ["強化  攻撃+%d" % m["n"], Color(1.0, 0.7, 0.4)]
		"fast":
			return ["妨害  カップ加速", Color(0.9, 0.55, 1.0)]
		"seal":
			return ["妨害  ゲート封印", Color(0.9, 0.55, 1.0)]
		"drain":
			return ["妨害  回数 -%d" % m["n"], Color(0.9, 0.55, 1.0)]
	return ["?", Color.WHITE]


func _on_enemy_hit(dmg: int, blocked: int) -> void:
	R["hp"] -= dmg
	shake = 8.0 + dmg * 1.5
	if dmg > 0:
		fx.sound("hurt", -2.0)
		ui["flash"].color = Color(0.9, 0.1, 0.1, 0.35)
		create_tween().tween_property(ui["flash"], "color:a", 0.0, 0.35)
		fx.float_text(Vector2(280, 150), "-%d" % dmg, Color(1.0, 0.4, 0.35), 48, 60.0, 0.9)
	if blocked > 0:
		fx.sound("block", -4.0)
		fx.float_text(Vector2(280, 230), "ブロック %d" % blocked, Color(0.6, 0.8, 1.0), 30, 40.0, 0.8)
	_punch(ui["hp_label"])


# --- 盤面からの合図 ---

func _on_gate_passed(idx: int, type: String, pos: Vector2) -> void:
	var c: Color = Board.GATE_DEFS[type]["color"]
	fx.burst(pos, c.lightened(0.3), 10, 320.0, 24.0, 0.35)
	fx.sound("tink", -10.0, 0.9 + 0.15 * (idx / Board.COLS))
	# 発電・索敵は、このターンに決まった回数通ると次のターンの準備になる（1ターンに1回まで）
	pass_counts[idx] = pass_counts.get(idx, 0) + 1
	var g = board.slots[idx]
	if g == null:
		return
	if type == "power" and pass_counts[idx] == int(g["val"]):
		S["next_energy"] += 1
		fx.float_text(pos + Vector2(0, -30), "次ターン エネ+1", Color(1.0, 0.75, 0.35), 26, 50.0, 0.9)
		fx.burst(pos, Color(1.0, 0.75, 0.35), 20, 420.0, 30.0, 0.5, "star_06")
	elif type == "scout" and pass_counts[idx] == int(g["val"]):
		S["next_draw"] += 1
		fx.float_text(pos + Vector2(0, -30), "次ターン +1枚", Color(0.6, 0.9, 1.0), 26, 50.0, 0.9)
		fx.burst(pos, Color(0.6, 0.9, 1.0), 20, 420.0, 30.0, 0.5, "star_06")


func _on_peg_hit(pos: Vector2, speed: float) -> void:
	if speed > 200.0:
		fx.burst(pos, Color(0.85, 0.9, 1.0), 3, 160.0, 14.0, 0.2, "spark_05", 0.0)
		fx.sound("peg", -22.0, 1.3)


func _on_ball_collected(val: float, pos: Vector2) -> void:
	S["ammo"] += val + S["per_ball"]
	fx.burst(Vector2(pos.x, Board.COLLECT_Y + 10), Color(1.0, 0.7, 0.4), 8, 260.0, 26.0, 0.35, "spark_01", 600.0)
	fx.sound("collect", -10.0)
	_punch(ui["ammo"])


func _on_block_gained(amount: int, pos: Vector2) -> void:
	S["block"] += amount
	fx.float_text(pos + Vector2(0, -20), "+%d" % amount, Color(0.6, 0.8, 1.0), 26, 40.0, 0.5)
	_punch(ui["block"])


# ============================================================
# 戦闘のあと・ショップ・休憩・宝箱
# ============================================================

func _after_victory() -> void:
	var e: Dictionary = S["enemy"]
	S["phase"] = "none"
	if e.get("boss", false):
		_show_victory()
		return
	var gold := randi_range(35, 45) if e.get("elite", false) else randi_range(15, 24)
	if has_relic("golden"):
		gold = int(gold * 1.5)
	R["gold"] += gold
	var lines := ["+%d ゴールド" % gold]
	if has_relic("herb"):
		R["hp"] = mini(R["max_hp"], R["hp"] + 5)
		lines.append("薬草袋で HP +5")
	if e.get("elite", false):
		var relic := _random_relic()
		if relic != "":
			R["relics"].append(relic)
			lines.append("レリック「%s」を手に入れた" % Data.RELICS[relic]["name"])
	_show_card_reward("勝利！　" + "　".join(lines))


func _show_card_reward(title: String) -> void:
	_set_battle_visible(false)
	var p := _open_panel(title)
	var pool := Data.CARDS.keys()
	pool.shuffle()
	var picks: Array = pool.slice(0, 3)
	var sub := _label(p, Vector2(0, 220), 30, Color(1, 1, 1, 0.8))
	sub.text = "デッキに加えるカードを1枚選ぶ"
	sub.size = Vector2(1920, 40)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in picks.size():
		var id: String = picks[i]
		var card := _make_card(p, id, Vector2(960 - 330 + i * 240 - Card.SIZE.x / 2.0 + 90, 320))
		card.pressed.connect(_take_card.bind(id))
	_button(p, Vector2(760, 680), Vector2(400, 90), "取らない", _show_map, "grey")


func _take_card(id: String) -> void:
	R["deck"].append(id)
	fx.sound("click")
	_show_map()


func _show_shop() -> void:
	screen = "shop"
	var p := _open_panel("ショップ")
	var pool := Data.CARDS.keys()
	pool.shuffle()
	var cards: Array = pool.slice(0, 5)
	for i in cards.size():
		var id: String = cards[i]
		var price: int = Data.CARDS[id]["price"] + randi_range(-5, 10)
		var pos := Vector2(960 - 2.5 * 220 + i * 220 + 20, 200)
		var card := _make_card(p, id, pos)
		var tag := _button(p, pos + Vector2(10, 245), Vector2(160, 56), "%d G" % price, Callable(), "yellow")
		card.pressed.connect(_buy_card.bind(id, price, card, tag))
		tag.pressed.connect(_buy_card.bind(id, price, card, tag))
	# レリック 2 つ
	var relics := []
	for k in 2:
		var r := _random_relic(relics)
		if r != "":
			relics.append(r)
	for k in relics.size():
		var rid: String = relics[k]
		var info: Dictionary = Data.RELICS[rid]
		var btn := _button(p, Vector2(330 + k * 470, 600), Vector2(440, 130),
			"%s　%d G\n%s" % [info["name"], info["price"], info["desc"]], Callable(), "grey", 24)
		btn.pressed.connect(_buy_relic.bind(rid, btn))
	# カードの削除（1回まで）
	var rm := _button(p, Vector2(1270, 600), Vector2(320, 130), "カードを1枚削除\n%d G" % REMOVE_PRICE, _shop_remove, "red", 26)
	rm.disabled = R["removed"]
	_button(p, Vector2(760, 860), Vector2(400, 100), "店を出る", _show_map, "blue")


func _buy_card(id: String, price: int, card: Card, tag: Button) -> void:
	if not is_instance_valid(card) or R["gold"] < price:
		fx.sound("tap", -6.0, 0.6)
		return
	R["gold"] -= price
	R["deck"].append(id)
	fx.sound("win", -10.0, 1.6)
	card.queue_free()
	tag.queue_free()


func _buy_relic(rid: String, btn: Button) -> void:
	var price: int = Data.RELICS[rid]["price"]
	if R["gold"] < price:
		fx.sound("tap", -6.0, 0.6)
		return
	R["gold"] -= price
	R["relics"].append(rid)
	fx.sound("win", -10.0, 1.4)
	btn.queue_free()


func _shop_remove() -> void:
	if R["gold"] < REMOVE_PRICE or R["removed"]:
		fx.sound("tap", -6.0, 0.6)
		return
	# 削除の画面から戻ると、店の品ぞろえは作り直しになる（試作なので簡単にしている）
	_pick_from_deck("削除するカードを選ぶ", _any_card, _remove_card, _show_shop)


func _remove_card(idx: int) -> void:
	R["gold"] -= REMOVE_PRICE
	R["removed"] = true
	R["deck"].remove_at(idx)
	fx.sound("hurt", -8.0, 1.4)
	_show_shop()


func _any_card(_c: String) -> bool:
	return true


func _not_upgraded(c: String) -> bool:
	return not Data.is_up(c)


func _show_rest() -> void:
	screen = "rest"
	var p := _open_panel("休憩所")
	var heal := int(R["max_hp"] * 0.3)
	_button(p, Vector2(460, 380), Vector2(460, 200), "休む\nHP を %d 回復" % heal, _rest_heal.bind(heal), "green", 34)
	_button(p, Vector2(1000, 380), Vector2(460, 200), "鍛える\nカードを1枚強化", _rest_upgrade, "yellow", 34)


func _rest_heal(heal: int) -> void:
	R["hp"] = mini(R["max_hp"], R["hp"] + heal)
	fx.sound("win", -8.0, 1.2)
	_show_map()


func _rest_upgrade() -> void:
	_pick_from_deck("強化するカードを選ぶ", _not_upgraded, _upgrade_card, _show_rest, true)


func _upgrade_card(idx: int) -> void:
	R["deck"][idx] = R["deck"][idx] + "+"
	fx.sound("win", -8.0, 1.6)
	_show_map()


func _show_treasure() -> void:
	screen = "treasure"
	var relic := _random_relic()
	var p := _open_panel("宝箱")
	var l := _label(p, Vector2(0, 380), 40, Color(1.0, 0.9, 0.5))
	l.size = Vector2(1920, 140)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if relic == "":
		R["gold"] += 50
		l.text = "空っぽ…… 代わりに 50 ゴールド"
	else:
		R["relics"].append(relic)
		l.text = "レリック「%s」を手に入れた\n%s" % [Data.RELICS[relic]["name"], Data.RELICS[relic]["desc"]]
	fx.sound("win", -6.0)
	_button(p, Vector2(760, 620), Vector2(400, 100), "進む", _show_map, "blue")


func _random_relic(exclude := []) -> String:
	var cands := []
	for k in Data.RELICS:
		if not R["relics"].has(k) and not exclude.has(k):
			cands.append(k)
	return "" if cands.is_empty() else cands.pick_random()


## デッキからカードを1枚選ぶ画面。filter で選べるカードを絞り、選ぶと on_pick(デッキ内の番号) を呼ぶ
## show_upgrade が true なら、マウスを乗せたカードの「強化前 → 強化後」を左下に並べて見せる
func _pick_from_deck(title: String, filter: Callable, on_pick: Callable, on_cancel: Callable, show_upgrade := false) -> void:
	var p := _open_panel(title)
	var n: int = R["deck"].size()
	var per_row := 8
	var s := 0.78
	for i in n:
		var id: String = R["deck"][i]
		var col := i % per_row
		var row := i / per_row
		var pos := Vector2(960 - per_row * 100 + col * 200 + 10, 180 + row * 195)
		var card := _make_card(p, id, pos)
		card.base_scale = s
		card.scale = Vector2.ONE * s
		card.pivot_offset = Vector2.ZERO
		if filter.call(id):
			card.pressed.connect(on_pick.bind(i))
			if show_upgrade:
				card.mouse_entered.connect(_show_upgrade_preview.bind(p, id))
		else:
			card.modulate = Color(0.4, 0.4, 0.45)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if show_upgrade:
		var hint := _label(p, Vector2(150, 860), 26, Color(1, 1, 1, 0.6))
		hint.text = "カードにマウスを乗せると、強化後が見られる"
		p.set_meta("preview_hint", hint)
	_button(p, Vector2(760, 960), Vector2(400, 90), "やめる", on_cancel, "grey")


func _show_upgrade_preview(p: Control, id: String) -> void:
	for key in ["preview_hint", "preview_before", "preview_after", "preview_arrow"]:
		if p.has_meta(key) and is_instance_valid(p.get_meta(key)):
			p.get_meta(key).queue_free()
	var before := _make_card(p, id, Vector2(110, 800))
	before.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var after := _make_card(p, id + "+", Vector2(430, 800))
	after.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var arrow := _label(p, Vector2(310, 870), 64, Color(1.0, 0.9, 0.5))
	arrow.text = "→"
	p.set_meta("preview_before", before)
	p.set_meta("preview_after", after)
	p.set_meta("preview_arrow", arrow)


func _show_deck() -> void:
	if screen == "title" or panel != null and panel.has_meta("deck_view"):
		return
	var back := screen
	var p := _open_panel("デッキ（%d 枚）" % R["deck"].size(), true)
	p.set_meta("deck_view", true)
	var per_row := 8
	for i in R["deck"].size():
		var card := _make_card(p, R["deck"][i], Vector2(960 - per_row * 100 + (i % per_row) * 200 + 10, 180 + (i / per_row) * 195))
		card.scale = Vector2.ONE * 0.78
		card.pivot_offset = Vector2.ZERO
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_button(p, Vector2(760, 960), Vector2(400, 90), "閉じる", func(): p.queue_free(), "grey")
	screen = back


func _show_victory() -> void:
	screen = "victory"
	_set_battle_visible(false)
	var p := _open_panel("クリア！")
	var l := _label(p, Vector2(0, 320), 36, Color(1, 1, 1, 0.9))
	l.size = Vector2(1920, 200)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = "ペグの王を倒した！\n残り HP %d ／ デッキ %d 枚 ／ レリック %d 個" % [R["hp"], R["deck"].size(), R["relics"].size()]
	fx.burst(Vector2(960, 300), Color(1.0, 0.85, 0.4), 60, 900.0, 70.0, 1.2, "star_06", 300.0)
	_button(p, Vector2(760, 640), Vector2(400, 100), "タイトルへ", _show_title, "blue")


func _show_game_over() -> void:
	screen = "over"
	var p := _open_panel("敗北……")
	var l := _label(p, Vector2(0, 340), 36, Color(1, 1, 1, 0.9))
	l.size = Vector2(1920, 140)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = "第 %d 層で「%s」に倒された" % [R["floor"], S["enemy"]["name"]]
	_button(p, Vector2(760, 600), Vector2(400, 100), "タイトルへ", _show_title, "blue")


# ============================================================
# 入力
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if screen != "battle" or panel != null:
		return
	# スペース: ターン中なら注ぐ（狙い開始）、狙い中ならカップを止める
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_on_pour_button()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and S["phase"] == "aim":
		_lock_cup()
	elif event.button_index == MOUSE_BUTTON_RIGHT and S["selected"] >= 0:
		_cancel_select()
	elif event.button_index == MOUSE_BUTTON_LEFT and S["phase"] == "turn" and S["selected"] >= 0:
		var idx := board.slot_at(get_global_mouse_position())
		if idx >= 0 and board.highlight.has(idx):
			_place_selected(idx)


# ============================================================
# 画面の部品
# ============================================================

func _label(parent: Node, pos: Vector2, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _tex_box(path: String, margin := 16) -> StyleBoxTexture:
	var b := StyleBoxTexture.new()
	b.texture = load(path)
	b.set_texture_margin_all(margin)
	return b


func _button(parent: Node, pos: Vector2, sz: Vector2, text: String, cb: Callable, color := "blue", font_size := 30) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = sz
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", font_size)
	var dark := color in ["grey", "yellow"]
	var fc := Color(0.15, 0.15, 0.2) if dark else Color.WHITE
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, fc)
	b.add_theme_color_override("font_disabled_color", Color(0.3, 0.32, 0.38))
	b.add_theme_stylebox_override("normal", _tex_box("res://assets/ui/%s_rect.png" % color))
	b.add_theme_stylebox_override("hover", _tex_box("res://assets/ui/%s_rect.png" % ("yellow" if color != "yellow" else "green")))
	b.add_theme_stylebox_override("pressed", _tex_box("res://assets/ui/green_rect.png"))
	b.add_theme_stylebox_override("disabled", _tex_box("res://assets/ui/grey_rect.png"))
	if cb.is_valid():
		b.pressed.connect(cb)
	b.pressed.connect(fx.sound.bind("click", -6.0))
	parent.add_child(b)
	return b


func _make_card(parent: Node, id: String, pos: Vector2) -> Card:
	var card := Card.new()
	card.setup(id, font)
	card.base_pos = pos
	card.position = pos
	parent.add_child(card)
	return card


## 全画面の重ね画面を開く（前のものは閉じる）。keep_old が true なら前のものを残して上に重ねる
func _open_panel(title: String, keep_old := false) -> Control:
	if not keep_old:
		_close_panel()
	var dim := ColorRect.new()
	dim.size = Vector2(1920, 1080)
	dim.color = Color(0.05, 0.06, 0.09, 0.93)
	ui["screens"].add_child(dim)
	if title != "":
		var t := _label(dim, Vector2(0, 90), 54, Color(1.0, 0.9, 0.5))
		t.text = title
		t.size = Vector2(1920, 80)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.15)
	if not keep_old:
		panel = dim
	return dim


func _close_panel() -> void:
	for c in ui["screens"].get_children():
		if c != run_map:
			c.queue_free()
	panel = null


func _set_battle_visible(on: bool) -> void:
	board.visible = on
	ui["hud"].visible = on
	visible_world = on


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	ui["hud"] = hud

	ui["title"] = _label(hud, Vector2(60, 76), 36)
	ui["hp_label"] = _label(hud, Vector2(60, 130), 30, Color(0.6, 1.0, 0.7))
	var hp_bar := ProgressBar.new()
	hp_bar.position = Vector2(60, 176)
	hp_bar.size = Vector2(420, 24)
	hp_bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.8, 0.45)
	fill.set_corner_radius_all(8)
	hp_bar.add_theme_stylebox_override("background", bg)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hud.add_child(hp_bar)
	ui["hp_bar"] = hp_bar
	ui["block"] = _label(hud, Vector2(60, 214), 32, Color(0.6, 0.8, 1.0))

	var orb := Panel.new()
	orb.position = Vector2(60, 280)
	orb.size = Vector2(130, 130)
	var orb_box := StyleBoxFlat.new()
	orb_box.bg_color = Color(0.95, 0.55, 0.2)
	orb_box.set_corner_radius_all(65)
	orb_box.set_border_width_all(6)
	orb_box.border_color = Color(1.0, 0.85, 0.55)
	orb.add_theme_stylebox_override("panel", orb_box)
	hud.add_child(orb)
	var energy := _label(orb, Vector2.ZERO, 48)
	energy.size = orb.size
	energy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui["energy"] = energy
	_label(hud, Vector2(210, 330), 26, Color(1, 1, 1, 0.7)).text = "エネルギー"

	ui["piles"] = _label(hud, Vector2(60, 440), 22, Color(1, 1, 1, 0.75))
	ui["mods"] = _label(hud, Vector2(60, 476), 22, Color(1.0, 0.75, 0.45))
	var msg := _label(hud, Vector2(60, 540), 26)
	msg.size = Vector2(440, 240)
	msg.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	ui["msg"] = msg

	var ammo := _label(hud, Vector2(1520, 690), 30, Color(1.0, 0.8, 0.5))
	ui["ammo"] = ammo

	var pour := _button(hud, Vector2(1480, 880), Vector2(400, 140), "", _on_pour_button, "blue", 32)
	ui["pour"] = pour

	var hand_root := Control.new()
	hand_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hand_root)
	ui["hand"] = hand_root

	var flash := ColorRect.new()
	flash.size = Vector2(1920, 1080)
	flash.color = Color(1, 0, 0, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(flash)
	ui["flash"] = flash

	# 地図・報酬・ショップなどを載せる層（戦闘の上）
	var screens := CanvasLayer.new()
	screens.layer = 2
	add_child(screens)
	var root := Control.new()
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screens.add_child(root)
	ui["screens"] = root


## 画面上端の帯: HP・ゴールド・層・レリック・デッキ・音量（タイトル以外でいつも出す）
func _build_top_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	var bar := Panel.new()
	bar.size = Vector2(1920, 56)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.05, 0.07, 0.95)
	bar.add_theme_stylebox_override("panel", box)
	layer.add_child(bar)
	ui["top"] = bar
	ui["top_hp"] = _label(bar, Vector2(24, 8), 28, Color(0.6, 1.0, 0.7))
	ui["top_gold"] = _label(bar, Vector2(250, 8), 28, Color(1.0, 0.85, 0.4))
	ui["top_floor"] = _label(bar, Vector2(470, 8), 28, Color(1, 1, 1, 0.8))
	var relics := HBoxContainer.new()
	relics.position = Vector2(640, 8)
	relics.add_theme_constant_override("separation", 10)
	bar.add_child(relics)
	ui["top_relics"] = relics
	ui["top_relic_count"] = -1
	_button(bar, Vector2(1560, 6), Vector2(180, 44), "デッキ", _show_deck, "grey", 22)
	_button(bar, Vector2(1750, 6), Vector2(150, 44), "音量", _toggle_volume, "grey", 22)

	var vol := Panel.new()
	vol.position = Vector2(1560, 60)
	vol.size = Vector2(340, 90)
	var vbox := StyleBoxFlat.new()
	vbox.bg_color = Color(0.1, 0.11, 0.15, 0.97)
	vbox.set_corner_radius_all(10)
	vol.add_theme_stylebox_override("panel", vbox)
	vol.visible = false
	layer.add_child(vol)
	_label(vol, Vector2(16, 10), 22).text = "音量"
	var slider := HSlider.new()
	slider.position = Vector2(16, 48)
	slider.size = Vector2(308, 24)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = 0.8
	slider.value_changed.connect(func(v): AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001))))
	AudioServer.set_bus_volume_db(0, linear_to_db(0.8))
	vol.add_child(slider)
	ui["volume"] = vol


func _toggle_volume() -> void:
	ui["volume"].visible = not ui["volume"].visible


func _rebuild_hand() -> void:
	for c in hand_cards:
		c.queue_free()
	hand_cards.clear()
	for id in S["hand"]:
		_make_hand_card(id)
	_layout_hand()


func _make_hand_card(id: String) -> Card:
	var card := Card.new()
	card.setup(id, font)
	card.auto_hover = false
	card.pressed.connect(_on_card_pressed.bind(card))
	ui["hand"].add_child(card)
	hand_cards.append(card)
	return card


func _layout_hand() -> void:
	# 枚数が多いときは重ねて、手札の幅を 1000px 以内に収める
	var n := hand_cards.size()
	var step := minf(Card.SIZE.x + 16.0, (1000.0 - Card.SIZE.x) / maxf(n - 1, 1))
	var total := (n - 1) * step + Card.SIZE.x
	var x0 := 960.0 - total / 2.0
	for i in n:
		var card: Card = hand_cards[i]
		card.base_pos = Vector2(x0 + i * step, 835.0)
		card.create_tween().tween_property(card, "position", card.base_pos, 0.2).set_trans(Tween.TRANS_QUAD)


func _on_card_pressed(card: Card) -> void:
	var i := hand_cards.find(card)
	if i >= 0:
		_play_card(i)


func _say(text: String) -> void:
	ui["msg"].text = text


func _punch(node: Control) -> void:
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2.ONE * 1.25
	node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_ui() -> void:
	ui["top_hp"].text = "HP %d / %d" % [R["hp"], R["max_hp"]]
	ui["top_gold"].text = "%d G" % R["gold"]
	ui["top_floor"].text = "第 %d 層" % R["floor"]
	if ui["top_relic_count"] != R["relics"].size():
		ui["top_relic_count"] = R["relics"].size()
		for c in ui["top_relics"].get_children():
			c.queue_free()
		for rid in R["relics"]:
			var l := Label.new()
			l.text = Data.RELICS[rid]["name"]
			l.tooltip_text = Data.RELICS[rid]["desc"]
			l.mouse_filter = Control.MOUSE_FILTER_STOP
			l.add_theme_font_override("font", font)
			l.add_theme_font_size_override("font_size", 22)
			l.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
			ui["top_relics"].add_child(l)
	if screen != "battle":
		return
	ui["hp_label"].text = "HP  %d / %d" % [R["hp"], R["max_hp"]]
	ui["hp_bar"].max_value = R["max_hp"]
	ui["hp_bar"].value = R["hp"]
	ui["block"].text = "ブロック  %d" % S["block"]
	ui["block"].modulate.a = 1.0 if S["block"] > 0 else 0.45
	ui["energy"].text = "%d/%d" % [S["energy"], ENERGY]
	ui["piles"].text = "山札 %d   捨て札 %d   除外 %d" % [S["draw"].size(), S["discard"].size(), S["exhaust"].size()]
	var mods := ""
	if S["next_energy"] > 0:
		mods += "次ターン エネ+%d   " % S["next_energy"]
	if S["next_draw"] > 0:
		mods += "次ターン +%d枚   " % S["next_draw"]
	if S["ammo_mul"] != 1.0:
		mods += "弾倉 ×%.1f   " % S["ammo_mul"]
	if S["per_ball"] > 0:
		mods += "玉ごと +%d" % S["per_ball"]
	ui["mods"].text = mods
	ui["ammo"].text = "弾倉 %s" % Board.fmt(_ammo_left())
	var turn: bool = S["phase"] == "turn"
	var aim: bool = S["phase"] == "aim"
	ui["pour"].disabled = not (turn or aim)
	var waiting := {"aim": "ここで止める\n（クリック／スペース）", "pour": "注いでいる…", "fire": "撃っている…",
		"enemy": "敵の番…"}
	ui["pour"].text = "玉を %d 個注ぐ\nターン終了" % S["balls"] if turn else waiting.get(S["phase"], "…")
	# 手札の浮き上がり: マウスの下にある一番上（右側）のカード1枚だけ。定位置の範囲で判定するので、浮いても外れない
	var mouse: Vector2 = ui["hand"].get_global_mouse_position()
	var hover_i := -1
	if panel == null:
		for i in range(hand_cards.size() - 1, -1, -1):
			if Rect2(hand_cards[i].base_pos + Vector2(0, -40), Card.SIZE + Vector2(0, 40)).has_point(mouse):
				hover_i = i
				break
	for i in hand_cards.size():
		var card: Card = hand_cards[i]
		card.set_state(turn and S["energy"] >= Data.info(card.id)["cost"], S["selected"] == i)
		card.set_hover(i == hover_i)


# ============================================================
# 描画（敵・銃・弾）
# ============================================================

func _draw() -> void:
	if not visible_world:
		return
	var e: Dictionary = S["enemy"]
	var c := ENEMY_POS + enemy_offset + Vector2(0, sin(time * 2.2) * 6.0)
	# 次の行動の予告（敵の頭上）
	if S["phase"] in ["turn", "aim", "pour", "fire"]:
		var it := _intent_text()
		var intent := ENEMY_POS + Vector2(-170, -ENEMY_R - 60)
		draw_string_outline(font, intent, "次: " + it[0], HORIZONTAL_ALIGNMENT_CENTER, 340, 32, 6, Color(0, 0, 0, 0.6))
		draw_string(font, intent, "次: " + it[0], HORIZONTAL_ALIGNMENT_CENTER, 340, 32, it[1])
	# 敵の体
	var r := ENEMY_R * enemy_scale * (1.25 if e.get("boss", false) else 1.0)
	if r > 1.0:
		var body := Color.from_hsv(e["hue"], 0.55, 0.85)
		draw_circle(c + Vector2(0, r * 0.9), r * 0.8, Color(0, 0, 0, 0.25))
		draw_circle(c, r + 6.0, body.darkened(0.5))
		draw_circle(c, r, body)
		draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.25, Color(1, 1, 1, 0.18))
		var look := (GUN_POS - c).normalized() * r * 0.06
		for sx in [-1.0, 1.0]:
			var eye := c + Vector2(sx * r * 0.32, -r * 0.1)
			draw_circle(eye, r * 0.17, Color.WHITE)
			draw_circle(eye + look, r * 0.08, Color(0.1, 0.1, 0.15))
		draw_arc(c + Vector2(0, r * 0.25), r * 0.3, 0.3, PI - 0.3, 16, body.darkened(0.6), 6.0)
		if e.get("boss", false):
			# 王冠
			var top := c + Vector2(0, -r - 4)
			draw_colored_polygon(PackedVector2Array([top + Vector2(-50, 10), top + Vector2(-50, -30), top + Vector2(-25, -10),
				top + Vector2(0, -40), top + Vector2(25, -10), top + Vector2(50, -30), top + Vector2(50, 10)]), Color(1.0, 0.82, 0.3))
		if enemy_flash > 0.0:
			draw_circle(c, r, Color(1, 1, 1, 0.6 * enemy_flash))
		if e["block"] > 0.0:
			draw_arc(c, r + 16.0, 0, TAU, 48, Color(0.6, 0.8, 1.0, 0.8), 8.0)
	# 名前と HP
	var bar := Rect2(ENEMY_POS.x - 190, ENEMY_POS.y + ENEMY_R + 50, 380, 30)
	draw_string(font, Vector2(bar.position.x, bar.position.y - 12), e["name"], HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 30,
		Color(1, 1, 1, 0.9))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hp_trail / e["max"], 0.0, 1.0), bar.size.y)), Color(1, 1, 1, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(e["hp"] / e["max"], 0.0, 1.0), bar.size.y)), Color(0.9, 0.28, 0.28))
	draw_string(font, Vector2(bar.position.x, bar.position.y + 24), "%s / %s" % [Board.fmt(maxf(e["hp"], 0.0)), Board.fmt(e["max"])],
		HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 22, Color.WHITE)
	if e["block"] > 0.0:
		draw_string_outline(font, Vector2(bar.position.x - 120, bar.position.y + 26), "盾 %s" % Board.fmt(e["block"]),
			HORIZONTAL_ALIGNMENT_RIGHT, 110, 28, 6, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(bar.position.x - 120, bar.position.y + 26), "盾 %s" % Board.fmt(e["block"]),
			HORIZONTAL_ALIGNMENT_RIGHT, 110, 28, Color(0.6, 0.8, 1.0))

	# ミニガン（敵の方を向き、撃つと銃身が回って反動で下がる）
	var dir := (ENEMY_POS - GUN_POS).normalized()
	var base := GUN_POS - dir * recoil
	draw_circle(GUN_POS + Vector2(0, 50), 64.0, Color(0.22, 0.24, 0.3))
	draw_set_transform(base, dir.angle(), Vector2.ONE * 1.5)
	draw_rect(Rect2(-30, -30, 70, 60), Color(0.4, 0.43, 0.5))
	for k in 3:
		var off := sin(gun_spin + k * TAU / 3.0) * 14.0
		var shade := 0.55 + 0.25 * cos(gun_spin + k * TAU / 3.0)
		draw_line(Vector2(30, off), Vector2(95, off), Color(shade, shade + 0.02, shade + 0.08), 9.0)
	draw_rect(Rect2(60, -22, 10, 44), Color(0.3, 0.32, 0.38))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for bl in bullets:
		var p: Vector2 = bl["p"]
		var tail: Vector2 = p - bl["v"].normalized() * 40.0
		draw_line(tail, p, Color(1.0, 0.85, 0.45, 0.9), 4.0)
		draw_circle(p, 3.5, Color(1.0, 0.95, 0.8))


func _save_shot() -> void:
	var n := shot_index
	shot_index += 1
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/frame_%03d.png" % [shots_dir, n])


# ============================================================
# デモ（撮影用の自動操作）
# ============================================================

func _run_demo() -> void:
	R = _new_run()
	run_map.generate()
	if demo_kind == "tour":
		await _run_tour()
		return
	if demo_kind == "auto":
		await _run_auto()
		return
	R["floor"] = 1
	_start_battle("slime")
	S["hand"] = ["focus", "prep", "add", "sq", "mul"]
	S["draw"].append("cheer")  # 下準備で引く1枚
	S["enemy"]["hp"] = 200.0
	S["enemy"]["max"] = 200.0
	hp_trail = 200.0
	_rebuild_hand()
	var plan := [["focus", -1], ["prep", -1], ["add", 1], ["sq", 5], ["mul", 9], ["cheer", 10]]  # [カード, 置くマス]
	if demo_kind == "bounce":
		# 2列目の一番下の跳ね返しで上へ飛ばし、上の +3 を通らせる
		S["hand"] = ["mul", "bounce", "add", "add", "guard"]
		_rebuild_hand()
		plan = [["mul", 1], ["bounce", 9], ["add", 6], ["add", 10]]
	await get_tree().create_timer(0.8).timeout
	for step in plan:
		_play_card(S["hand"].find(step[0]))
		if step[1] >= 0:
			board.highlight[step[1]] = true
			await get_tree().create_timer(0.35).timeout
			_place_selected(step[1])
		await get_tree().create_timer(0.35).timeout
	await get_tree().create_timer(0.3).timeout
	_pour()


## 画面めぐり: タイトル・地図・ショップ・休憩・宝箱・報酬・ボス戦・クリア・敗北を順に見せる
func _run_tour() -> void:
	R["relics"] = ["hourglass", "belt", "scope"]
	R["deck"].append_array(["bounce+", "power", "refill"])
	_show_title()
	await _wait(0.8)
	_show_map()
	await _wait(0.8)
	_show_shop()
	await _wait(0.8)
	_show_rest()
	await _wait(0.6)
	_pick_from_deck("強化するカードを選ぶ", _not_upgraded, _any_card, _show_rest, true)
	_show_upgrade_preview(panel, "mul")
	await _wait(0.8)
	_show_treasure()
	await _wait(0.6)
	R["floor"] = 3
	_start_battle("mage")
	S["debuff"] = {"seal": true, "drain": 2}
	board.place(5, "add", 6, 3.0)
	board.place(6, "mul", 6, 2.0)
	await _wait(0.2)
	_rebuild_hand()
	S["hand"].clear()
	_rebuild_hand()
	_start_turn()
	# 手札の浮き上がりの確認: 2枚目 → 4枚目 → 手札の外へマウスを動かす
	await _wait(0.6)
	get_viewport().warp_mouse(hand_cards[1].base_pos + Card.SIZE / 2.0)
	await _wait(0.4)
	get_viewport().warp_mouse(hand_cards[3].base_pos + Card.SIZE / 2.0)
	await _wait(0.4)
	get_viewport().warp_mouse(Vector2(960, 500))
	await _wait(0.4)
	R["floor"] = 11
	_start_battle("pegking")
	await _wait(1.0)
	_show_card_reward("勝利！　+20 ゴールド")
	await _wait(0.8)
	_show_victory()
	await _wait(0.8)
	_show_game_over()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


## 自動プレイ（確認用）: 地図は最初の候補へ進み、戦闘は出せるカードを全部出して真ん中で止めて注ぐ
func _run_auto() -> void:
	_start_run()
	var last := ""
	var steps := 0
	while screen not in ["victory", "over"] and steps < 4000:
		steps += 1
		Engine.time_scale = 4.0
		await _wait(0.1)
		match screen:
			"map":
				var k: String = run_map.choices()[0]
				for c in run_map.choices():
					if run_map.nodes[c]["type"] == "elite":
						k = c
				run_map.current = k
				run_map.visited[k] = true
				var n: Dictionary = run_map.nodes[k]
				print("層 %d  %s  HP %d  %d G  デッキ %d  レリック %s" % [n["row"] + 1, RunMap.TYPE_NAME[n["type"]], R["hp"],
					R["gold"], R["deck"].size(), ",".join(R["relics"])])
				_on_map_node(n)
			"battle":
				if S["phase"] == "turn":
					for _k in 8:
						var i := -1
						for j in S["hand"].size():
							if Data.info(S["hand"][j])["cost"] <= S["energy"]:
								i = j
								break
						if i < 0:
							break
						_play_card(i)
						if S["selected"] >= 0:
							if board.highlight.is_empty():
								_cancel_select()
								break
							_place_selected(board.highlight.keys()[0])
					_pour()
				elif S["phase"] == "aim":
					if absf(board.cup_x - 960.0) < 40.0:
						_lock_cup()
				elif S["phase"] == "none" and panel != null:
					var tag := "%s %d" % [S["enemy"]["name"], R["floor"]]
					if tag != last:
						last = tag
						print("   → %s を倒した（ターン %d）" % [S["enemy"]["name"], S["turn"]])
					_take_card(Data.CARDS.keys().pick_random())
			"shop":
				_show_map()
			"rest":
				_rest_heal(int(R["max_hp"] * 0.3))
			"treasure":
				_show_map()
	print("結果: %s  層 %d  HP %d" % [screen, R["floor"], R["hp"]])
	get_tree().quit()
