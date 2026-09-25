// volumetric_starfield.inc.glsl — a starfield you can FLY THROUGH.
//
// `Space/Starfield` is a DOME: every star sits on the celestial sphere at radius=cells, so it
// never moves relative to the viewer. That is correct for distant stars (their parallax is
// unmeasurable) but it means flying gives no sense of travel at all.
//
// This layer is a VOLUME: stars sit on a world-anchored lattice around the viewer, so passing
// them produces real parallax and near ones sweep by quickly.
//
// It is deliberately LOCAL -- the march stops at uStvView. Beyond that the dome takes over.
// That split is not just cheap, it is necessary: a star is a point source, so its ANGULAR size
// is constant, which means the cylinder a single pixel sweeps out has radius
// (angular size x distance) and GROWS without limit. Past some range that cylinder is wider
// than a cell, and any one-cell-per-step test starts missing stars that are near the ray but
// in a neighbouring cell. Bounded, that cannot happen, and distant stars are the dome's job
// anyway -- where parallax is genuinely negligible.
//
// Contract (same shape as the nebula layers):
//     vec3 volumetricStarfieldSky(vec3 camPos, vec3 dir, float pxPerDir, float dither, out vec3 transmittance);
// Stars absorb nothing, so transmittance is always 1 -- exactly like the dome.
//
// GPL-3.0 (see LICENSE at the repository root).

#ifndef VOLUMETRIC_STARFIELD_GLSLINC
#define VOLUMETRIC_STARFIELD_GLSLINC

#include "lib/hash.glsl"
#include "lib/noise.glsl"
#include "lib/raymarch.glsl"

#define STV_MAX_STEPS 640   // hard cap on the march

// Star colour: hotter (bluer) for the bright ones, cooler for the dim, which is the usual
// cheap approximation of spectral type.
vec3 starTint(float m) {
	return mix(vec3(1.00, 0.82, 0.66), vec3(0.78, 0.86, 1.00), clamp(m, 0.0, 1.0));
}

vec3 volumetricStarfieldSky(vec3 camPos, vec3 dir, float pxPerDir, float dither, out vec3 transmittance) {
	vec3 d = normalize(dir);
	transmittance = vec3(1.0);            // stars do not absorb

	// Step at HALF a cell so the ray cannot stride over a whole cell, and evaluate a cell only
	// when the ray ENTERS it (tracked via `lastCell`). That dedup is what stops a star being
	// counted once per step. A 3D DDA would be exact; this is the cheap version, and at
	// half-cell steps the only cells it can miss are the ones clipped at a corner.
	float dt = max(uStvCell, 1e-4) * 0.5;
	int steps = min(int(uStvView / dt) + 1, STV_MAX_STEPS);

	vec3 col = vec3(0.0);
	vec3 lastCell = vec3(-1e9);            // guaranteed != the first cell

	for (int i = 0; i < STV_MAX_STEPS; i++) {
		if (i >= steps) break;
		float t = (float(i) + dither) * dt;
		vec3 p = camPos + d * t;

		vec3 c = floor(p / uStvCell);
		if (c == lastCell) continue;
		lastCell = c;

		vec3 r = hash33(c + uStvSeed);
		if (r.x > uStvDensity) continue;    // this cell holds no star
		float mag = r.y;

		// The position MUST come from an independent hash. It used to reuse r.x, which is also
		// the occupancy test, so occupancy (r.x <= density) clamped the star's z offset: at
		// density 0.5 the z offset could only ever land in [0.15, 0.50]. Every occupied cell was
		// therefore empty in its upper z half -- periodic empty slabs, which read as straight
		// layers of sky with no stars. Measured offline: mean z offset 0.324, not 0.500.
		vec3 r2 = hash33(c + uStvSeed + 13.71);

		// The star must sit far enough inside its cell that the ray always visits that cell:
		// a pixel's capture cylinder has radius (uStvAng * distance) at the far end of the
		// volume, and a star closer to the wall than that could be within catching distance
		// while the ray never enters the star's own cell -- so it would be missed. DERIVING the
		// margin keeps that empty shell as thin as the geometry allows; a fixed generous margin
		// leaves periodic empty slabs, which is the artefact we just removed.
		float margin = clamp(uStvAng * uStvView / max(uStvCell, 1e-4), 0.02, 0.45);
		vec3 P = (c + margin + (1.0 - 2.0 * margin) * r2) * uStvCell;

		vec3 rel = P - camPos;
		float along = dot(rel, d);
		if (along <= 0.0) continue;         // behind us

		float dperp = length(rel - along * d);
		float ang = dperp / along;          // angular offset from this pixel's ray

		float rr = uStvAng * (0.95 + 0.45 * mag);                    // constant ANGULAR radius

		if (ang >= rr) continue;

		// Sub-pixel stars fade rather than being lost or fattened, so the field stays
		// resolution-independent -- the same rule as the dome.
		float radPx = rr / max(pxPerDir, 1e-9);
		float cover = clamp(radPx, 0.0, 1.0);

		// Disc falloff, then inverse-square: flying towards a star makes it brighter.
		float q = 1.0 - ang / rr;
		float flux = q * q * cover * cover / (1.0 + along * along * uStvFalloff);

		col += uStvBright * (0.30 + 0.70 * mag) * flux * starTint(mag);
	}

	return col;
}

#endif  // VOLUMETRIC_STARFIELD_GLSLINC
