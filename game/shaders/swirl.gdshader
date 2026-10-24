// 背景: ゆっくり渦を巻く、段々に塗り分けた模様（ドット絵らしく粗いピクセルにまとめる）
shader_type canvas_item;

uniform vec4 col_bg : source_color = vec4(0.106, 0.11, 0.2, 1.0);
uniform vec4 col_a : source_color = vec4(0.153, 0.165, 0.353, 1.0);
uniform vec4 col_b : source_color = vec4(0.231, 0.114, 0.31, 1.0);
uniform float speed = 0.12;
uniform float pixel_size = 6.0;  // 画面上の 1 ドットの大きさ
uniform float bands = 6.0;  // 色の段の数

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 p = floor(FRAGCOORD.xy / pixel_size) * pixel_size / res.y;
	vec2 c = vec2(res.x / res.y * 0.5, 0.5);
	vec2 d = p - c;
	float r = length(d);
	float t = TIME * speed;
	float a = atan(d.y, d.x) + r * 3.2 - t * 2.0;
	vec2 q = vec2(cos(a), sin(a)) * r;
	float n = sin(q.x * 6.0 + t * 3.0) * sin(q.y * 6.0 - t * 2.0);
	n += 0.5 * sin((q.x + q.y) * 9.0 + t * 4.0);
	n = clamp(n * 0.45 + 0.5, 0.0, 1.0);
	n = floor(n * bands) / bands;
	vec3 col = mix(col_bg.rgb, col_a.rgb, smoothstep(0.3, 0.6, n));
	col = mix(col, col_b.rgb, smoothstep(0.65, 0.95, n));
	COLOR = vec4(col, 1.0);
}
