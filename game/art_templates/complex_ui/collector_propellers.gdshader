shader_type canvas_item;
render_mode unshaded;

uniform sampler2D parts_mask : filter_nearest, repeat_disable;
uniform sampler2D blade_texture : filter_nearest, repeat_disable;
uniform float angle = 0.0;
uniform bool original_only = false;

void fragment() {
	vec4 original = texture(TEXTURE, UV);
	vec2 p = UV / TEXTURE_PIXEL_SIZE;
	bool left = p.x >= 125.0 && p.x < 370.0 && p.y >= 440.0 && p.y < 860.0;
	bool right = p.x >= 1032.0 && p.x < 1277.0 && p.y >= 440.0 && p.y < 860.0;
	vec4 result = original;
	if (!original_only && (left || right)) {
		vec3 mask = texture(parts_mask, UV).rgb;
		if (mask.g < 0.5) {
			vec2 center = left ? vec2(246.0, 646.0) : vec2(1156.0, 646.0);
			float phase = left ? angle : -angle;
			// Rotate in the rotor plane, then restore the original side-view projection.
			vec2 local = (p - center) / vec2(0.55, 1.0);
			float c = cos(phase);
			float s = sin(phase);
			vec2 rotor = vec2(c * local.x + s * local.y, -s * local.x + c * local.y);
			// Reuse the original upper blade for an opposite, balanced blade pair.
			if (rotor.y > 0.0) { rotor = -rotor; }
			vec2 source = center + rotor * vec2(0.55, 1.0);
			vec4 blade = texture(blade_texture, source * TEXTURE_PIXEL_SIZE);
			vec4 backing = mask.b > 0.5 ? vec4(0.0) : original;
			float alpha = blade.a + backing.a * (1.0 - blade.a);
			result = vec4(alpha > 0.0 ? (blade.rgb * blade.a + backing.rgb * backing.a * (1.0 - blade.a)) / alpha : vec3(0.0), alpha);
		}
	}
	COLOR = result;
}
