// nebula-and-stars.frag — a SCENE: the filamentary nebula in front of the fly-through
// star volume.
//
// The two layers do NOT interact. The stars do not light the gas, and the gas does not
// scatter starlight. What they share is OCCLUSION -- the nebula's transmittance dims the
// stars behind it, so flying into dust hides them. That is the entire composition:
//
//     vec3 Tn; vec3 neb   = nebulaSky(camPos, dir, pxPerDir, dither, Tn);
//     vec3 Ts; vec3 stars = volumetricStarfieldSky(camPos, dir, pxPerDir, dither, Ts);
//     vec3 col = neb + Tn * stars;               // Tn is the dust
//
// GPL-3.0 (see LICENSE at the repository root).

#ifdef GL_ES
precision mediump float;
#endif
uniform vec2  u_resolution;
uniform float u_time;
uniform vec2  u_mouse;

// ===== PHYSICS ==================================================================
// A scene owns no physics of its own: each layer brings its own from its .inc.glsl --
// ridged-clouds supplies the gas, volumetric_starfield the stars. This marker exists
// because the builders split the source on it.

// ===== VARIABLES ================================================================
// These knobs are REPEATED from Space/Nebula/ridged-clouds.frag and
// Space/volumetric_starfield/volumetric_starfield.frag, because the builders read knob
// declarations out of the .frag's VARIABLES section. Repeating them is exactly how they
// would silently drift, so Tools/build_scenes.py checks that this file declares every
// knob both layer sources declare, and FAILS THE BUILD if one has been added or renamed
// in a layer and not carried here.
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


// scene knob, not a layer knob
const float uStars    = 1.0;   // [0, 1] fade the star volume; 0 branches it off entirely, so it is free
// ===== VARIABLES ================================================================
const float uStvCell    = 3.0;      // [1, 50]    cell size in world units: bigger = fewer, further apart
const float uStvDensity = 0.03;     // [0, 1]     fraction of cells that hold a star
const float uStvView    = 100.0;    // [10, 500]  how far the local volume reaches
const float uStvAng     = 0.0026;   // [0.0002, 0.006] star angular radius (direction units)
const float uStvBright  = 3.08;      // [0, 6]     exposure
const float uStvFalloff = 0.0028;   // [0.0001, 0.05] inverse-square scale: bigger = stars dim faster with distance
const float uStvSeed    = 0.0;      // [0, 100]   lattice seed


// ===== SHARED MATHS =============================================================
#include "Space/Nebula/ridged-clouds.inc.glsl"
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
	// Fly forward through the gas and the star lattice.
	float fov = 70.0;
	vec3 camPos = vec3(0.0, 0.0, -u_time * 6.0);
	vec3 dir = cameraRay(gl_FragCoord.xy, fov);
	float pxPerDir = 2.0 * tan(radians(fov * 0.5)) / u_resolution.y;
	float dither = ign(gl_FragCoord.xy);

	vec3 Tn; vec3 neb   = nebulaSky(camPos, dir, pxPerDir, dither, Tn);
	vec3 Ts; vec3 stars = volumetricStarfieldSky(camPos, dir, pxPerDir, dither, Ts);

	// Stars first (behind), then the nebula in front dimming them by its transmittance.
	vec3 col = neb + Tn * uStars * stars;

	col = aces(col);
	gl_FragColor = vec4(pow(col, vec3(0.4545)), 1.0);
}
