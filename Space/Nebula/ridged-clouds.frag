// ridged-clouds.frag — a raymarched filamentary nebula (world-space volume).
//
// A different family from gyroid-clouds: instead of smooth fbm billows, the density is a
// network of thin RIDGES, which is what supernova remnants and HII regions look like.
//
//     vec3 nebulaSky(vec3 camPos, vec3 dir, float pxPerDir, float dither, out vec3 transmittance);
//
// An original implementation of the ridged-filament idea -- see the note in
// ridged-clouds.inc.glsl about the non-free upstream shaders it is inspired by.
//
// GPL-3.0 (see LICENSE at the repository root).

#ifdef GL_ES
precision mediump float;
#endif
uniform vec2  u_resolution;
uniform float u_time;
uniform vec2  u_mouse;

// ===== PHYSICS ==================================================================
// Constants, the density field and the contract live in ridged-clouds.inc.glsl (below).

// ===== VARIABLES ================================================================
const float uFilScale   = 0.35;  // [0.05, 1.5] field scale: higher = finer strands
const float uFilFreq    = 1.70;  // [1.1, 2.6]  frequency growth per octave
const float uFilVoid    = 0.60;  // [0.05, 0.85] void threshold: higher = sparser strands
const float uFilCore    = 0.60;  // [0, 2]      extra brightness in the cores
const float uFilDensity = 0.25;  // [0.05, 6]   optical depth
const float uFilView    = 22.0;  // [4, 80]     how deep the ray marches
const float uFilSteps   = 96.0;  // [16, 192]   march steps: quality vs speed
const float uFilBright  = 0.08;  // [0, 4]      exposure
const float uFilHue     = 0.55;  // [0, 1]      base hue
const float uFilSat     = 0.45;  // [0, 1]      saturation

// ===== SHARED MATHS =============================================================
#include "Space/Nebula/ridged-clouds.inc.glsl"

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
	// Slowly orbit, looking into the field (preview framing only).
	float t = u_time * 0.05;
	vec3 camPos = vec3(cos(t), 0.3 * sin(t * 0.9), sin(t)) * 3.0;
	vec3 targetDir = normalize(-camPos);
	mat3 view = lookAt(targetDir, vec3(0.0, 1.0, 0.0));
	float fov = 70.0;
	vec3 dir = normalize(view * cameraRay(gl_FragCoord.xy, fov));
	float pxPerDir = 2.0 * tan(radians(fov * 0.5)) / u_resolution.y;

	float dither = ign(gl_FragCoord.xy);
	vec3 transmittance;
	vec3 col = nebulaSky(camPos, dir, pxPerDir, dither, transmittance);

	col = aces(col);
	gl_FragColor = vec4(pow(col, vec3(0.4545)), 1.0);
}
