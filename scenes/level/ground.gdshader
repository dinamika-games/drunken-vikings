shader_type canvas_item;

// The grass of the land, seen from above, drawn in metres (one unit of the
// canvas is a metre): the painted lush grass, laid twice at different scales
// and turned, so that its repeat does not show, and blended in large slow
// patches with the drier grass (or, without it, a sunnier tint of the lush).

uniform sampler2D lush : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D dry : source_color, repeat_enable, filter_linear_mipmap;
uniform bool has_dry = false;

// How many metres one copy of the textures covers.
uniform float metres = 32.0;

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

float fbm(vec2 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += noise(p) * amplitude;
		p = p * 2.03 + vec2(17.1, 9.3);
		amplitude *= 0.5;
	}
	return sum;
}

vec3 grass(sampler2D tex, vec2 uv, float mixing) {
	// The second copy is turned and larger, so that the two never repeat together.
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec3 one = texture(tex, uv).rgb;
	vec3 two = texture(tex, turn * uv * 0.73 + vec2(0.37, 0.71)).rgb;
	return mix(one, two, mixing);
}

void fragment() {
	vec2 uv = world / metres;
	float mixing = smoothstep(0.3, 0.7, fbm(world * 0.02));
	vec3 lush_color = grass(lush, uv, mixing);
	vec3 dry_color;
	if (has_dry) {
		dry_color = grass(dry, uv, mixing);
	} else {
		float grey = dot(lush_color, vec3(0.3, 0.59, 0.11));
		dry_color = mix(vec3(grey), lush_color, 0.6) * vec3(1.18, 1.08, 0.72);
	}
	float dryness = smoothstep(0.45, 0.7, fbm(world * 0.004 + vec2(3.7, 1.3)));
	vec3 color = mix(lush_color, dry_color, dryness * 0.85);
	// Soft light and shade over the hills.
	color *= 0.9 + 0.18 * fbm(world * 0.008 + vec2(9.1, 4.4));
	COLOR = vec4(color, 1.0);
}
