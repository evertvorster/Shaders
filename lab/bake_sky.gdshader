// bake_sky.gdshader — bake the procedural sky into a 6-face strip.
// Colour = skyColor(direction) for the direction the DDS/GL cubemap spec assigns
// to each (face, u, v). Rendered as one wide image: +X, -X, +Y, -Y, +Z, -Z.
shader_type canvas_item;

#include "res://sky_core.gdshaderinc"

const int FACES = 6;

void fragment() {
	float fx = UV.x * float(FACES);
	int f = int(floor(fx));
	float u = fract(fx);
	float v = UV.y;
	COLOR = vec4(skyColor(face_dir(f, u, v)), 1.0);
}
