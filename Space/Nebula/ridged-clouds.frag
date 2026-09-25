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
const float uFilScale   = 0.22;  // [0.05, 1.5] field scale: higher = finer strands
const float uFilFreq    = 1.43;  // [1.1, 2.6]  frequency growth per octave
const float uFilVoid    = 0.65;  // [0.05, 0.85] void threshold: higher = sparser strands
const float uFilCore    = 0.00;  // [0, 2]      extra brightness in the cores
const float uFilDensity = 3.60;  // [0.05, 6]   optical depth
const float uFilView    = 25.0;  // [4, 80]     how deep the ray marches
const float uFilSteps   = 16.0;  // [16, 192]   march steps: quality vs speed
const float uFilBright  = 0.167;  // [0, 4]      exposure
const float uFilHue     = 0.695;  // [0, 1]      base hue
const float uFilSat     = 0.39;  // [0, 1]      saturation
const float uFilHueRange = 0.18; // [0, 2]      palette WIDTH: 0 = one hue, 1 = the wheel, >1 = wraps
const float uFilHueScale = 0.90; // [0.1, 6]    how finely the hue follows the clouds
const vec3  uFilBg = vec3(0.000, 0.000, 0.000);  // what shows THROUGH the gas (standalone backdrop)
const float uFilOpacity = 1.00;  // [0, 1]      how much light the gas blocks (lower = translucent)
const float uFilWarp    = 0.78;  // [0, 2]      domain warp: bends the strands (0 = straight)
const float uFilWarpScale = 0.60; // [0.02, 0.6] warp frequency: higher = busier bending

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
	//
	// The orbit radius FOLLOWS THE FIELD SCALE. This field's strand size goes as 1/uFilScale,
	// so a fixed radius parks the camera inside a single feature at large scales and renders
	// a flat wash -- with uFilScale 0.05 (features ~20 units) a 3-unit orbit showed nothing
	// at all, which looked exactly like a broken shader. Scaling with 1/uFilScale keeps the
	// preview informative at any setting.
	float t = u_time * 0.05;
	float orbit = 3.0 / max(uFilScale, 0.02);
	vec3 camPos = vec3(cos(t), 0.3 * sin(t * 0.9), sin(t)) * orbit;
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
