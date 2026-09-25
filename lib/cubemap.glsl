// lib/cubemap.glsl — the cube-face direction mapping, used by the cubemap BAKE host.
//
// A cubemap bake renders six square faces that are later assembled in DDS/GL order
// (+X, -X, +Y, -Y, +Z, -Z). To fill a face you need the 3D direction each of its pixels
// represents, and that mapping is a *specification*, not a preference: if it is wrong the
// cube looks subtly rotated or mirrored in the game while every face, on its own, looks
// perfectly reasonable.
//
// CHECK CORNERS, NOT FACE CENTRES. A face centre is the same colour under any rotation or
// mirror, so a centre-only test passes while the cube is visibly wrong. That is exactly how
// a real bug got through once.
//
// This is the same mapping the Vega Strike baker and its orientation self-test use
// (sky_core.gdshaderinc / bake_dir.gdshader in the Godot lab). Verified self-consistent:
// the 24 face corners (6 faces x 4 corners) collapse onto exactly 8 cube corners, each
// reached by exactly 3 faces, with every component +-1.
//
// GPL-3.0 (see LICENSE at the repository root).

#ifndef LIB_CUBEMAP_GLSL
#define LIB_CUBEMAP_GLSL

// f: 0..5 in DDS/GL order (+X, -X, +Y, -Y, +Z, -Z). u,v: 0..1 across the face.
vec3 faceDir(int f, float u, float v) {
	if (f == 0) {              // +X
		return vec3( 1.0, 1.0 - 2.0 * v, 1.0 - 2.0 * u);
	} else if (f == 1) {       // -X
		return vec3(-1.0, 1.0 - 2.0 * v, 2.0 * u - 1.0);
	} else if (f == 2) {       // +Y
		return vec3(2.0 * u - 1.0,  1.0, 2.0 * v - 1.0);
	} else if (f == 3) {       // -Y
		return vec3(2.0 * u - 1.0, -1.0, 1.0 - 2.0 * v);
	} else if (f == 4) {       // +Z
		return vec3(2.0 * u - 1.0, 1.0 - 2.0 * v,  1.0);
	}
	return vec3(1.0 - 2.0 * u, 1.0 - 2.0 * v, -1.0);   // -Z
}

#endif  // LIB_CUBEMAP_GLSL
