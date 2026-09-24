// lib/hash.glsl — integer-lattice hashes, shared by every shader.
//
// Canonical sources keep `#include "lib/hash.glsl"` (repo-root-relative) and run in
// glslviewer with `-I <repo root>`. The builders inline the include, so generated
// per-host outputs stay self-contained.
//
// GPL-3.0 (see LICENSE at the repository root).

float hash13(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec3 hash33(vec3 p3) {
	return vec3(hash13(p3), hash13(p3 + 19.19), hash13(p3 + 41.77));
}
