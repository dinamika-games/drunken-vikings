// The dots of How to play (see HowTo): a bead for each part, in a row, one
// square cell each. The parts done are amber beads, the part now a bigger
// gold bead which glows and breathes, with a ring which fills as the part
// plays (as the rope ring of the cards), and the parts to come dim glass.
// Each bead is shaded as a little sphere lit from the top left, with the ink
// outline of the pictures of the game.
shader_type canvas_item;

uniform int count = 8;
uniform float current = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;

const vec3 INK = vec3(0.165, 0.118, 0.078);
const vec3 AMBER = vec3(0.88, 0.56, 0.16);
const vec3 GOLD = vec3(0.95, 0.76, 0.31);
const vec3 GLASS = vec3(0.95, 0.90, 0.80);
const vec3 SUN = vec3(-0.45, -0.6, 0.66);

// The colour of a bead of the [radius] at [p] (from its middle, in cells),
// and its coverage in the alpha.
vec4 bead(vec2 p, float radius, vec3 base, float opacity, float aa) {
	float d = length(p);
	float inside = 1.0 - smoothstep(radius - aa, radius + aa, d);
	if (inside <= 0.0) {
		return vec4(0.0);
	}
	vec2 q = p / radius;
	float z = sqrt(max(0.0, 1.0 - dot(q, q)));
	vec3 normal = normalize(vec3(q, z));
	float diffuse = clamp(dot(normal, normalize(SUN)), 0.0, 1.0);
	float specular = pow(clamp(dot(reflect(-normalize(SUN), normal), vec3(0.0, 0.0, 1.0)), 0.0, 1.0), 18.0);
	vec3 color = base * (0.45 + 0.65 * diffuse) + vec3(1.0) * specular * 0.7;
	// The ink outline.
	float rim = smoothstep(radius - 0.06 - aa, radius - 0.06 + aa, d);
	color = mix(color, INK, rim);
	return vec4(color, inside * opacity);
}

void fragment() {
	float cells = float(count);
	float x = UV.x * cells;
	float index = floor(x);
	vec2 p = vec2(fract(x) - 0.5, UV.y - 0.5);
	// NOTE: The smoothing of the edges, from the position along the row
	// (fract jumps at the borders of the cells, which drew lines there).
	float aa = fwidth(x) * 1.2;
	// The glow and the ring fade out before the border of the cell.
	float inner = 1.0 - smoothstep(0.4, 0.49, max(abs(p.x), abs(p.y)));
	vec4 result = vec4(0.0);
	if (index < current - 0.5) {
		result = bead(p, 0.27, AMBER, 1.0, aa);
	} else if (index < current + 0.5) {
		float breath = 0.5 + 0.5 * sin(time * 3.0);
		float radius = 0.34 + 0.015 * breath;
		// The glow around the bead.
		float glow = exp(-max(0.0, length(p) - radius) * 14.0) * (0.35 + 0.25 * breath);
		result = vec4(GOLD, glow * step(radius, length(p)) * inner);
		// The ring which fills as the part plays, clockwise from the top.
		float angle = fract(atan(p.x, -p.y) / 6.2831853);
		float ring = (1.0 - smoothstep(0.025 - aa, 0.025 + aa, abs(length(p) - 0.42))) * inner;
		if (angle < progress) {
			result = mix(result, vec4(GOLD, 1.0), ring);
		} else {
			result = mix(result, vec4(INK, 0.5), ring);
		}
		vec4 core = bead(p, radius, GOLD, 1.0, aa);
		result = mix(result, core, core.a);
	} else {
		result = bead(p, 0.23, GLASS, 0.45, aa);
	}
	COLOR = result;
}
