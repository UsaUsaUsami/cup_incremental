class_name Card
extends Control
## 手札・報酬のカード1枚。マウスを乗せると浮き上がって少し傾き、押すと pressed を出す。
## 見た目: 生成りの地に濃い縁、下へずらした影。ふだんはゆっくり揺れている（ドット絵＋前衛的な仕上げ）。

signal pressed

const SIZE := Vector2(180, 230)

var id := ""
var playable := true
var selected := false
var hovered := false
var base_pos := Vector2.ZERO  # 手札での定位置（浮き上がりの基準）
var candidates: Array = []  # このカードを置ける候補マス（手札にある間は引き直さない）
var auto_hover := true  # false なら、浮き上がりは外から set_hover で決める（手札は main が決める）
var base_scale := 1.0  # 一覧などで縮めて並べるときの大きさ（浮き上がりはこれを基準にする）
var sway := true  # ふだんゆっくり揺らすか

var _bg: Panel
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _phase := randf() * TAU
var _tilt := 0.0  # 乗せたときの傾き（度）
var _t := 0.0


## card_id はデッキの1枚（強化済みは "add+" のように末尾に "+"）
func setup(card_id: String, _font: Font = null) -> void:
	id = card_id
	var info := Data.info(card_id)
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	_style_normal = Style.box(Style.CARD, 14, 5, Style.CARD_INK, 8)
	_style_selected = Style.box(Style.GOLD.lightened(0.4), 14, 5, Style.ORANGE.darkened(0.2), 12)
	_bg = Panel.new()
	_bg.size = SIZE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_theme_stylebox_override("panel", _style_normal)
	add_child(_bg)

	# 上半分: ゲートの見本か、すぐ効くカードの印
	var gate: String = info.get("gate", "")
	var face := Panel.new()
	face.position = Vector2(16, 36)
	face.size = Vector2(SIZE.x - 32, 72)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face_col: Color = Board.GATE_DEFS[gate]["color"] if gate != "" else Style.PANEL
	face.add_theme_stylebox_override("panel", Style.box(face_col, 10, 4, Style.CARD_INK, 0))
	add_child(face)
	var face_text: String = info.get("icon", "★")
	if gate in ["add", "mul"]:
		face_text = info["name"]
	elif gate != "":
		face_text = Board.GATE_DEFS[gate]["label"]
	var face_label := _label(face_text, 40, Style.INK, true)
	face_label.size = face.size
	face_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	face.add_child(face_label)

	var name_label := _label(info["name"], 28, Style.TEAL.darkened(0.35) if Data.is_up(card_id) else Style.CARD_INK)
	name_label.position = Vector2(8, 116)
	name_label.size = Vector2(SIZE.x - 16, 32)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(name_label)

	var desc_text: String = Data.gate_desc(card_id) if gate != "" else info["desc"]
	var desc := _label(desc_text, 18, Style.CARD_INK.lightened(0.25))
	desc.position = Vector2(14, 158)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	desc.custom_minimum_size = Vector2(SIZE.x - 28, 0)
	desc.size = Vector2(SIZE.x - 28, 60)
	add_child(desc)

	# 左上のコスト（エネルギーと同じ橙の玉）
	var cost := Panel.new()
	cost.position = Vector2(-12, -12)
	cost.size = Vector2(50, 50)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.add_theme_stylebox_override("panel", Style.box(Style.ORANGE, 25, 4, Style.CARD_INK, 4))
	add_child(cost)
	var cost_label := _label(str(info["cost"]), 32, Style.INK, true)
	cost_label.size = cost.size
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.add_child(cost_label)

	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _process(delta: float) -> void:
	# ふだんはゆっくり揺れ、乗せたときは少し傾く
	_t += delta
	var target := _tilt if hovered or selected else (sin(_t * 1.4 + _phase) * 1.2 if sway else 0.0)
	rotation_degrees = lerpf(rotation_degrees, target, minf(1.0, delta * 10.0))


func _set_hover(on: bool) -> void:
	if auto_hover:
		set_hover(on)


func set_hover(on: bool) -> void:
	if on == hovered:
		return
	hovered = on
	_tilt = randf_range(-4.0, 4.0)
	_refresh()


func _label(text: String, font_size: int, color: Color, shadow := false) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Style.ink(l, font_size, color, 3 if shadow else 0)
	if not shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


func set_state(can_play: bool, is_selected: bool) -> void:
	if can_play == playable and is_selected == selected:
		return
	playable = can_play
	selected = is_selected
	_refresh()


func _refresh() -> void:
	_bg.add_theme_stylebox_override("panel", _style_selected if selected else _style_normal)
	modulate = Color.WHITE if playable else Color(0.6, 0.6, 0.68)
	var lift := 0.0
	if selected:
		lift = -44.0
	elif hovered and playable:
		lift = -28.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", base_pos + Vector2(0, lift), 0.18)
	tw.tween_property(self, "scale", Vector2.ONE * base_scale * (1.1 if (hovered and playable) or selected else 1.0), 0.18)
	z_index = 2 if hovered or selected else 0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
