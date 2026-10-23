class_name Fx
extends Node2D
## 演出の道具箱: 粒子の一発、飛び出す文字、一瞬の光、効果音。

const SOUNDS := {
	"tink": ["impactGlass_light_000", "impactGlass_light_001", "impactGlass_light_002", "impactGlass_light_003", "impactGlass_light_004"],
	"peg": ["impactMetal_light_000", "impactMetal_light_001", "impactMetal_light_002"],
	"collect": ["impactSoft_medium_000", "impactSoft_medium_001", "impactSoft_medium_002"],
	"gun": ["impactPunch_medium_000", "impactPunch_medium_001", "impactPunch_medium_002"],
	"hit": ["impactPlate_light_000", "impactPlate_light_001", "impactPlate_light_002"],
	"block": ["impactMetal_heavy_000"],
	"hurt": ["impactPunch_heavy_000"],
	"win": ["impactBell_heavy_000"],
	"click": ["click-a"],
	"tap": ["tap-a"],
}
const MIN_GAP := {"peg": 0.04, "gun": 0.055, "hit": 0.07, "tink": 0.03, "collect": 0.04}

var font: Font
var tex := {}
var streams := {}
var players: Array[AudioStreamPlayer] = []
var next_player := 0
var last_played := {}
var add_mat: CanvasItemMaterial


func _ready() -> void:
	font = load("res://assets/fonts/MPLUSRounded1c-Bold.ttf")
	for n in ["spark_01", "spark_04", "spark_05", "star_06", "muzzle_01", "muzzle_02", "light_01", "circle_05", "smoke_01", "flare_01"]:
		tex[n] = load("res://assets/fx/%s.png" % n)
	for key in SOUNDS:
		var list: Array = []
		for n in SOUNDS[key]:
			list.append(load("res://assets/sfx/%s.ogg" % n))
		streams[key] = list
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


func sound(key: String, volume_db := 0.0, pitch := 1.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_played.get(key, -10.0) < MIN_GAP.get(key, 0.0):
		return
	last_played[key] = now
	var p := players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = streams[key].pick_random()
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


## 粒子を一度だけ吹き出す。size は粒の大きさ（ピクセル）
func burst(pos: Vector2, color: Color, amount := 12, speed := 300.0, size := 26.0, life := 0.45,
		tex_name := "spark_01", gravity := 400.0, direction := Vector2.UP, spread := 180.0) -> void:
	var p := CPUParticles2D.new()
	p.texture = tex[tex_name]
	p.material = add_mat
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.damping_min = 80.0
	p.damping_max = 160.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	var s := size / float(p.texture.get_width())
	p.scale_amount_min = s * 0.5
	p.scale_amount_max = s
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life + 0.2, false).timeout.connect(p.queue_free)


## 一瞬だけ光る絵（銃口の火など）
func flash(pos: Vector2, tex_name: String, size: float, rot: float, life: float, color := Color.WHITE) -> void:
	var sp := Sprite2D.new()
	sp.texture = tex[tex_name]
	sp.material = add_mat
	sp.position = pos
	sp.rotation = rot
	sp.scale = Vector2.ONE * size / float(sp.texture.get_width())
	sp.modulate = color
	add_child(sp)
	var tw := sp.create_tween()
	tw.tween_property(sp, "modulate:a", 0.0, life)
	tw.tween_callback(sp.queue_free)


## 飛び出して消える文字（ダメージ数など）
func float_text(pos: Vector2, text: String, color: Color, font_size := 32, rise := 70.0, life := 0.8) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	l.size = Vector2(300, font_size + 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = pos - Vector2(150, font_size)
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2.ONE * 0.6
	l.z_index = 20
	add_child(l)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - rise, life).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, life * 0.4).set_delay(life * 0.6)
	tw.chain().tween_callback(l.queue_free)
