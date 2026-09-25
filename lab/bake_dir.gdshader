// bake_dir.gdshader — orientation SELF-TEST for the bake pipeline.
//
// Renders the six cube faces side by side, colouring each pixel with the
// direction the DDS/GL cubemap spec assigns to that (face, u, v):
//     colour = normalize(dir) * 0.5 + 0.5
//
// IMPORTANT: check CORNERS, not just the face centres. A face centre is the same
// colour under any rotation or mirror, so a centre-only test passes while the
// face is visibly rotated in-game (which is exactly how a real bug got through).
// face_dir() is shared from sky_core.gdshaderinc so the test exercises the same
// mapping the baker uses.
shader_type canvas_item;

#include "res://sky_core.gdshaderinc"

const int FACES = 6;

void fragment() {
	float fx = UV.x * float(FACES);
	int f = int(floor(fx));
	float u = fract(fx);
	float v = UV.y;
	COLOR = vec4(normalize(face_dir(f, u, v)) * 0.5 + 0.5, 1.0);
}
