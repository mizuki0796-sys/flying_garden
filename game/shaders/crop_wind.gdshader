shader_type canvas_item;

// Only instanced crop meshes carry this marker. All ordinary canvas commands
// retain their original vertices, colors and texture sampling.
uniform float animation_time = 0.0;
uniform float wind_strength = 0.0;

void vertex() {
	if (INSTANCE_CUSTOM.w > 0.5) {
		// GLES stores instance custom data in half floats. Split the phase into
		// exact integer + 1/1024 parts to avoid visible wind-phase quantization.
		float phase = INSTANCE_CUSTOM.x + (INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.z) / 1024.0;
		float bend = -wind_strength * (0.55
			+ sin(animation_time * (1.8 + wind_strength) + phase) * 0.45
			+ sin(animation_time * 5.3 + phase * 1.7) * 0.20);
		VERTEX.x += bend * CUSTOM0.y * CUSTOM0.x;
	}
}
