shader_type canvas_item;
render_mode world_vertex_coords;

// The backdrop of the screens of choices (see ScreenBackdrop): the dim and
// the mirror of the players fade out over the clear rects (e.g., the fields
// and the pasture of the farm at home), so that what lies behind shows almost
// as it is, and the fog of the backdrop clears softly around them, not at a
// sharp edge.

const int MAX_CLEAR = 32;

// The clear rects in the pixels of the canvas: the position in xy, the size in zw.
uniform vec4 clear_rects[MAX_CLEAR];
uniform int clear_count = 0;

// How round the corners of the clear rects are, in pixels.
uniform float radius = 28.0;

// How far the fog clears around the clear rects, in pixels.
uniform float feather = 56.0;

// How much of the backdrop stays over the clear rects.
uniform float residue : hint_range(0.0, 1.0) = 0.08;

varying vec2 at;

void vertex() {
	at = VERTEX;
}

// The signed distance from the box of [half_size] with corners of [r] around
// the origin to [p]: negative inside.
float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	float d = 1e6;
	for (int i = 0; i < min(clear_count, MAX_CLEAR); i++) {
		vec4 rect = clear_rects[i];
		vec2 half_size = rect.zw * 0.5;
		float r = min(radius, min(half_size.x, half_size.y));
		d = min(d, rounded_box(at - rect.xy - half_size, half_size, r));
	}
	// NOTE (mristin):
	// The fog starts to clear a little outside the rects and is gone a little
	// inside them, so that their edges are already clear.
	float clear = 1.0 - smoothstep(-0.25 * feather, feather, d);
	COLOR.a *= mix(1.0, residue, clear);
}
