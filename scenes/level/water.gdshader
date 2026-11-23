shader_type canvas_item;

// The water of the lakes, seen from above: slow swells of darker and lighter
// water, and small crests of waves which glint and drift with the wind.
//
// The polygon of the water is drawn in metres (one unit of the canvas is a
// metre), so the waves keep their size in metres whatever the zoom.

uniform vec4 deep : source_color = vec4(0.18, 0.36, 0.53, 1.0);
uniform vec4 shallow : source_color = vec4(0.27, 0.48, 0.66, 1.0);
uniform vec4 crest : source_color = vec4(0.85, 0.93, 1.0, 1.0);

// Where the wind blows to, and how fast the waves drift, in metres per second.
uniform vec2 wind = vec2(0.6, 0.8);
uniform float drift = 1.2;

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
		u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 along = normalize(wind);
	vec2 across = vec2(-along.y, along.x);
	vec2 p = world - along * drift * TIME;

	// The swells: large and slow.
	float swell = fbm(p * 0.012 + vec2(TIME * 0.01, 0.0));
	vec3 color = mix(deep.rgb, shallow.rgb, smoothstep(0.25, 0.75, swell));

	// The crests: short streaks across the wind, which come and go.
	vec2 q = vec2(dot(p, across), dot(p, along));
	float warp = fbm(p * 0.05) * 6.0;
	float lines = sin(q.y * 0.9 + warp + TIME * 1.3);
	float breakup = noise(vec2(q.x * 0.18, q.y * 0.35) + TIME * 0.15);
	float crests = smoothstep(0.86, 0.98, lines) * smoothstep(0.55, 0.85, breakup);

	// The glints: tiny sparkles of the sun.
	vec2 cell = floor(p * 0.8);
	vec2 inside = fract(p * 0.8) - 0.5;
	float sparkle = step(0.9985, hash(cell + floor(TIME * 2.0)));
	float glint = sparkle * smoothstep(0.25, 0.0, length(inside));

	color = mix(color, crest.rgb, crests * 0.3 + glint * 0.5);
	COLOR = vec4(color, 1.0);
}
