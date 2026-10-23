class_name Card
extends Control
## 手札・報酬のカード1枚。マウスを乗せると浮き上がり、押すと pressed を出す。

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

var _bg: Panel
var _style_normal: StyleBoxTexture
var _style_selected: StyleBoxTexture


## card_id はデッキの1枚（強化済みは "add+" のように末尾に "+"）
func setup(card_id: String, font: Font) -> void:
	id = card_id
	var info := Data.info(card_id)
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	_style_normal = _box("res://assets/ui/grey_square.png")
	_style_selected = _box("res://assets/ui/yellow_square.png")
	_bg = Panel.new()
	_bg.size = SIZE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_theme_stylebox_override("panel", _style_normal)
	add_child(_bg)

	# 上半分: ゲートの見本か、すぐ効くカードの印
	var gate: String = info.get("gate", "")
	var face := Panel.new()
	face.position = Vector2(16, 40)
	face.size = Vector2(SIZE.x - 32, 64)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face_box := StyleBoxFlat.new()
	face_box.set_corner_radius_all(10)
	face_box.bg_color = Board.GATE_DEFS[gate]["color"] if gate != "" else Color(0.22, 0.24, 0.32)
	face.add_theme_stylebox_override("panel", face_box)
	add_child(face)
	var face_text: String = info.get("icon", "★")
	if gate in ["add", "mul"]:
		face_text = info["name"]
	elif gate != "":
		face_text = Board.GATE_DEFS[gate]["label"]
	var face_label := _label(face_text, font, 36, Color.WHITE)
	face_label.size = face.size
	face_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	face.add_child(face_label)

	var kind := _label(Board.GATE_DEFS[gate]["kind"] + "ゲート" if gate != "" else "すぐ効く", font, 15, Color(0.25, 0.27, 0.33))
	kind.position = Vector2(16, 108)
	kind.size = Vector2(SIZE.x - 32, 20)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(kind)

	var name_label := _label(info["name"], font, 24,
		Color(0.1, 0.5, 0.2) if Data.is_up(card_id) else Color(0.12, 0.13, 0.17))
	name_label.position = Vector2(8, 128)
	name_label.size = Vector2(SIZE.x - 16, 30)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(name_label)

	var desc_text: String = Data.gate_desc(card_id) if gate != "" else info["desc"]
	var desc := _label(desc_text, font, 16, Color(0.2, 0.22, 0.28))
	desc.position = Vector2(14, 160)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	desc.custom_minimum_size = Vector2(SIZE.x - 28, 0)
	desc.size = Vector2(SIZE.x - 28, 60)
	add_child(desc)

	# 左上のコスト
	var cost := Panel.new()
	cost.position = Vector2(-10, -10)
	cost.size = Vector2(46, 46)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost_box := StyleBoxFlat.new()
	cost_box.set_corner_radius_all(23)
	cost_box.bg_color = Color(0.25, 0.45, 0.95)
	cost_box.set_border_width_all(3)
	cost_box.border_color = Color(0.85, 0.92, 1.0)
	cost.add_theme_stylebox_override("panel", cost_box)
	add_child(cost)
	var cost_label := _label(str(info["cost"]), font, 26, Color.WHITE)
	cost_label.size = cost.size
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.add_child(cost_label)

	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _set_hover(on: bool) -> void:
	if auto_hover:
		set_hover(on)


func set_hover(on: bool) -> void:
	if on == hovered:
		return
	hovered = on
	_refresh()


func _box(path: String) -> StyleBoxTexture:
	var b := StyleBoxTexture.new()
	b.texture = load(path)
	b.set_texture_margin_all(16)
	return b


func _label(text: String, font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func set_state(can_play: bool, is_selected: bool) -> void:
	if can_play == playable and is_selected == selected:
		return
	playable = can_play
	selected = is_selected
	_refresh()


func _refresh() -> void:
	_bg.add_theme_stylebox_override("panel", _style_selected if selected else _style_normal)
	modulate = Color.WHITE if playable else Color(0.55, 0.55, 0.6)
	var lift := 0.0
	if selected:
		lift = -40.0
	elif hovered and playable:
		lift = -24.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", base_pos + Vector2(0, lift), 0.15)
	tw.tween_property(self, "scale", Vector2.ONE * base_scale * (1.08 if (hovered and playable) or selected else 1.0), 0.15)
	z_index = 2 if hovered or selected else 0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
