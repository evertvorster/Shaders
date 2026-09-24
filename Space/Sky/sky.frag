// sky.frag — the sky compositor: an ordered STACK of layers, folded near -> far.
//
// This is the skeleton the rest of the sky slots into. It does not invent any content
// of its own; it declares the ORDER and the fold, and each layer keeps its own
// contract (emission + transmittance):
//
//     vec3 layerSky(..., out vec3 transmittance);
//
// ---------------------------------------------------------------- THE FOLD
// Compositing is front-to-back, nearest layer first:
//
//     col += T * emission;      // this layer's light, dimmed by everything in front
//     T   *= transmittance;     // ...and what is left for everything behind it
//
// so a layer's transmittance reaches the stars AND the background content behind it.
// When `T` reaches zero (an opaque foreground nebula) the fold STOPS -- the layers
// behind it are not merely invisible, they are never evaluated, which is where the
// performance comes from. Evert: "we'll dim the stars, and maybe totally get rid of the
// other objects if they are reasonably occluded."
//
// ---------------------------------------------------------------- THE ORDER
//   near  ->  local nebula (a volume: parallax)
//         ->  local starfield (dome)
//         ->  background content: Milky Way / galaxies / distant nebulae   <-- next
//   far
//
// Each layer has a fade knob, so a layer can be dialled in or out against the others.
// A faded-out layer contributes no emission AND no absorption (its T is pulled to 1),
// so it truly disappears rather than leaving a grey veil.
//
// ---------------------------------------------------------------- CONTRACT
//     vec3 skyColour(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance);
//
// Returns linear HDR emission plus the transmittance of the whole stack; tone mapping
// belongs to the host.
//
// ---------------------------------------------------------------- LICENCE
// GPL-3.0 (see LICENSE at the repository root).

#ifdef GL_ES
precision mediump float;
#endif
uniform vec2  u_resolution;
uniform float u_time;
uniform vec2  u_mouse;

// ===== PHYSICS ==================================================================
// The compositor has no physics of its own; the layers bring theirs via their includes.

// ===== VARIABLES ================================================================
// Fades, then every knob the included layers need (their names are namespaced per
// layer -- uStar*, uNeb* -- because a GLSL translation unit is flat).

const float uFadeNebula = 0.00;  // [0, 1]   weight of the local nebula layer (0 = OFF)
const float uFadeStars  = 1.00;  // [0, 1]   weight of the local starfield layer
const float uFadeMilkyway = 1.00;  // [0, 1]   weight of the Milky Way layer

// starfield knobs (Space/Starfield)
const float uStarDensity      = 60.0;  // [5, 400] field density: star count scales with its SQUARE
const float uStarCluster      = 0.00;  // [0, 1]   clumping; 0 = perfectly uniform field
const float uStarClusterScale = 4.00;  // [0.5, 20] clump size: lower = bigger clumps
const float uStarBright       = 1.00;  // [0, 4]   exposure
const float uStarGlow         = 1.00;  // [0, 3]   glare around the brightest stars
const float uStarCount        = 0.60;  // [0.05, 1] cell occupancy

// nebula knobs (Space/Nebula/gyroid-clouds)
const float uNebDensity    = 1.50;  // [0.1, 20]  overall gas density
const float uNebHaze       = 0.40;  // [0, 2]     soft haze filling the volume
const float uNebStructure  = 1.50;  // [0, 3]     filamentary cloud structure
const float uNebBright     = 1.00;  // [0, 8]     exposure
const float uNebSunAngle   = 2.00;  // [0, 6.28]  where the sun sits around us
const float uNebSunHeight  = 0.50;  // [-1, 1]    sun elevation
const float uNebLocalStars = 1.00;  // [0, 1]     stars embedded in the gas
const float uNebNoiseScale = 1.00;  // [0.05, 4]  size of the cloud detail
const float uNebSteps      = 16.0;  // [6, 64]    march steps: quality vs speed

// Milky Way knobs (Space/MilkyWay)
const float uMwPitch      = 0.00;  // [0, 3.14]   tilt of the galactic plane
const float uMwYaw        = 0.00;  // [0, 6.28]   yaw of the plane
const float uMwCoreAngle  = 0.00;  // [0, 6.28]   where the core sits along the band
const float uMwWidth      = 0.10;  // [0.02, 0.5] bright band thickness (at the centre)
const float uMwSpan       = 1.00;  // [0.3, 1.8]  how far the arc stretches along the sky
const float uMwTaper      = 0.60;  // [0, 1]      how much thinner the bands get at the sides
const float uMwNoiseScale = 2.50;  // [0.5, 8]    size of the turbulence
const float uMwBright     = 1.00;  // [0, 4]      bright band brightness
const float uMwDust       = 1.20;  // [0, 4]      dark band extinction
const float uMwDustWidth  = 0.055; // [0.01, 0.3] dark band thickness
const float uMwDustOffset = 0.02;  // [-0.15, 0.15] dark band offset from the midplane
const float uMwCore       = 1.50;  // [0, 4]      core brightness
const float uMwCoreSize   = 0.22;  // [0.05, 0.8] core angular size

// ===== SHARED MATHS =============================================================
// The layers themselves. Each include brings its constants, maths and contract; the
// include guards let them share lib/hash.glsl without colliding.

#include "Space/Starfield/starfield.inc.glsl"
#include "Space/Nebula/gyroid-clouds.inc.glsl"
#include "Space/MilkyWay/milkyway.inc.glsl"

// ===== THE FOLD =================================================================
vec3 skyColour(vec3 camPos, vec3 dir, float pxPerDir, out vec3 transmittance) {
	vec3 col = vec3(0.0);
	vec3 T   = vec3(1.0);

	// ---- nearest: the local nebula volume (emission AND absorption) ----
	// Guarded on the fade: at 0 the whole layer is skipped, so turning the clouds off
	// costs nothing at all rather than evaluating an invisible layer.
	if (uFadeNebula > 0.0) {
		vec3 Tl;
		vec3 e = nebulaSky(camPos, dir, pxPerDir, Tl);
		Tl = mix(vec3(1.0), Tl, uFadeNebula);
		col += T * e * uFadeNebula;
		T *= Tl;
	}
	if (T.r < 0.01 && T.g < 0.01 && T.b < 0.01) { transmittance = T; return col; }

	// ---- the local starfield dome ----
	{
		vec3 Tl;
		vec3 e = starfieldSky(dir, pxPerDir, Tl);
		Tl = mix(vec3(1.0), Tl, uFadeStars);
		col += T * e * uFadeStars;
		T *= Tl;
	}
	if (T.r < 0.01 && T.g < 0.01 && T.b < 0.01) { transmittance = T; return col; }

	// ---- farthest: background content ----
	// The Milky Way band is direction-only and sits behind everything above, so its own
	// dust cannot dim the local stars in front of it -- but it also cannot be dimmed by
	// them, and the fold is the same one line.
	if (uFadeMilkyway > 0.0) {
		vec3 Tl;
		vec3 e = milkywaySky(dir, pxPerDir, Tl);
		Tl = mix(vec3(1.0), Tl, uFadeMilkyway);
		col += T * e * uFadeMilkyway;
		T *= Tl;
	}

	transmittance = T;
	return col;
}

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
	// Look along the band at the core, so it stretches across the view (preview only).
	vec3 camPos = vec3(0.0);
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
	vec3 col = skyColour(camPos, dir, pxPerDir, transmittance);

	col = aces(col);
	gl_FragColor = vec4(pow(col, vec3(0.4545)), 1.0);
}
