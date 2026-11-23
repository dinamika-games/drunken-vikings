shader_type canvas_item;

// A splash where an oar dips into the water: a bright swirl of foam at first,
// then rings which spread and fade.
//
// Each splash is a square drawn with a color which carries its state: red is
// its age (0 new, 1 gone), green its strength (a deep stroke splashes more).

void fragment() {
	float age = COLOR.r;
	float strength = COLOR.g;
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);

	float outer = smoothstep(0.09, 0.0, abs(r - (0.25 + 0.75 * age)));
	float inner = smoothstep(0.07, 0.0, abs(r - 0.55 * age));
	float fade = (1.0 - age) * strength;
	float rings = (outer + 0.6 * inner) * fade;

	// The foam of the dip: a swirl which dies out quickly.
	float angle = atan(d.y, d.x);
	float swirl = 0.6 + 0.4 * sin(angle * 5.0 + r * 12.0 - age * 10.0);
	float foam = smoothstep(0.45, 0.0, r) * swirl * (1.0 - smoothstep(0.0, 0.35, age)) * strength;

	float alpha = clamp(rings * 0.7 + foam * 0.9, 0.0, 1.0) * step(r, 1.0);
	COLOR = vec4(1.0, 1.0, 1.0, alpha);
}
