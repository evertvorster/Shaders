// milkyway.frag — the Milky Way: overlapping core, bright band and dark band.
//
// We are inside it, so it stretches across the sky. Composed front to back: a dark
// turbulent dust band, a bright turbulent band behind it, and a galactic core. Both
// bands are thickest toward the core and taper to the tips.
//
//     vec3 milkywaySky(vec3 dir, float pxPerDir, out vec3 transmittance);
//
// GPL-3.0 (see LICENSE at the repository root).

#ifdef GL_ES
precision mediump float;
#endif
uniform vec2  u_resolution;
uniform float u_time;
uniform vec2  u_mouse;

// ===== PHYSICS ==================================================================
// The band maths lives in milkyway.inc.glsl (below).

// ===== VARIABLES ================================================================
const float uMwPitch      = 0.00;  // [0, 3.14]   tilt of the galactic plane
const float uMwYaw        = 0.00;  // [0, 6.28]   yaw of the plane
const float uMwCoreAngle  = 0.03;  // [0, 6.28]   where the core sits along the band
const float uMwDistance   = 0.90;  // [0.25, 4]   scale every element: further / nearer the centre
const float uMwWidth      = 0.10;  // [0.02, 0.6] bright band width
const float uMwFalloff    = 2.00;  // [0.5, 8]    cross-band falloff: 2 = gaussian, higher = flatter then sharper
const float uMwSpan       = 118.0; // [15, 180]   half-width of the arc, in degrees
const float uMwTaper      = 0.20;  // [0, 1]      how much thinner the bands get at the sides
const float uMwNoiseScale = 15.9;  // [0.5, 60]   size of the turbulence
const float uMwBright     = 0.45;  // [0, 4]      bright band brightness
const float uMwDust       = 4.00;  // [0, 12]     dark band extinction
const float uMwDustWidth  = 0.10;  // [0.01, 0.4] dark band width
const float uMwDustOffset = 0.02;  // [-0.15, 0.15] dark band offset from the midplane
const float uMwCore       = 2.78;  // [0, 4]      core brightness
const float uMwCoreSize   = 0.15;  // [0.05, 0.8] core angular size

// ===== SHARED MATHS =============================================================
#include "Space/MilkyWay/milkyway.inc.glsl"

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
	// Look straight at the core, with the band running across the view (preview only).
	vec3 pole = mwPole();
	vec3 up = abs(pole.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 ax = normalize(cross(pole, up));
	vec3 ay = cross(pole, ax);
	vec3 coreDir = normalize(cos(uMwCoreAngle) * ax + sin(uMwCoreAngle) * ay);

	mat3 view = lookAt(coreDir, pole);
	float fov = 90.0;
	vec3 dir = normalize(view * cameraRay(gl_FragCoord.xy, fov));
	float pxPerDir = 2.0 * tan(radians(fov * 0.5)) / u_resolution.y;

	vec3 transmittance;
	vec3 col = milkywaySky(dir, pxPerDir, transmittance);

	col = aces(col);
	gl_FragColor = vec4(pow(col, vec3(0.4545)), 1.0);
}
