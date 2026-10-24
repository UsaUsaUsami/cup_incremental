class_name Style
extends RefCounted
## 見た目の決まり（色・文字・パネルの形）を1か所にまとめる。
## 方向: ドット絵っぽさ＋前衛的な仕上げ（Balatro のような、渦を巻く背景・ブラウン管の質感・影を落とした角丸の塊）。
## 色は Balatro と同じにせず、このゲーム用に決める: 夜の藍と紫の地に、橙（自分）・赤（敵）・青緑（情報）・金。

const BG := Color("1b1c33")  # 地の藍
const BG_SWIRL_A := Color("2f3a86")  # 渦の色 1
const BG_SWIRL_B := Color("5a2470")  # 渦の色 2
const PANEL := Color("262844")  # パネル
const PANEL_DARK := Color("15162a")  # パネルの縁・影
const SHADOW := Color(0.02, 0.02, 0.06, 0.85)
const INK := Color("f4efe1")  # 文字（生成り）
const INK_DIM := Color(0.96, 0.94, 0.88, 0.6)
const ORANGE := Color("ff9b2f")  # 自分（エネルギー・弾）
const RED := Color("ec4a5a")  # 敵・危険
const TEAL := Color("2ec4b6")  # 情報・残りターン
const BLUE := Color("3a7bd5")  # 弾倉の箱
const GOLD := Color("ffd166")
const PURPLE := Color("9b5de5")
const CARD := Color("f4efe1")  # カードの地
const CARD_INK := Color("1d1e33")

static var _font: Font


## 画面全体で使うドットのフォント（DotGothic16）。16 の倍数の大きさがいちばんくっきり見える
static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/DotGothic16-Regular.ttf")
	return _font


## 角丸の塊に、真下へずらした濃い影を付けたパネル
static func box(color: Color, radius := 12, border := 0, border_color := PANEL_DARK, shadow := 6) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	if border > 0:
		b.set_border_width_all(border)
		b.border_color = border_color
	if shadow > 0:
		b.shadow_color = SHADOW
		b.shadow_size = 1
		b.shadow_offset = Vector2(0, shadow)
	b.anti_aliasing = false
	return b


## 文字に濃い影を付ける（縁取りより、ドット絵らしく見える）
static func ink(l: Control, size: int, color := INK, shadow := 3) -> void:
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0.03, 0.03, 0.08, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", shadow)
	l.add_theme_constant_override("shadow_outline_size", 0)


## ボタン: 塊の色、乗せると明るく、押すと沈む
static func style_button(b: Button, color: Color, font_size := 32) -> void:
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", font_size)
	var dark := color.get_luminance() > 0.6
	var fc := CARD_INK if dark else INK
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, fc)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.0 if dark else 0.6))
	b.add_theme_constant_override("shadow_offset_y", 3)
	b.add_theme_stylebox_override("normal", box(color, 14, 4, color.darkened(0.45), 7))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.15), 14, 4, color.darkened(0.35), 9))
	var pressed := box(color.darkened(0.1), 14, 4, color.darkened(0.5), 2)
	pressed.content_margin_top = 6
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", box(PANEL.lightened(0.05), 14, 4, PANEL_DARK, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
