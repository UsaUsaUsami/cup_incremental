extends Node2D
## カップ×ゲート×ミニガンのデッキ構築ローグライト（PC 向け 1920×1080）。
## ランの流れ: タイトル → 地図 → 戦闘・強敵・ショップ・休憩・宝箱 → … → ボス → クリア。
## 戦闘: 毎ターン手札を引き、エネルギーを払ってカードを出す。ゲートのカードは光った候補マスに置く。
## 「注ぐ」でカップが左右に動き出し、止めた位置から玉を注ぐ。玉は弾倉に溜まり、ミニガンが敵を撃つ。
## 敵が残れば敵の番（攻撃・守り・強化・妨害）。盤面は戦闘ごとにリセットし、デッキはランを通して育つ。

const HAND_SIZE := 5
const HAND_MAX := 9
const ENERGY := 4
const EXTRA_CANDIDATES := 2  # 候補マス: 各列1つずつに加えて、ランダムに光るマスの数
const BALLS_PER_TURN := 10
const GATE_USES := 6
const FIRE_TIME := 2.0
const START_GOLD := 99
const SWEEP_SPEED := 520.0
const REMOVE_PRICE := 75
const ROUTE_LEN := 11  # 1章の層の数（最後がボス）
const TYPE_NAME := {"battle": "戦闘", "elite": "強敵", "shop": "ショップ", "rest": "休憩", "treasure": "宝箱", "boss": "ボス"}
const ENEMY_POS := Vector2(1530.0, 165.0)  # 台の上段の右
const ENEMY_R := 72.0
const BULLET_SPEED := 2600.0
const BULLET_RATE := 32.0
const DECK_POS := Vector2(120.0, 720.0)
const DISCARD_POS := Vector2(1800.0, 980.0)
const HAND_SCALE := 0.85  # 手札は左上に 3列で並べるので少し縮める

var R := {}  # ラン全体: gold, deck, relics, floor（HP はない。ノルマに届かなければランが終わる）
var S := {}  # いまの戦闘
var screen := "title"
var board: Board
var fx: Fx
var cam: Camera2D
var font: Font
var ui := {}
var hand_cards: Array = []
var panel: Control  # いま開いている画面（報酬・ショップ・休憩など）
var visible_world := false  # 敵・銃・弾を描くか（戦闘中だけ）
var _sprite_cache := {}  # 敵の id → ドット絵の形

var fire_t := 0.0
var fire_hp_start := 0.0
var bullet_acc := 0.0
var bullets: Array[Dictionary] = []
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
var demo_pour := false  # デモ: カードを置き終えたので、カップが狙いの位置に来たら注ぐ
var shots_dir := ""
var next_shot := 0.0
var shot_index := 0
const SHOT_START := 0.3
const SHOT_END := 10.5
const SHOT_INTERVAL := 0.1


func _ready() -> void:
	font = Style.font()
	_build_backdrop()
	cam = Camera2D.new()
	cam.position = Vector2(960, 540)
	add_child(cam)
	cam.make_current()

	board = Board.new()
	board.z_index = -1  # 台は奥。敵（台の上段）と弾は main が台の上に描く
	add_child(board)
	fx = Fx.new()
	add_child(fx)
	board.gate_passed.connect(_on_gate_passed)
	board.peg_hit.connect(_on_peg_hit)
	board.ball_collected.connect(_on_ball_collected)
	board.chip_gained.connect(_on_chip_gained)

	_build_hud()
	_build_top_bar()

	R = _new_run()
	S = _empty_battle()
	_parse_args()
	if not demo:
		_show_title()


## いちばん奥に渦を巻く背景、いちばん手前にブラウン管風の仕上げを重ねる
func _build_backdrop() -> void:
	var back := CanvasLayer.new()
	back.layer = -10
	add_child(back)
	var swirl := ColorRect.new()
	swirl.size = Vector2(1920, 1080)
	swirl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/swirl.gdshader")
	sm.set_shader_parameter("col_bg", Style.BG)
	sm.set_shader_parameter("col_a", Style.BG_SWIRL_A)
	sm.set_shader_parameter("col_b", Style.BG_SWIRL_B)
	swirl.material = sm
	back.add_child(swirl)

	var front := CanvasLayer.new()
	front.layer = 100
	add_child(front)
	var crt := ColorRect.new()
	crt.size = Vector2(1920, 1080)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := ShaderMaterial.new()
	cm.shader = load("res://shaders/crt.gdshader")
	crt.material = cm
	front.add_child(crt)


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

## route は 1層ずつの中身: {"type": 戦闘・強敵・ショップ・休憩・宝箱・ボス, "enemy": 敵の id（戦闘のときだけ）}
func _new_run() -> Dictionary:
	return {"gold": START_GOLD, "deck": Data.START_DECK.duplicate(),
		"relics": [], "floor": 0, "removed": false, "route": _make_route()}


## 一本道の 11層を作る。1層目は戦闘、ボスの直前は休憩、最後はボス。
## ショップ・宝箱・強敵・もう1つの休憩の位置はランごとにランダム（地図はなく、選ぶこともない）
func _make_route() -> Array:
	var types := []
	types.resize(ROUTE_LEN)
	types.fill("battle")
	types[ROUTE_LEN - 1] = "boss"
	types[ROUTE_LEN - 2] = "rest"
	var free := range(2, ROUTE_LEN - 2)  # 3層目からボスの2つ前まで
	free.shuffle()
	for t in ["shop", "treasure", "elite", "rest"]:
		types[free.pop_back()] = t
	var route := []
	for i in ROUTE_LEN:
		var node := {"type": types[i]}
		match types[i]:
			"battle":
				node["enemy"] = (Data.EASY_POOL if i < 3 else Data.NORMAL_POOL).pick_random()
			"elite":
				node["enemy"] = Data.ELITE_POOL.pick_random()
			"boss":
				node["enemy"] = "pegking"
		route.append(node)
	return route


func has_relic(id: String) -> bool:
	return R["relics"].has(id)


func _start_run() -> void:
	R = _new_run()
	_next_floor()


func _show_title() -> void:
	screen = "title"
	_set_battle_visible(false)
	ui["top"].visible = false
	var p := _open_panel("")
	p.color = Color(Style.BG, 0.35)  # 渦の背景を見せる
	var t := _label(p, Vector2(0, 230), 112, Style.GOLD)
	t.text = "カップ × ゲート × ミニガン"
	t.size = Vector2(1920, 140)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.pivot_offset = t.size / 2.0
	t.add_theme_constant_override("shadow_offset_y", 8)
	var wob := t.create_tween().set_loops()
	wob.tween_property(t, "rotation_degrees", 1.5, 1.6).set_trans(Tween.TRANS_SINE)
	wob.tween_property(t, "rotation_degrees", -1.5, 1.6).set_trans(Tween.TRANS_SINE)
	var sub := _label(p, Vector2(0, 400), 32, Style.INK_DIM)
	sub.text = "玉を注いで、ゲートで増やして、撃ち抜くデッキ構築ローグライト（試作）"
	sub.size = Vector2(1920, 50)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(p, Vector2(760, 560), Vector2(400, 110), "はじめる", _start_run, "blue")
	_button(p, Vector2(760, 700), Vector2(400, 90), "音量", _toggle_volume, "grey")
	var help := _label(p, Vector2(0, 900), 24, Color(1, 1, 1, 0.5))
	help.text = "カードをクリック → 光ったマスに置く　／　スペースかボタンで注ぐ → もう一度で止める　／　右クリックで選択取り消し"
	help.size = Vector2(1920, 40)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## 次の層へ進む（戦闘・ショップ・休憩・宝箱が終わるたびに呼ぶ）
func _next_floor() -> void:
	_close_panel()
	R["floor"] += 1
	ui["top"].visible = true
	var node: Dictionary = R["route"][R["floor"] - 1]
	fx.float_text(Vector2(960, 160), "第 %d 層 — %s" % [R["floor"], TYPE_NAME[node["type"]]], Color(1.0, 0.9, 0.5), 44,
		30.0, 1.4)
	match node["type"]:
		"battle", "elite", "boss":
			_start_battle(node["enemy"])
		"shop":
			_show_shop()
		"rest":
			_show_rest()
		"treasure":
			_show_treasure()


## 次のその種類の層まで、あと何層か（この先に無ければ -1）
func _floors_until(t: String) -> int:
	for i in range(R["floor"], R["route"].size()):
		if R["route"][i]["type"] == t:
			return i + 1 - R["floor"]
	return -1


# ============================================================
# 戦闘の流れ
# ============================================================

## turn は今のターン番号、turns は制限ターン（このターン数のうちにノルマへ届けば勝ち）
func _empty_battle() -> Dictionary:
	return {"phase": "none", "draw": [], "discard": [], "exhaust": [], "hand": [], "energy": 0,
		"balls": 0, "ammo": 0.0, "ammo_mul": 1.0, "per_ball": 0, "chip": 0, "next_energy": 0, "next_draw": 0,
		"enemy": Data.scaled_enemy("slime", 1), "selected": -1, "turn": 0, "turns": 3}


func _start_battle(enemy_id: String) -> void:
	_close_panel()
	screen = "battle"
	ui["top"].visible = true
	_set_battle_visible(true)
	S = _empty_battle()
	S["enemy"] = Data.scaled_enemy(enemy_id, R["floor"])
	S["draw"] = R["deck"].duplicate()
	S["draw"].shuffle()
	S["turns"] = S["enemy"]["turns"] + (1 if has_relic("watch") else 0)
	board.clear_board()
	board.reset_pegs()
	board.add_bonus = 1.0 if has_relic("whetstone") else 0.0
	board.mul_bonus = 0.5 if has_relic("double") else 0.0
	# 敵のハンデ: デメリットゲートを決まった場所に置く（戦闘のあいだずっと残る）
	for g in S["enemy"]["gates"]:
		board.place(g[1] * Board.COLS + g[2], g[0], _gate_uses())
	hp_trail = S["enemy"]["hp"]
	enemy_scale = 0.0
	enemy_offset = Vector2.ZERO
	create_tween().tween_property(self, "enemy_scale", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_start_turn()


func _start_turn() -> void:
	S["turn"] += 1
	S["phase"] = "turn"
	S["energy"] = ENERGY + S["next_energy"] + (1 if has_relic("hourglass") and S["turn"] == 1 else 0)
	S["balls"] = BALLS_PER_TURN + (2 if has_relic("heavy_cup") else 0) - (2 if _trait() == "fewer" else 0)
	S["ammo"] = 0.0
	S["ammo_mul"] = 1.2 if has_relic("belt") else 1.0
	S["per_ball"] = 0
	S["chip"] = 0
	S["selected"] = -1
	var draw_n: int = HAND_SIZE + S["next_draw"] + (1 if has_relic("pocket") else 0) - (1 if _trait() == "hand" else 0)
	S["next_energy"] = 0
	S["next_draw"] = 0
	pass_counts.clear()
	board.highlight.clear()
	board.refill(_gate_uses())
	board.sweep_speed = SWEEP_SPEED * (0.65 if has_relic("scope") else 1.0) * (1.6 if _trait() == "fast" else 1.0)
	if _trait() == "pegs":
		board.shuffle_pegs()
		_toast("ペグの並びが変わった")
	board.sweeping = true  # カップはターンのあいだずっと左右に動いている

	_rebuild_hand()
	_draw_cards(draw_n)


## 1ターンにゲート1つが働く回数（敵のデメリットゲートも同じ）
func _gate_uses() -> int:
	return maxi(GATE_USES + (2 if has_relic("oil") else 0) - (2 if _trait() == "drain" else 0), 1)


## いま戦っている敵の固有ハンデ（無ければ ""）
func _trait() -> String:
	return S["enemy"].get("trait", "")


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
		tw.tween_property(card, "scale", Vector2.ONE * card.base_scale, 0.35).set_delay(k * 0.07)
		tw.tween_property(card, "modulate:a", 1.0, 0.2).set_delay(k * 0.07)
		get_tree().create_timer(k * 0.07).timeout.connect(fx.sound.bind("tap", -14.0, 1.2))


func _play_card(i: int) -> void:
	if S["phase"] != "turn" or i < 0 or i >= S["hand"].size():
		return
	var id: String = S["hand"][i]
	var card := Data.info(id)
	if S["energy"] < card["cost"]:
		_toast("エネルギーが足りない")
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
		_toast("盤面が埋まっていて置けない")
		return
	# 候補マスはカード1枚ごとに一度だけ抽選する（選び直しても変わらない）。埋まったマスは外し、全部埋まったときだけ引き直す
	var card_node: Card = hand_cards[i]
	var cands: Array = card_node.candidates.filter(func(k): return board.slots[k] == null)
	if cands.is_empty():
		cands = _roll_candidates(empty)
		card_node.candidates = cands
	S["selected"] = i
	board.highlight.clear()
	for k in cands:
		board.highlight[k] = true
	fx.sound("click")


## 候補マスの抽選: 各列から空きマスを1つずつ（どの列にも置ける）＋残りからランダムに EXTRA_CANDIDATES 個
func _roll_candidates(empty: Array[int]) -> Array:
	var out := []
	for col in Board.COLS:
		var in_col := empty.filter(func(k): return k % Board.COLS == col)
		if not in_col.is_empty():
			out.append(in_col.pick_random())
	var rest := empty.filter(func(k): return not out.has(k))
	rest.shuffle()
	out.append_array(rest.slice(0, EXTRA_CANDIDATES))
	return out


func _cancel_select() -> void:
	S["selected"] = -1
	board.highlight.clear()


func _place_selected(slot: int) -> void:
	var i: int = S["selected"]
	var id: String = S["hand"][i]
	var card := Data.info(id)
	S["energy"] -= card["cost"]
	board.place(slot, card["gate"], _gate_uses(), card.get("val", 0.0), card.get("uses_bonus", 0))
	board.highlight.clear()
	S["selected"] = -1
	var c: Color = Board.GATE_DEFS[card["gate"]]["color"]
	fx.burst(Board.slot_rect(slot).get_center(), c, 18, 380.0, 34.0, 0.4, "star_06")
	fx.sound("tink", -4.0, 0.8)
	_discard_card(i, false, Board.slot_rect(slot).get_center())


func _instant(id: String) -> void:
	var v: float = Data.info(id)["val"]
	match Data.base_id(id):
		"more":
			S["balls"] += int(v)
			fx.float_text(Vector2(board.cup_x, Board.CUP_Y - 70), "玉 +%d" % v, Color(1.0, 0.9, 0.5))
		"extend":
			S["turns"] += int(v)
			fx.float_text(ENEMY_POS + Vector2(0, -230), "制限ターン +%d" % v, Color(0.6, 0.9, 1.0), 34)
		"load":
			S["ammo_mul"] *= v
			fx.float_text(Vector2(960, 730), "弾倉 ×%.1f" % v, Color(1.0, 0.75, 0.4))
		"burst":
			S["per_ball"] += int(v)
			fx.float_text(Vector2(960, 730), "玉ごと +%d" % v, Color(1.0, 0.6, 0.4))
		"focus":
			S["energy"] += int(v)
			fx.float_text(Vector2(135, 100), "+%d" % v, Color(1.0, 0.75, 0.35), 44)
			_punch(ui["energy"])
		"refill", "prep":
			_draw_cards(int(v))
		"save":
			S["next_energy"] += int(v)
			fx.float_text(Vector2(135, 100), "次ターン +%d" % v, Color(1.0, 0.75, 0.35), 30)


## ターン終了: 動いているカップをその場で止め、そこから玉を注ぐ（注ぐボタンかスペース）
func _pour() -> void:
	if S["phase"] != "turn":
		return
	S["phase"] = "pour"
	_cancel_select()
	for i in range(S["hand"].size() - 1, -1, -1):
		_discard_card(i, false)
	board.sweeping = false
	board.to_pour = S["balls"]
	fx.sound("tink", -4.0, 0.7)
	fx.burst(Vector2(board.cup_x, Board.CUP_Y - 40.0), Color(1.0, 0.9, 0.55), 14, 300.0, 28.0, 0.35, "star_06", 0.0)


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
	if demo_pour and S["phase"] == "turn":
		# デモでは、カードを置き終えたあと、カップが2列目の真上に来たところで注ぐ
		var target := Board.BOARD_L + 1.5 * (Board.BOARD_R - Board.BOARD_L) / Board.COLS
		if absf(board.cup_x - target) < 12.0:
			demo_pour = false
			_pour()

	if screen == "battle":
		match S["phase"]:
			"pour":
				if board.to_pour == 0 and board.balls.is_empty():
					_start_fire()
			"fire":
				_update_fire(delta)
			"next":
				phase_timer -= delta
				if phase_timer <= 0.0:
					_start_turn()

	_update_bullets(delta)
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
	# 弾倉の倍率は玉の分だけにかける。刻みゲートの分は倍率の影響を受けない
	S["ammo"] = S["ammo"] * S["ammo_mul"] + S["chip"]
	S["phase"] = "fire"
	fire_t = 0.0
	fire_hp_start = S["enemy"]["hp"]
	bullet_acc = 0.0
	dmg_window = 0.0
	dmg_window_t = 0.0
	if S["ammo"] <= 0.0:
		fire_t = FIRE_TIME


func _ammo_left() -> float:
	if S.get("phase", "") == "fire":
		return maxf(S["ammo"] * (1.0 - fire_t / FIRE_TIME), 0.0)
	return S.get("ammo", 0.0)


func _update_fire(delta: float) -> void:
	var before: float = S["enemy"]["hp"]
	fire_t += delta
	# 撃った量だけ、残りノルマ（敵の HP として見せている）が減る
	S["enemy"]["hp"] = fire_hp_start - S["ammo"] * minf(fire_t / FIRE_TIME, 1.0)
	dmg_window += before - S["enemy"]["hp"]
	dmg_window_t += delta

	if S["ammo"] > 0.0:
		bullet_acc += BULLET_RATE * delta
		while bullet_acc >= 1.0:
			bullet_acc -= 1.0
			# 受け皿のどこかから、台を突き抜けて上段の敵へ撃ち上げる
			var bw := (Board.BOARD_R - Board.BOARD_L) / Board.BUCKETS.size()
			var muzzle := Vector2(Board.BOARD_L + (randi() % Board.BUCKETS.size() + 0.5) * bw, Board.BUCKET_TOP - 6.0)
			var d := (ENEMY_POS + Vector2(randf_range(-30, 30), randf_range(-20, 20)) - muzzle).normalized()
			bullets.append({"p": muzzle, "v": d * BULLET_SPEED})
			fx.flash(muzzle, "muzzle_0%d" % randi_range(1, 2), 110.0, d.angle() + PI / 2.0, 0.06, Color(1.0, 0.8, 0.4))
			fx.sound("gun", -8.0, 1.1)
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
		elif S["turn"] >= S["turns"]:
			_quota_failed()
		else:
			S["phase"] = "next"
			phase_timer = 0.8


func _update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bl := bullets[i]
		bl["p"] += bl["v"] * delta
		if bl["p"].distance_to(ENEMY_POS) < ENEMY_R * 0.8:
			bullets.remove_at(i)
			fx.burst(bl["p"], Color(1.0, 0.75, 0.35), 5, 260.0, 20.0, 0.25, "spark_04", 200.0)
			fx.sound("hit", -10.0)
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
	get_tree().create_timer(1.0).timeout.connect(_after_victory)


## 制限ターンを使い切ってもノルマに届かなかった: ランはここで終わり
func _quota_failed() -> void:
	S["phase"] = "over"
	shake = 14.0
	fx.sound("hurt", -2.0)
	ui["flash"].color = Color(0.9, 0.1, 0.1, 0.35)
	create_tween().tween_property(ui["flash"], "color:a", 0.0, 0.5)
	var tw := create_tween()
	tw.tween_property(self, "enemy_scale", 1.25, 0.15)
	tw.tween_property(self, "enemy_scale", 1.0, 0.2)
	get_tree().create_timer(1.2).timeout.connect(_show_game_over)


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


func _on_ball_collected(val: float, pos: Vector2, mult: float) -> void:
	# 落ちた受け皿の倍率がかかる（真ん中ほど高い）
	S["ammo"] += (val + S["per_ball"]) * mult
	var col := Style.GOLD if mult >= 2.0 else (Style.ORANGE if mult >= 1.0 else Style.INK_DIM)
	fx.burst(Vector2(pos.x, Board.BUCKET_TOP + 10), col, 8, 260.0, 26.0, 0.35, "spark_01", 600.0)
	if mult != 1.0:
		fx.float_text(Vector2(pos.x, Board.BUCKET_TOP - 10), "×%s" % ("%.1f" % mult).trim_suffix(".0"), col, 26, 40.0, 0.5)
	fx.sound("collect", -10.0)
	_punch(ui["ammo_val"])


func _on_chip_gained(amount: int, pos: Vector2) -> void:
	S["chip"] += amount
	fx.float_text(pos + Vector2(0, -20), "+%d" % amount, Color(0.75, 0.82, 0.95), 26, 40.0, 0.5)
	_punch(ui["ammo_val"])


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
	_button(p, Vector2(760, 680), Vector2(400, 90), "取らない", _next_floor, "grey")


func _take_card(id: String) -> void:
	R["deck"].append(id)
	fx.sound("click")
	_next_floor()


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
	_button(p, Vector2(760, 860), Vector2(400, 100), "店を出る", _next_floor, "blue")


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
	_button(p, Vector2(460, 380), Vector2(460, 200), "鍛える\nカードを1枚強化", _rest_upgrade, "yellow", 34)
	_button(p, Vector2(1000, 380), Vector2(460, 200), "削る\nカードを1枚削除", _rest_remove, "green", 34)


func _rest_remove() -> void:
	_pick_from_deck("削除するカードを選ぶ", _any_card, _rest_remove_card, _show_rest)


func _rest_remove_card(idx: int) -> void:
	R["deck"].remove_at(idx)
	fx.sound("hurt", -8.0, 1.4)
	_next_floor()


func _rest_upgrade() -> void:
	_pick_from_deck("強化するカードを選ぶ", _not_upgraded, _upgrade_card, _show_rest, true)


func _upgrade_card(idx: int) -> void:
	R["deck"][idx] = R["deck"][idx] + "+"
	fx.sound("win", -8.0, 1.6)
	_next_floor()


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
	_button(p, Vector2(760, 620), Vector2(400, 100), "進む", _next_floor, "blue")


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


## 山札・捨て札・除外の中身を一覧で見る（山札は順番が分からないように並べ替える）
func _show_pile(kind: String) -> void:
	if screen != "battle" or panel != null:
		return
	var cards: Array = S[kind].duplicate()
	var names := {"draw": "山札", "discard": "捨て札", "exhaust": "除外"}
	if kind == "draw":
		cards.sort()
	var p := _open_panel("%s（%d 枚）" % [names[kind], cards.size()])
	var per_row := 8
	for i in cards.size():
		var card := _make_card(p, cards[i], Vector2(960 - per_row * 100 + (i % per_row) * 200 + 10, 180 + (i / per_row) * 195))
		card.base_scale = 0.78
		card.scale = Vector2.ONE * 0.78
		card.pivot_offset = Vector2.ZERO
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cards.is_empty():
		var l := _label(p, Vector2(0, 460), 36, Style.INK_DIM)
		l.text = "まだ何もない"
		l.size = Vector2(1920, 50)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(p, Vector2(760, 960), Vector2(400, 90), "閉じる", _close_panel, "grey")


func _show_victory() -> void:
	screen = "victory"
	_set_battle_visible(false)
	var p := _open_panel("クリア！")
	var l := _label(p, Vector2(0, 320), 36, Color(1, 1, 1, 0.9))
	l.size = Vector2(1920, 200)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = "ペグの王を倒した！\nデッキ %d 枚 ／ レリック %d 個" % [R["deck"].size(), R["relics"].size()]
	fx.burst(Vector2(960, 300), Color(1.0, 0.85, 0.4), 60, 900.0, 70.0, 1.2, "star_06", 300.0)
	_button(p, Vector2(760, 640), Vector2(400, 100), "タイトルへ", _show_title, "blue")


func _show_game_over() -> void:
	screen = "over"
	var p := _open_panel("敗北……")
	var l := _label(p, Vector2(0, 340), 36, Color(1, 1, 1, 0.9))
	l.size = Vector2(1920, 140)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = "第 %d 層「%s」のノルマに届かなかった" % [R["floor"], S["enemy"]["name"]]
	_button(p, Vector2(760, 600), Vector2(400, 100), "タイトルへ", _show_title, "blue")


# ============================================================
# 入力
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if screen != "battle" or panel != null:
		return
	# スペース: 注ぐ（動いているカップをその場で止めて落とす）
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_pour()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and S["selected"] >= 0:
		_cancel_select()
	elif event.button_index == MOUSE_BUTTON_LEFT and S["phase"] == "turn" and S["selected"] >= 0:
		var idx := board.slot_at(get_global_mouse_position())
		if idx >= 0 and board.highlight.has(idx):
			_place_selected(idx)


# ============================================================
# 画面の部品
# ============================================================

func _label(parent: Node, pos: Vector2, font_size: int, color := Style.INK) -> Label:
	var l := Label.new()
	l.position = pos
	Style.ink(l, font_size, color)
	parent.add_child(l)
	return l


func _button(parent: Node, pos: Vector2, sz: Vector2, text: String, cb: Callable, color := "blue", font_size := 30) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = sz
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	# 色の名前 → 塊の色。blue は「いちばん押してほしいボタン」なので自分の色（橙）
	var palette := {"blue": Style.ORANGE, "grey": Style.PANEL.lightened(0.18), "yellow": Style.GOLD,
		"green": Style.TEAL, "red": Style.RED}
	Style.style_button(b, palette.get(color, Style.ORANGE), font_size)
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
	dim.color = Color(Style.BG, 0.88)
	ui["screens"].add_child(dim)
	if title != "":
		var t := _label(dim, Vector2(0, 86), 64, Style.GOLD)
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

	# 左の列（下）: 弾倉×倍率の箱、エネルギーと先の予定の窓。手札は左の列の上に並べる（_layout_hand）
	ui["ammo_val"] = _score_box(hud, Vector2(40, 730), Vector2(240, 110), "弾倉", Style.BLUE)
	_label(hud, Vector2(292, 752), 48, Style.INK).text = "×"
	ui["mul_val"] = _score_box(hud, Vector2(340, 730), Vector2(220, 110), "倍率", Style.RED)

	# 左下: エネルギーの玉（独立）と、ショップ・宝箱・休憩・強敵・ボスまであと何層かの札
	var orb := Panel.new()
	orb.position = Vector2(40, 872)
	orb.size = Vector2(170, 170)
	orb.add_theme_stylebox_override("panel", Style.box(Style.ORANGE, 85, 6, Style.ORANGE.darkened(0.45), 8))
	hud.add_child(orb)
	var e_title := _label(orb, Vector2(0, 28), 18, Style.INK)
	e_title.text = "エネルギー"
	e_title.size = Vector2(170, 30)
	e_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var energy := _label(orb, Vector2(0, 54), 60)
	energy.size = Vector2(170, 90)
	energy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ui["energy"] = energy
	var tile_cols := {"shop": Style.GOLD, "treasure": Style.TEAL, "rest": Color("5fbf6a"), "elite": Style.RED, "boss": Style.PURPLE}
	var ti := 0
	for t in ["shop", "treasure", "rest", "elite", "boss"]:
		var tile := Panel.new()
		tile.position = Vector2(226 + (ti % 3) * 126, 864 + (ti / 3) * 100)
		tile.size = Vector2(118, 92)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_theme_stylebox_override("panel", Style.box(Style.PANEL, 12, 4, tile_cols[t].darkened(0.2), 6))
		hud.add_child(tile)
		var tl := _label(tile, Vector2(0, 6), 20, tile_cols[t])
		tl.text = TYPE_NAME[t]
		tl.size = Vector2(118, 26)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var tv := _label(tile, Vector2(0, 30), 44, Style.INK)
		tv.size = Vector2(118, 56)
		tv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ui["ahead_" + t] = tv
		ti += 1

	# 右の細い列: 山札・捨て札・除外（押すと中身が見られる）と、このターンの上乗せ
	ui["pile_draw"] = _button(hud, Vector2(1712, 76), Vector2(192, 104), "", _show_pile.bind("draw"), "grey", 26)
	ui["pile_discard"] = _button(hud, Vector2(1712, 196), Vector2(192, 104), "", _show_pile.bind("discard"), "grey", 26)
	ui["pile_exhaust"] = _button(hud, Vector2(1712, 316), Vector2(192, 104), "", _show_pile.bind("exhaust"), "grey", 26)
	var mods := _label(hud, Vector2(1716, 450), 24, Style.ORANGE)
	mods.size = Vector2(190, 300)
	mods.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	ui["mods"] = mods

	var pour := _button(hud, Vector2(1712, 850), Vector2(192, 210), "", _pour, "blue", 30)
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
	bar.add_theme_stylebox_override("panel", Style.box(Style.PANEL_DARK, 0, 0, Style.PANEL_DARK, 6))
	layer.add_child(bar)
	ui["top"] = bar
	ui["top_gold"] = _label(bar, Vector2(24, 8), 32, Style.GOLD)
	ui["top_floor"] = _label(bar, Vector2(180, 8), 32, Style.INK)
	# レリックは数だけ出し、マウスを乗せると一覧と説明が出る
	var relics := _label(bar, Vector2(1360, 10), 24, Style.PURPLE.lightened(0.3))
	relics.mouse_filter = Control.MOUSE_FILTER_STOP
	ui["top_relics"] = relics
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


## 得点の箱（見出しと大きな数字）。数字の Label を返す
func _score_box(parent: Node, pos: Vector2, sz: Vector2, title: String, color: Color) -> Label:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", Style.box(color, 14, 5, color.darkened(0.5), 8))
	parent.add_child(p)
	var t := _label(p, Vector2(0, 6), 24, Style.INK_DIM)
	t.text = title
	t.size = Vector2(sz.x, 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var v := _label(p, Vector2(0, 38), 56, Style.INK)
	v.size = Vector2(sz.x, 70)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return v


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
	card.base_scale = HAND_SCALE
	card.scale = Vector2.ONE * HAND_SCALE
	card.pressed.connect(_on_card_pressed.bind(card))
	ui["hand"].add_child(card)
	hand_cards.append(card)
	return card


func _layout_hand() -> void:
	# 左の列の上に 3列で並べる（最大 9枚 = 3段）
	var n := hand_cards.size()
	for i in n:
		var card: Card = hand_cards[i]
		card.base_pos = Vector2(28 + (i % 3) * 188, 100 + (i / 3) * 206)
		card.create_tween().tween_property(card, "position", card.base_pos, 0.2).set_trans(Tween.TRANS_QUAD)


func _on_card_pressed(card: Card) -> void:
	var i := hand_cards.find(card)
	if i >= 0:
		_play_card(i)


## 注意を盤面の上に短く出す（文章の欄は持たない）
func _toast(text: String) -> void:
	fx.float_text(Vector2((Board.BOARD_L + Board.BOARD_R) / 2.0, Board.CUP_Y + 20), text, Style.INK, 34, 50.0, 1.2)


func _punch(node: Control) -> void:
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2.ONE * 1.25
	node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_ui() -> void:
	ui["top_gold"].text = "%d G" % R["gold"]
	ui["top_floor"].text = "第 %d 層／%d" % [R["floor"], ROUTE_LEN]
	for t in ["shop", "treasure", "rest", "elite", "boss"]:
		var n := _floors_until(t)
		ui["ahead_" + t].text = str(n) if n >= 0 else "—"
		ui["ahead_" + t].modulate.a = 1.0 if n >= 0 else 0.35
	ui["top_relics"].text = "レリック %d" % R["relics"].size()
	var tips := []
	for rid in R["relics"]:
		tips.append("%s：%s" % [Data.RELICS[rid]["name"], Data.RELICS[rid]["desc"]])
	ui["top_relics"].tooltip_text = "\n".join(tips) if not tips.is_empty() else "まだ持っていない"
	if screen != "battle":
		return
	ui["energy"].text = "%d/%d" % [S["energy"], ENERGY]
	ui["pile_draw"].text = "山札\n%d" % S["draw"].size()
	ui["pile_discard"].text = "捨て札\n%d" % S["discard"].size()
	ui["pile_exhaust"].text = "除外\n%d" % S["exhaust"].size()
	ui["ammo_val"].text = Board.fmt(_ammo_left() if S["phase"] == "fire" else S["ammo"] + S["chip"])
	ui["mul_val"].text = ("%.1f" % S["ammo_mul"]).trim_suffix(".0")
	var mods := []
	if S["per_ball"] > 0:
		mods.append("玉ごと +%d" % S["per_ball"])
	if S["next_energy"] > 0:
		mods.append("次ターン エネ +%d" % S["next_energy"])
	if S["next_draw"] > 0:
		mods.append("次ターン +%d 枚" % S["next_draw"])
	ui["mods"].text = "\n".join(mods)
	var turn: bool = S["phase"] == "turn"
	ui["pour"].disabled = not turn
	var waiting := {"pour": "注いで\nいる…", "fire": "撃って\nいる…", "next": "次の\nターンへ"}
	ui["pour"].text = "玉を%d個\n注ぐ\n（Space）" % S["balls"] if turn else waiting.get(S["phase"], "…")
	# 手札の浮き上がり: マウスの下にある一番上（右側）のカード1枚だけ。定位置の範囲で判定するので、浮いても外れない
	var mouse: Vector2 = ui["hand"].get_global_mouse_position()
	var hover_i := -1
	if panel == null:
		for i in range(hand_cards.size() - 1, -1, -1):
			var shrink := Card.SIZE * (1.0 - HAND_SCALE) / 2.0
			if Rect2(hand_cards[i].base_pos + shrink, Card.SIZE * HAND_SCALE).has_point(mouse):
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
	# 台の上段 = 敵: 左に名前・残りターン・ハンデ・ノルマ、右に敵の絵
	var lx := Board.BOARD_L + 10.0
	var kind := "ボス" if e.get("boss", false) else ("強敵" if e.get("elite", false) else "戦闘")
	draw_string(font, Vector2(lx, 112), "%s　%s" % [kind, e["name"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Style.INK)
	var left: int = maxi(S["turns"] - S["turn"] + (1 if S["phase"] in ["turn", "pour", "fire"] else 0), 0)
	var pill := Rect2(lx, 128, 230, 46)
	draw_style_box(Style.box(Style.RED if left <= 1 else Style.TEAL.darkened(0.2), 12, 4, Style.PANEL_DARK, 6), pill)
	draw_string(font, Vector2(pill.position.x, pill.position.y + 34), "残り %d ターン" % left, HORIZONTAL_ALIGNMENT_CENTER,
		pill.size.x, 30, Style.INK)
	# ハンデは札にして並べる（ゲート → 固有ハンデ）
	var tags: Array = []
	var counts := {}
	for g in e["gates"]:
		counts[g[0]] = counts.get(g[0], 0) + 1
	for k in counts:
		tags.append(["%s ×%d" % [Board.GATE_DEFS[k]["label"], counts[k]], Style.RED.darkened(0.35)])
	if e.has("trait"):
		tags.append([Data.TRAITS[e["trait"]], Style.PURPLE.darkened(0.3)])
	var tx := pill.end.x + 14.0
	var ty := 134.0
	for tag in tags:
		var w := font.get_string_size(tag[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 24.0
		if tx + w > ENEMY_POS.x - ENEMY_R - 20.0:
			tx = pill.end.x + 14.0
			ty += 36.0
		draw_style_box(Style.box(tag[1], 8, 3, Style.PANEL_DARK, 4), Rect2(tx, ty, w, 32))
		draw_string(font, Vector2(tx + 12, ty + 24), tag[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Style.INK)
		tx += w + 8.0
	# 残りノルマ（敵の HP として見せる）
	var bar := Rect2(lx, 196, ENEMY_POS.x - ENEMY_R - 40.0 - lx, 36)
	draw_style_box(Style.box(Style.PANEL_DARK, 10, 4, Style.PANEL_DARK, 6), bar.grow(4))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hp_trail / e["max"], 0.0, 1.0), bar.size.y)), Style.INK)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(e["hp"] / e["max"], 0.0, 1.0), bar.size.y)), Style.RED)
	var qt := "ノルマ あと %s ／ %s" % [Board.fmt(maxf(e["hp"], 0.0)), Board.fmt(e["max"])]
	draw_string_outline(font, Vector2(bar.position.x, bar.position.y + 28), qt, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 26, 5,
		Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(bar.position.x, bar.position.y + 28), qt, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 26, Style.INK)
	# 敵の体: 名前から作る左右対称のドット絵（敵ごとに形が決まっている）
	var r := ENEMY_R * enemy_scale * (1.12 if e.get("boss", false) else 1.0)
	if r > 1.0:
		_draw_enemy_sprite(c, r, e)

	for bl in bullets:
		var p: Vector2 = bl["p"]
		var tail: Vector2 = p - bl["v"].normalized() * 40.0
		draw_line(tail, p, Color(1.0, 0.85, 0.45, 0.9), 4.0)
		draw_circle(p, 3.5, Color(1.0, 0.95, 0.8))


## 敵のドット絵の形（11×10 のマス）。名前の hash を種にして、左右対称に作る。
## 0: 空き / 1: 体 / 2: 目 / 3: 口
func _enemy_pixels(id: String) -> Array:
	if _sprite_cache.has(id):
		return _sprite_cache[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var w := 11
	var h := 10
	var grid := []
	for y in h:
		var row := []
		row.resize(w)
		row.fill(0)
		grid.append(row)
	for y in h:
		for x in range(0, 6):
			# 真ん中ほど埋まりやすく、上下の端ほど空きやすい
			var dx := absf(x - 5.0) / 5.0
			var dy := absf(y - 4.5) / 4.5
			var p := 0.95 - dx * 0.55 - dy * dy * 0.5
			if rng.randf() < p:
				grid[y][x] = 1
				grid[y][w - 1 - x] = 1
	for y in range(2, 9):
		grid[y][5] = 1
	# 目と口
	for ex in [3, 7]:
		grid[3][ex] = 2
		grid[4][ex] = 2
	for mx in range(4, 7):
		grid[6][mx] = 3
	# 足（下の段）をランダムに
	for x in range(1, 5):
		if rng.randf() < 0.5:
			grid[9][x] = 1
			grid[9][w - 1 - x] = 1
	_sprite_cache[id] = grid
	return grid


func _draw_enemy_sprite(c: Vector2, r: float, e: Dictionary) -> void:
	var grid := _enemy_pixels(e["id"])
	var h := grid.size()
	var w: int = grid[0].size()
	var cs := r * 2.0 / w  # 1マスの大きさ
	var body := Color.from_hsv(e["hue"], 0.6, 0.95)
	var origin := c - Vector2(w * cs, h * cs) / 2.0
	var look := Vector2(-0.6, 1.0).normalized()  # 下の台を見下ろす
	# 影 → 縁取り → 体 → 目と口 の順に重ねる
	for pass_i in 3:
		for y in h:
			for x in w:
				var v: int = grid[y][x]
				if v == 0:
					continue
				var rc := Rect2(origin + Vector2(x, y) * cs, Vector2(cs, cs))
				match pass_i:
					0:
						draw_rect(Rect2(rc.position + Vector2(0, cs * 0.6), rc.size), Color(0, 0, 0, 0.35))
					1:
						draw_rect(rc.grow(4.0), body.darkened(0.6))
					2:
						var col := body
						if v == 2:
							col = Style.INK
						elif v == 3:
							col = body.darkened(0.55)
						elif y < h / 3:
							col = body.lightened(0.15)  # 上の方を明るく
						draw_rect(rc, col)
						if v == 2 and y == 4:
							# 瞳は銃の方を見る
							draw_rect(Rect2(rc.position + Vector2(cs * 0.25 + look.x * cs * 0.2, -cs * 0.4), Vector2(cs * 0.5, cs * 0.7)),
								Style.CARD_INK)
	if e.get("boss", false):
		# 王冠（ドット）
		var top := origin + Vector2(w * cs / 2.0, -cs * 0.2)
		for i in 5:
			var hx := top.x + (i - 2) * cs
			var hh := cs * (1.6 if i % 2 == 0 else 0.9)
			draw_rect(Rect2(hx - cs / 2.0, top.y - hh, cs, hh), Style.GOLD)
		draw_rect(Rect2(top.x - cs * 2.5, top.y - cs * 0.5, cs * 5, cs * 0.6), Style.GOLD.darkened(0.2))
	if enemy_flash > 0.0:
		for y in h:
			for x in w:
				if grid[y][x] != 0:
					draw_rect(Rect2(origin + Vector2(x, y) * cs, Vector2(cs, cs)), Color(1, 1, 1, 0.7 * enemy_flash))


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
		S["hand"] = ["mul", "bounce", "add", "add", "more"]
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
	demo_pour = true


## 画面めぐり: タイトル・ショップ・休憩・宝箱・戦闘・ボス戦・報酬・クリア・敗北を順に見せる
func _run_tour() -> void:
	R["relics"] = ["hourglass", "belt", "scope"]
	R["deck"].append_array(["bounce+", "power", "refill"])
	_show_title()
	await _wait(0.8)
	R["floor"] = 4
	ui["top"].visible = true
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
	board.place(5, "add", 6, 3.0)
	board.place(13, "inv", 6, 6.0)
	board.place(17, "mul", 6, 2.0)
	# 値が 1 未満の玉の見た目の確認（小さく描かれ、小数が出る）
	for v in [0.5, 0.05, 0.002]:
		board.balls.append({"p": Vector2(700 + v * 400, 300), "v": Vector2.ZERO, "val": v, "passed": {}, "pop": 0.0})
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


## 自動プレイ（確認用）: 戦闘は出せるカードを全部出して真ん中で止めて注ぐ。ショップなどは何もせず進む
func _run_auto() -> void:
	_start_run()
	var last := ""
	var last_floor := 0
	var played_turn := -1
	var steps := 0
	while screen not in ["victory", "over"] and steps < 4000:
		steps += 1
		Engine.time_scale = 4.0
		await _wait(0.1)
		if R["floor"] != last_floor:
			last_floor = R["floor"]
			var n: Dictionary = R["route"][R["floor"] - 1]
			print("層 %d  %s  %s  %d G  デッキ %d  レリック %s" % [R["floor"], TYPE_NAME[n["type"]], n.get("enemy", ""),
				R["gold"], R["deck"].size(), ",".join(R["relics"])])
		match screen:
			"battle":
				if S["phase"] == "turn" and played_turn == S["turn"]:
					if absf(board.cup_x - (Board.BOARD_L + Board.BOARD_R) / 2.0) < 40.0:
						_pour()
				elif S["phase"] == "turn":
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
					played_turn = S["turn"]
					if absf(board.cup_x - (Board.BOARD_L + Board.BOARD_R) / 2.0) < 40.0:
						_pour()
				elif S["phase"] == "none" and panel != null:
					var tag := "%s %d" % [S["enemy"]["name"], R["floor"]]
					if tag != last:
						last = tag
						print("   → %s を倒した（ターン %d）" % [S["enemy"]["name"], S["turn"]])
					_take_card(Data.CARDS.keys().pick_random())
			"shop", "rest", "treasure":
				_next_floor()
	print("結果: %s  層 %d" % [screen, R["floor"]])
	get_tree().quit()
