// gyroid-clouds.frag — volumetric emission nebula: gyroid-fbm clouds in a world-space
// volume (canonical source; also the glslviewer build).
//
// Ported from al-ro's "Volumetric nebula rendered in tiles" (Shadertoy DtdSz7, MIT,
// 2023), reduced to a single pass and adapted to this repo's layer contract. The
// original's multi-buffer camera state and progressive tile rendering are host work
// and are dropped here; only the volume, its density and its lighting remain.
//
// ---------------------------------------------------------------- THE MODEL
// We are INSIDE a finite cube of gas (half-size VOLUME_EXTENT). Along each view ray we
// march front-to-back, accumulating emitted light and attenuating what is behind us:
//
//   density  : a gyroid-based fbm -- self-similar filaments and voids, which is what
//              nebula gas actually looks like. Shaped into a haze shell and a
//              structure shell so the centre around us stays relatively clear.
//   lighting : sunlight scattered once, via Henyey-Greenstein phase, plus Beers-Law
//              transmittance accumulated along a short secondary ray to the sun.
//              Lit by the sun only -- the stars are the compositor's business.
//
// Because the ray origin is a real position, the volume has PARALLAX: move and the
// clouds shift against the distant stars. The output is linear HDR emission; tone
// mapping belongs to the compositor/host, not to the layer.
//
// ---------------------------------------------------------------- THE CONTRACT
//     vec3 nebulaSky(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance);
//
// Emission + transmittance, per channel (dust and gas absorb unevenly). The starfield
// dome is behind; composing is one fold:
//
//     vec3 T;
//     vec3 col = nebulaSky(camPos, dir, ppd, T);
//     col += starfieldSky(dir, ppd, T);
//
// ---------------------------------------------------------------- LICENCE
// GPL-3.0 (see LICENSE at the repository root). Upstream technique MIT (c) 2023 al-ro.

#ifdef GL_ES
precision mediump float;
#endif
uniform vec2  u_resolution;
uniform float u_time;
uniform vec2  u_mouse;

// ===== PHYSICS ==================================================================
// This variant's constants, shared maths and contract live in gyroid-clouds.glslinc
// (below), so the sky compositor can include the identical code. Nothing to see here.

// ===== VARIABLES ================================================================
// The knobs. Each annotated `[min, max]`; the builder promotes them to uniforms in
// the generated hosts. They are `const` here because glslviewer cannot set uniforms.
const float uNebDensity    = 0.60;  // [0.1, 20]  overall gas density
const float uNebHaze       = 0.40;  // [0, 2]     soft haze filling the volume
const float uNebStructure  = 1.50;  // [0, 3]     filamentary cloud structure
const vec3 uNebGlowColour   = vec3(1.00, 1.00, 1.00);  // the gas's own glow (scales scattering)
const vec3 uNebAbsorbColour = vec3(1.00, 1.00, 1.00);  // what the gas absorbs (extinction tint)
const vec3 uNebSunColour    = vec3(1.00, 1.00, 1.00);  // the sun's colour
const float uNebBright     = 1.00;  // [0, 8]     exposure
const float uNebSunAngle   = 2.00;  // [0, 6.28]  where the sun sits around us
const float uNebSunHeight  = 0.50;  // [-1, 1]    sun elevation
const float uNebNoiseScale = 0.44;  // [0.05, 4]  size of the cloud detail
const float uNebVoid       = 0.12;  // [0.02, 0.45] void threshold: higher = sparser clouds
const float uNebView       = 26.0;  // [10, 400]  how far a view ray marches (visible depth)
const float uNebSteps      = 24.0;  // [6, 64]    march steps: quality vs speed
const float uNebDither     = 1.00;  // [0, 1]     per-pixel jitter of the first step (0 = off)

// ===== SHARED MATHS ===========================================================
#include "Space/Nebula/gyroid-clouds.inc.glsl"

// ===== HOST (glslviewer) ========================================================
// Everything from this marker down is host plumbing and is REPLACED by the builder.
// The marker line itself (`// ===== HOST`) is what the builder splits on.

vec3 cameraRay(vec2 fragCoord, float fovDeg) {
	vec2 xy = fragCoord - u_resolution.xy * 0.5;
	float z = (0.5 * u_resolution.y) / tan(radians(fovDeg) * 0.5);
	return normalize(vec3(xy, -z));
}

// ACES filmic tone map (Krzysztof Narkowicz). Host-side: the layer returns linear HDR.
vec3 aces(vec3 x) {
	return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

void main() {
	// Fixed camera just off the volume centre, looking outward, so the cavity wall of
	// clouds fills the view. Static, so a preview is reproducible frame to frame.
	vec3 camPos = vec3(0.40, 0.15, 0.0);
	vec3 targetDir = normalize(camPos);
	mat3 view = lookAt(targetDir, vec3(0.0, 1.0, 0.0));
	float fov = 55.0;
	vec3 dir = normalize(view * cameraRay(gl_FragCoord.xy, fov));
	float pxPerDir = 2.0 * tan(radians(fov * 0.5)) / u_resolution.y;

	// Dither the first step per pixel: without it, flying forward slides the sampling
	// lattice through the gas and the banding flickers.
	float dither = ign(gl_FragCoord.xy);
	vec3 transmittance;
	vec3 col = nebulaSky(camPos, dir, pxPerDir, dither, transmittance);

	col = aces(col);
	gl_FragColor = vec4(pow(col, vec3(0.4545)), 1.0);
}
