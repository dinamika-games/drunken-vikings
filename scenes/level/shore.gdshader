shader_type canvas_item;

// The sand along the shores, drawn on a band (a Line2D) which follows the
// edge of the water: the middle of the band is the water line, and the water
// lies on the side where UV.y is 0 (see LakeMap._build_layers).
//
// Towards the land the sand dries, from dark wet sand to pale dry sand with a
// fine grain, and frays into the grass. Over the water, the foam of small
// waves laps up the beach and back, leaving the sand wet behind it.
//
// The band is drawn in metres (one unit of the canvas is a metre).

uniform vec4 wet : source_color = vec4(0.55, 0.47, 0.33, 1.0);
uniform vec4 dry : source_color = vec4(0.88, 0.80, 0.60, 1.0);
uniform vec4 foam : source_color = vec4(0.95, 0.98, 1.0, 1.0);

varying vec2 world;

void vertex() {
	world = VERTEX;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void fragment() {
	// From -1 (the outer edge over the water) through 0 (the water line) to 1
	// (the edge on the land).
	float s = UV.y * 2.0 - 1.0;

	// The waves come in slowly, a little out of step along the shore.
	float along = noise(world * 0.04) * 6.0;
	float wave = 0.5 + 0.5 * sin(TIME * 0.9 + along);
	float reach = mix(-0.25, 0.3, wave);

	float ragged = noise(world * 0.6) - 0.5;
	float grain = hash(floor(world * 6.0)) - 0.5;

	// The sand: wet where the waves reached, drying towards the land.
	float wetness = 1.0 - smoothstep(0.0, 0.55, s - reach * 0.6 + ragged * 0.1);
	vec3 sand = mix(dry.rgb, wet.rgb, wetness);
	sand += grain * 0.06 + (noise(world * 0.25) - 0.5) * 0.08;
	float sand_alpha = step(0.0, s) * (1.0 - smoothstep(0.75, 1.0, s + ragged * 0.25));

	// The foam at the front of the wave, a ragged white line.
	float front = abs(s - reach + ragged * 0.12);
	float foam_alpha = (1.0 - smoothstep(0.0, 0.09, front)) * (0.55 + 0.45 * noise(world * 1.3 + TIME * 0.3));
	// A thinner, fainter foam where the water meets the sand.
	foam_alpha = max(foam_alpha, (1.0 - smoothstep(0.0, 0.05, abs(s))) * 0.35);

	vec3 color = mix(sand, foam.rgb, foam_alpha);
	COLOR = vec4(color, max(sand_alpha, foam_alpha * step(-0.6, s)));
}
