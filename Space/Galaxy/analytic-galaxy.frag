// analytic-galaxy.frag — the Milky Way as a semi-analytic band (no ray marching).
//
// A fixed backdrop: the column density along the view ray is the closed-form path
// integral of an exponential disk, so the band costs one divide instead of a hundred
// samples. Lit from the inside, dust-absorbing, with authored arms and turbulence.
//
//     vec3 galaxySky(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance);
//
// GPL-3.0 (see LICENSE at the repository root).

#ifdef GL_ES
precision mediump float;
#endif
uniform vec2  u_resolution;
uniform float u_time;
uniform vec2  u_mouse;

// ===== PHYSICS ==================================================================
// The disk constants and maths live in analytic-galaxy.inc.glsl (below).

// ===== VARIABLES ================================================================
const float uGalPitch       = 0.00;  // [0, 3.14]   tilt of the galactic plane (0 = world XZ)
const float uGalYaw         = 0.00;  // [0, 6.28]   yaw of the plane
const float uGalEmission    = 0.25;  // [0, 4]      how brightly the gas glows
const float uGalDust        = 2.50;  // [0, 6]      dust extinction over the path
const float uGalTurb        = 0.80;  // [0, 1]      turbulence on the column
const float uGalNoiseScale  = 0.50;  // [0.05, 2]   size of the turbulent structure
const float uGalArmCount    = 2.00;  // [1, 6]      number of spiral arms
const float uGalArmTwist    = 4.00;  // [1, 10]     how tightly the arms wind
const float uGalArmStrength = 0.60;  // [0, 1]      arm contrast
const float uGalSoftness    = 0.08;  // [0.01, 0.5] bounds the grazing-ray column
const float uGalBright      = 1.00;  // [0, 4]      exposure

// ===== SHARED MATHS =============================================================
#include "Space/Galaxy/analytic-galaxy.inc.glsl"

// ===== HOST (glslviewer) ========================================================
// Everything from this marker down is host plumbing and is REPLACED by the builder.
// The marker line itself (`// ===== HOST`) is what the builder splits on.

vec3 cameraRay(vec2 fragCoord, float fovDeg) {
	vec2 xy = fragCoord - u_resolution.xy * 0.5;
	float z = (0.5 * u_resolution.y) / tan(radians(fovDeg) * 0.5);
	return normalize(vec3(xy, -z));
}

vec3 aces(vec3 x) {
	return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main() {
	// Stand back and look at the galaxy as a distant object (preview framing only).
	vec3 camPos = vec3(0.0, 26.0, 60.0);
	vec3 targetDir = normalize(-camPos);
	mat3 view = lookAt(targetDir, vec3(0.0, 1.0, 0.0));
	float fov = 70.0;
	vec3 dir = normalize(view * cameraRay(gl_FragCoord.xy, fov));
	float pxPerDir = 2.0 * tan(radians(fov * 0.5)) / u_resolution.y;

	vec3 transmittance;
	vec3 col = galaxySky(camPos, dir, pxPerDir, transmittance);

	col = aces(col);
	gl_FragColor = vec4(pow(col, vec3(0.4545)), 1.0);
}
