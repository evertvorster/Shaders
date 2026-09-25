// volumetric_starfield.frag — a starfield you can fly through (world-anchored star volume).
//
//     vec3 volumetricStarfieldSky(vec3 camPos, vec3 dir, float pxPerDir, float dither, out vec3 transmittance);
//
// Local stars only: the march is bounded by uStvView, and the distant field is the dome's job
// (Space/Starfield). See volumetric_starfield.inc.glsl for why the split is necessary.
//
// GPL-3.0 (see LICENSE at the repository root).

#ifdef GL_ES
precision mediump float;
#endif
uniform vec2  u_resolution;
uniform float u_time;
uniform vec2  u_mouse;

// ===== PHYSICS ==================================================================
// The lattice, the star model and the contract live in volumetric_starfield.inc.glsl (below).

// ===== VARIABLES ================================================================
const float uStvCell    = 3.0;      // [1, 50]    cell size in world units: bigger = fewer, further apart
const float uStvDensity = 0.03;     // [0, 1]     fraction of cells that hold a star
const float uStvView    = 100.0;    // [10, 500]  how far the local volume reaches
const float uStvAng     = 0.0026;   // [0.0002, 0.006] star angular radius (direction units)
const float uStvBright  = 3.08;      // [0, 6]     exposure
const float uStvFalloff = 0.0028;   // [0.0001, 0.05] inverse-square scale: bigger = stars dim faster with distance
const float uStvSeed    = 0.0;      // [0, 100]   lattice seed

// ===== SHARED MATHS =============================================================
#include "Space/volumetric_starfield/volumetric_starfield.inc.glsl"

// ===== HOST (glslviewer) ========================================================
// Everything from this marker down is host plumbing and is REPLACED by the builder.

vec3 cameraRay(vec2 fragCoord, float fovDeg) {
	vec2 xy = fragCoord - u_resolution.xy * 0.5;
	float z = (0.5 * u_resolution.y) / tan(radians(fovDeg) * 0.5);
	return normalize(vec3(xy, -z));
}

vec3 aces(vec3 x) {
	return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main() {
	// Fly forward through the lattice, so the parallax is visible in the preview.
	float fov = 70.0;
	float speed = 12.0;
	vec3 camPos = vec3(0.0, 0.0, -u_time * speed);
	vec3 dir = normalize(cameraRay(gl_FragCoord.xy, fov));
	float pxPerDir = 2.0 * tan(radians(fov * 0.5)) / u_resolution.y;

	float dither = ign(gl_FragCoord.xy);
	vec3 transmittance;
	vec3 col = volumetricStarfieldSky(camPos, dir, pxPerDir, dither, transmittance);

	col = aces(col);
	gl_FragColor = vec4(pow(col, vec3(0.4545)), 1.0);
}
