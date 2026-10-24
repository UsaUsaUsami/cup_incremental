// 仕上げ: ブラウン管風（わずかな歪み・走査線・四隅の暗さ・色のにじみ）。画面のいちばん上に重ねる
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float curve = 0.025;  // 画面の丸み
uniform float scan = 0.10;  // 走査線の濃さ
uniform float vignette = 0.45;  // 四隅の暗さ
uniform float chroma = 1.2;  // 色のにじみ（ピクセル）

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 cc = uv - 0.5;
	float dist = dot(cc, cc);
	uv += cc * dist * curve;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec2 px = vec2(SCREEN_PIXEL_SIZE.x * chroma, 0.0);
		vec3 col;
		col.r = texture(screen_tex, uv + px).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - px).b;
		float line = sin(uv.y / SCREEN_PIXEL_SIZE.y * 3.14159) * 0.5 + 0.5;
		col *= 1.0 - scan * line;
		col *= 1.0 - vignette * dist * 1.6;
		COLOR = vec4(col, 1.0);
	}
}
