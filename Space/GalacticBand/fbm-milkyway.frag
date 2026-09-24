// fbm-milkyway.frag — the Milky Way band, seen from the side of one of its arms.
//
// A direction-only background layer: no parallax, it is painted on the celestial sphere.
// The maths, the contract and the knobs live in fbm-milkyway.inc.glsl (below), so the
// sky compositor can include the identical code.
//
//     vec3 galacticBandSky(vec3 dir, float pxPerDir, out vec3 transmittance);
//
// Emission plus chromatic transmittance (the dust reddens what is behind it). Compose it
// beneath the local starfield.
//
// GPL-3.0 (see LICENSE at the repository root).

#ifdef GL_ES
precision mediump float;
#endif
uniform vec2  u_resolution;
uniform float u_time;
uniform vec2  u_mouse;

// ===== PHYSICS ==================================================================
// Constants and maths live in fbm-milkyway.inc.glsl (below). Nothing to see here.

// ===== VARIABLES ================================================================
// The knobs. Each annotated `[min, max]`; the builder promotes them to uniforms in the
// generated hosts.

const float uGalPitch       = 1.00;   // [0, 3.14]   band tilt
const float uGalYaw         = 0.50;   // [0, 6.28]   band orientation around the sky
const float uGalCoreAngle   = 0.00;   // [0, 6.28]   where the bright core sits along the band
const float uGalWidth       = 0.14;   // [0.02, 0.4] band thickness
const float uGalCoreSize    = 0.15;   // [0.05, 1]   angular size of the core bulge
const float uGalCore        = 0.90;   // [0, 4]      core bulge brightness
const float uGalBand        = 0.70;   // [0, 4]      band brightness
const float uGalStarClouds  = 0.50;   // [0, 4]      unresolved star clouds
const float uGalNoiseScale  = 7.00;   // [0.5, 16]   size of the cloud texture
const float uGalRiftOffset  = 0.03;   // [-0.2, 0.2] dust rift offset from the midplane
const float uGalRiftWidth   = 0.04;   // [0.01, 0.3] dust rift width
const float uGalDust        = 1.20;   // [0, 3]      dust extinction
const float uGalBright      = 0.80;   // [0, 4]      exposure

// ===== SHARED MATHS =============================================================
// The band's maths and contract, shared with the compositor. Inlined by the builder.
#include "Space/GalacticBand/fbm-milkyway.inc.glsl"

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
	// Look straight at the galactic core: the band and its bulge fill the view.
	vec3 coreDir;
	mwGalacticFrame(coreDir);
	vec3 camPos = vec3(0.0);
	mat3 view = lookAt(coreDir, vec3(0.0, 1.0, 0.0));
	float fov = 70.0;
	vec3 dir = normalize(view * cameraRay(gl_FragCoord.xy, fov));
	float pxPerDir = 2.0 * tan(radians(fov * 0.5)) / u_resolution.y;

	vec3 transmittance;
	vec3 col = galacticBandSky(dir, pxPerDir, transmittance);

	col = aces(col);
	gl_FragColor = vec4(pow(col, vec3(0.4545)), 1.0);
}
