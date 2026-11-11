shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D wood : filter_nearest, repeat_enable;
uniform sampler2D rubble : filter_nearest, repeat_enable;
uniform sampler2D brick : filter_nearest, repeat_enable;
uniform sampler2D concrete : filter_nearest, repeat_enable;
uniform sampler2D alloy0 : filter_nearest;
uniform sampler2D alloy1 : filter_nearest;
uniform sampler2D alloy2 : filter_nearest;
uniform sampler2D alloy3 : filter_nearest;
uniform sampler2D alloy4 : filter_nearest;
uniform sampler2D alloy5 : filter_nearest;
uniform vec2 world_start;
uniform vec2 world_size;
uniform vec2 wood_size;
uniform vec2 rubble_size;
uniform vec2 brick_size;
uniform vec2 concrete_size;
uniform vec2 mask_start;
uniform vec2 mask_size;
uniform sampler2D remaining_cells : filter_nearest;
uniform sampler2D exposed : filter_nearest, repeat_disable;

bool occupied(vec2 center) {
	float r = length(center);
	return r >= 10000.0 && r < 10015.0 && texture(remaining_cells,(center-mask_start)/mask_size).r > 0.5;
}

vec4 metal(float id, vec2 uv) {
	if (id < 0.5) return texture(alloy0,uv);
	if (id < 1.5) return texture(alloy1,uv);
	if (id < 2.5) return texture(alloy2,uv);
	if (id < 3.5) return texture(alloy3,uv);
	if (id < 4.5) return texture(alloy4,uv);
	return texture(alloy5,uv);
}

float hash2(vec2 p) {
	int h = int(p.x)*374761393 + int(p.y)*668265263 + 1337;
	h = (h ^ (h >> 13))*1274126177;
	return float(h & 1023)/1023.0;
}

float rust_field(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash2(cell),hash2(cell+vec2(1,0)),f.x),mix(hash2(cell+vec2(0,1)),hash2(cell+vec2(1,1)),f.x),f.y);
}

void fragment() {
	vec2 p = world_start + UV * world_size;
	// Preserve the original whole-cell placement and staircase silhouette.
	vec2 contour = floor(p)+0.5;
	float radius = length(contour);
	vec2 art = p * vec2(80.0,64.0);
	vec2 old_uv = vec2(mod(floor(p.x)+floor(floor(p.y)/2.0),3.0)+fract(p.x),mod(floor(p.y),2.0)+fract(p.y))/vec2(3,2);
	vec4 c = vec4(0.0);
	if (radius >= 9985.0 && radius < 10015.0) {
		float opacity = 1.0;
		if (radius < 10000.0) {
			float outer_edge = 1.0;
			float wall_edge = 1.0;
			// Distance to the neighboring square edges also follows the tread at a corner.
			if (radius < 9987.0 || radius > 9998.0) {
				for (int y = -1; y <= 1; y++) {
					for (int x = -1; x <= 1; x++) {
						vec2 neighbor = contour + vec2(float(x),float(y));
						float gap = length(max(abs(p-neighbor)-0.5,vec2(0.0)));
						float r = length(neighbor);
						if (r < 9985.0) outer_edge = min(outer_edge,gap);
						if (r >= 10000.0) wall_edge = min(wall_edge,gap);
					}
				}
			}
			float body = mix(0.50,0.72,smoothstep(9985.0,10000.0,length(p)));
			opacity = mix(0.24,body,smoothstep(0.0,0.45,outer_edge));
			opacity = mix(1.0,opacity,smoothstep(0.0,1.0,wall_edge));
		}
		c = vec4(vec3(0.23),opacity);
	}
	vec4 background = c;
	if (radius >= 10000.0 && radius < 10005.0) c = texture(wood,art/wood_size);
	else if (radius >= 10005.0 && radius < 10009.0) c = texture(rubble,old_uv);
	else if (radius >= 10009.0 && radius < 10012.0) c = texture(brick,art/brick_size);
	else if (radius >= 10012.0 && radius < 10014.0) c = texture(concrete,old_uv);
	else if (radius >= 10014.0 && radius < 10015.0) {
		// A stable local field chooses existing rust pixels, never whole heavy-rust blocks.
		float id = min(5.0,floor(rust_field(p*vec2(4.0,3.0))*6.0));
		vec2 uv = fract(p);
		// Remove single-block outer bevels; keep the original interior metal plates.
		uv = (vec2(202.0,197.0)+uv*vec2(998.0,608.0))/vec2(1402.0,1122.0);
		c = metal(id,uv);
	}
	if (radius >= 10000.0 && radius < 10015.0) {
		if (!occupied(contour)) {
			c = background;
		} else {
			bool left = !occupied(contour-vec2(1,0));
			bool right = !occupied(contour+vec2(1,0));
			bool back = !occupied(contour-vec2(0,1));
			bool front = !occupied(contour+vec2(0,1));
			vec2 f = fract(p);
			float band = max(left ? 1.0-smoothstep(0.05,0.15,f.x) : 0.0,
				right ? smoothstep(0.85,0.95,f.x) : 0.0);
			band = max(band,back ? 1.0-smoothstep(0.06,0.20,f.y) : 0.0);
			band = max(band,front ? smoothstep(0.43,0.66,f.y) : 0.0);
			if (left && right && back && front) band = 1.0;
			if (band > 0.0) {
				float row = radius < 10005.0 ? 0.0 : radius < 10009.0 ? 1.0 : radius < 10012.0 ? 2.0 : radius < 10014.0 ? 3.0 : 4.0;
				float variants = row == 0.0 ? 12.0 : 6.0;
				float variant = min(variants-1.0,floor(hash2(floor(p))*variants));
				// Connected edges sample inside the bevel. Only an exposed front uses the end grain.
				vec2 src = mix(vec2(left ? 0.0 : 3.0,back ? 0.0 : 3.0),
					vec2(right ? 80.0 : 77.0,front ? 64.0 : 48.0),f);
				vec4 block = texture(exposed,(vec2(variant*80.0,row*64.0)+floor(src)+0.5)/vec2(textureSize(exposed,0)));
				c = mix(c,mix(background,vec4(block.rgb,1.0),block.a),band);
			}
		}
	}
	COLOR = c;
}
