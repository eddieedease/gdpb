shader_type canvas_item;

// Soft dark vignette + a slow drifting highlight for cabinet ambiance.
uniform float strength : hint_range(0.0, 1.5) = 0.4;
uniform float radius : hint_range(0.2, 1.5) = 1.05;
uniform float softness : hint_range(0.05, 1.5) = 0.55;
uniform vec3 tint : source_color = vec3(0.05, 0.03, 0.1);
uniform float glow_strength : hint_range(0.0, 0.3) = 0.05;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	// Correct for screen aspect so the vignette stays circular in real pixels
	// instead of stretching into an oval on portrait vs. landscape tables.
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	uv.x *= screen_size.x / screen_size.y;
	float dist = length(uv);
	float vig = smoothstep(radius, radius - softness, dist);
	vec3 dark = tint * (1.0 - vig) * strength;

	float drift = sin(TIME * 0.15) * 0.5 + 0.5;
	float glow = smoothstep(0.9, 0.0, distance(UV, vec2(0.5, mix(0.15, 0.85, drift)))) * glow_strength;

	COLOR = vec4(dark + glow * vec3(0.6, 0.8, 1.0), 1.0 - vig * 0.02);
	COLOR.a = clamp((1.0 - vig) * strength + glow, 0.0, 0.9);
}
