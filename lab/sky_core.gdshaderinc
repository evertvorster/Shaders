// sky_core.gdshaderinc — shared procedural sky (one source of truth).
//
// Used by BOTH:
//   sky.gdshader       (shader_type sky)      -> interactive authoring/preview
//   bake_sky.gdshader  (shader_type canvas_item) -> 6-face cube bake
//
// Model (Evert's framing): we are INSIDE the galaxy. So:
//   1. galactic band + far star layer      (bright toward the galactic centre)
//   2. dust/nebula cloud                   (emission + it SWALLOWS the far stars)
//   3. near stars drawn on TOP of the dust (they are closer than the cloud)
// Everything is a pure function of a direction, so it renders identically from a
// sky shader and from the explicit cube-face directions used when baking.

// ---- galactic frame -------------------------------------------------------
uniform vec3 uPoleDir = vec3(0.35, 0.72, 0.60);   // galactic pole
uniform vec3 uCenterDir = vec3(0.86, -0.20, -0.47); // galactic centre
uniform float uBandWidth : hint_range(0.25, 3.0) = 1.0;   // multiplier on the measured profile
uniform float uBandIntensity : hint_range(0.0, 2.0) = 0.8;
uniform float uBandAsym : hint_range(0.0, 1.0) = 0.75;
uniform vec3 uBandColor : source_color = vec3(0.72, 0.74, 0.85);
// longitudinal bulge (galactic centre), measured from the ESO panorama
uniform float uBulgeWidth : hint_range(5.0, 90.0) = 28.0;   // degrees
uniform float uBulgePow : hint_range(0.5, 4.0) = 1.2;
uniform float uBulgeFloor : hint_range(0.0, 0.6) = 0.22;
// cloud / rift structure inside the band
uniform float uBandStructScale : hint_range(1.0, 40.0) = 9.0;
uniform float uRiftStrength : hint_range(0.0, 1.0) = 0.7;

// ---- stars ---------------------------------------------------------------
uniform float uStarDensity : hint_range(0.0, 2.0) = 0.55;
uniform float uStarSize : hint_range(0.2, 4.0) = 1.0;
uniform float uStarBright : hint_range(0.0, 3.0) = 1.1;
uniform float uNearStars : hint_range(0.0, 2.0) = 0.35;
uniform float uStarThreshold : hint_range(0.0, 1.0) = 0.55;

// The POV-Ray recipes build a star field as a COMPOSITION of size classes (tiny
// many -> big few), not one uniform field, and they CLUSTER: `distribu_angle`
// 180 spreads over the sphere, 2 collimates into tight clusters, and
// `excentricity` stretches them. See recipes/starfield.md.
uniform float uStarClassMix : hint_range(0.0, 1.0) = 0.5;   // small<->big balance
uniform float uClusterScale : hint_range(0.5, 20.0) = 3.0;   // broad cluster size
uniform float uClusterStrength : hint_range(0.0, 1.0) = 0.55;
uniform float uTightClusterScale : hint_range(2.0, 40.0) = 12.0;
uniform float uTightClusterAmount : hint_range(0.0, 1.0) = 0.35;

// ---- dust / nebula -------------------------------------------------------
uniform vec3 uNebulaColorA : source_color = vec3(0.85, 0.42, 0.16); // warm dust
uniform vec3 uNebulaColorB : source_color = vec3(0.16, 0.42, 0.55); // cool gas
uniform float uNebulaAmount : hint_range(0.0, 2.0) = 0.25;
uniform float uNebulaScale : hint_range(0.5, 40.0) = 4.0;
uniform float uNebulaThreshold : hint_range(0.0, 1.0) = 0.45;
uniform float uDustExtinction : hint_range(0.0, 1.0) = 0.85;
uniform float uSeed : hint_range(0.0, 100.0) = 0.0;

// ---- nebula structure ----------------------------------------------------
// Real nebulae (and the shipped art) are FILAMENTARY: thin strands and sharp
// sheets with big dark voids — not round blobs. A ridged field on a
// domain-warped fbm gives that; the void mask carves out the large dark areas.
uniform float uWarp : hint_range(0.0, 4.0) = 1.0;          // domain warp amount
uniform float uFilamentSharp : hint_range(0.5, 8.0) = 2.5;  // higher = thinner strands
uniform float uVoidScale : hint_range(0.3, 10.0) = 1.1;     // large-scale voids
uniform float uVoidThreshold : hint_range(0.0, 0.9) = 0.35;

// ---- volumetric nebula ----------------------------------------------------
// The POV-Ray cloud nebulae (mCloudNebula07 etc.) are NOT surfaces: they are
// spheres of PARTICIPATING MEDIA -- scattering (emission ~ density) plus
// extinction -- with a granite/turbulence density field, and the camera sits
// INSIDE them. That is physically why their dust swallows the stars behind it.
// So we march the view ray through the cloud, accumulating emission and
// transmittance, and dim the stars by the result. This is affordable because we
// bake OFFLINE: a per-pixel raymarch is a one-time cost, not a per-frame one.
uniform float uVolAmount : hint_range(0.0, 6.0) = 0.0;      // scattering scale
uniform float uVolExtinction : hint_range(0.0, 4.0) = 1.0;  // attenuation scale
// Emission is SEPARATE from extinction in the source (its own `emission` term), and
// that matters: the 06-family nebulae glow without occluding. 0 keeps the old
// coupled behaviour; >0 adds light without attenuating.
uniform float uVolEmission : hint_range(0.0, 4.0) = 0.0;
uniform float uVolScale : hint_range(0.5, 20.0) = 3.0;      // density feature size
uniform float uVolThreshold : hint_range(0.0, 1.0) = 0.55;  // granite threshold
uniform float uVolContrast : hint_range(0.02, 1.0) = 0.22;  // edge softness
uniform float uVolEnvInner : hint_range(0.0, 1.0) = 0.15;   // cavity around the viewer
uniform float uVolEnvOuter : hint_range(0.0, 1.0) = 1.0;    // fade at the far edge
uniform float uVolColorPow : hint_range(0.5, 6.0) = 2.2;    // density->colour ramp
uniform float uVolFine : hint_range(0.0, 1.0) = 0.55;       // fine filamentary texture
uniform float uVolRidge : hint_range(0.0, 1.0) = 0.7;       // 0 = cumulus blobs, 1 = lace filaments
// mCloudNebula06 (which scene 37 uses) evaluates its density on ABSOLUTE
// coordinates, so the cloud is mirror-symmetric across all three planes. That is
// what produces the "pinwheel"/kaleidoscope look of that background -- it is a
// symmetry effect, not a spiral artefact.
uniform float uVolOctant : hint_range(0.0, 1.0) = 0.0;      // 1 = mirror in x/y/z
// ...but applied to a REGION of the sky, not the whole face: in the reference the
// mirrored pinwheel occupies part of the view and the rest is ordinary cloud.
// Applying it everywhere produces a geometric kaleidoscope, which is wrong.
uniform float uVolSymScale : hint_range(0.5, 20.0) = 2.2;   // size of the symmetric patch
uniform float uVolSymAmount : hint_range(0.0, 1.0) = 0.4;   // how much of the sky is symmetric
// ...and its base pattern is `spiral1 4` selecting between cellular / banded /
// bump sub-patterns, each domain-warped. Approximated here.
uniform float uVolSpiral : hint_range(0.0, 8.0) = 0.0;      // spiral arms (0 = off)
uniform float uVolSpiralMix : hint_range(0.0, 1.0) = 0.5;  // how much it drives density
// Colour mode: the 07 family colours its density by a two-tone field (see
// uVolTone*); the 06 family uses a FIXED multi-stop emission spectrum keyed by
// density. 0 = two-tone field, 1 = emission spectrum.
uniform float uVolSpectrum : hint_range(0.0, 1.0) = 0.0;
uniform float uVolSpectrumPhase : hint_range(0.0, 1.0) = 0.5088;  // the ACTUAL source phase
// The source feeds its density_map a pigment value spanning 0..1. Our density has
// a different span, so the map's bands get crossed far too often (colour contours).
// This rescales the density BEFORE the map lookup -- a real setting, not a fudge.
uniform float uVolSpectrumScale : hint_range(0.1, 4.0) = 1.0;
uniform float uVolBandGap : hint_range(0.0, 0.45) = 0.18;      // dark gap between colour bands
// Number of colour bands across the density range. The source has 6 (its element
// stops), which reads as THICK bands; more bands = thinner stripes. This is an
// aesthetic dial, not a fidelity one.
uniform float uVolBands : hint_range(2.0, 8.0) = 4.0;
// REGIONAL colour. The shipped art shows large areas clearly one hue and large
// areas clearly another. Colour driven by density (or by a smooth ramp) can never
// do that -- it needs its own low-frequency QUANTISED field: the region picks the
// hue, the density only sets brightness.
uniform float uVolPattern : hint_range(0.0, 1.0) = 0.0;      // 1 = source-faithful signal path
// The nebula density in the source is a COLOUR, and POV-Ray multiplies that colour
// by the scattering/emission colour (see docs: "This resulting color is multiplied
// by the absorption, emission and scattering color"). So each RGB channel has its
// OWN density -- its own spatial structure -- which is why the colours BELONG to
// the cloud. A scalar density plus a separately-evaluated colour can only ever
// look painted on. 1 = per-channel coloured density (source-faithful).
uniform float uVolRGB : hint_range(0.0, 1.0) = 0.0;
// A real cloud nebula shows SEVERAL hues -- red/magenta, blue, purple where they
// meet, green -- not two. (Evert: the shipped starfield2 "looks very much like the
// colorized version of the horsehead nebula".) A two-colour tone field cannot do
// that. Four stops, driven by a low-frequency field.
uniform vec3 uPal0 : source_color = vec3(0.78, 0.12, 0.10);  // DEEP RED (low blue! a
                                                              // high blue here reads as pink)
uniform vec3 uPal1 : source_color = vec3(0.45, 0.10, 0.55);  // purple  (FRINGE only)
uniform vec3 uPal2 : source_color = vec3(0.08, 0.18, 0.42);  // deep blue
uniform vec3 uPal3 : source_color = vec3(0.40, 0.48, 0.14);  // YELLOW-GREEN / olive
                                                              // (the shipped greens lean
                                                              //  yellow, not blue-green)
// Evert: "the purple is a bit much, it was sort of fringing on the clouds". So purple
// is not a broad region -- it is a narrow band at the boundary between the first
// and second colours, which is what a red/blue interface physically looks like.
uniform float uPalPurpleW : hint_range(0.002, 0.2) = 0.03;
// "areas that were much brighter lit cloud than the surrounding" -- a highlight
// control. ADDITIVE, not a power: a power on a value < 1 just darkens everything.
uniform float uVolGain : hint_range(0.0, 4.0) = 0.0;
uniform float uVolPalScale : hint_range(0.2, 6.0) = 1.1;
// Some directions are bare apart from a very slight, almost uniform dust cloud;
// others are rich. This is the faint floor, and a stronger mass gate does the rest.
uniform float uVolHaze : hint_range(0.0, 0.5) = 0.05;
// KALISET (kaleidoscopic IFS). Evert found the "Simplicity Galaxy" shader
// (shadertoy MslGWN lineage, Jared Berghold 2022), whose nebula shape comes from a
// kaliset inversion fractal: p = abs(p)/dot(p,p) + c. Unlike fbm -- which can only
// make blobby/mottled clouds -- this yields SELF-SIMILAR FILAMENTS, sheets and
// voids, which is what real nebulae (and the shipped art) look like. It is also
// cheap: ~18 iterations, no octave stack.
uniform float uVolKali : hint_range(0.0, 1.0) = 0.0;      // blend kaliset into the density
uniform float uVolKaliIter : hint_range(4.0, 18.0) = 14.0;
uniform float uVolKaliScale : hint_range(0.2, 6.0) = 1.5;
// How hard the kaliset drives the density, and how much it is allowed to bypass the
// fbm mass gate. "Kaliset needs to be stronger": at 1.0 the kaliset replaces the
// density but was still being gated/damped by fbm fields, which masked its shape.
uniform float uVolKaliStrength : hint_range(0.2, 4.0) = 1.0;
// POV-Ray's crackle/marble/bumps each span the full 0..1, so the pattern sweeps
// its colour map. Our fbm-based stand-ins have a NARROW distribution, so the
// signal must be stretched or it never leaves the middle of the map (which is why
// everything came out one orange/brown). Not a fudge: it is compensating for our
// noise having a smaller range than POV-Ray's patterns.
uniform float uSigBias : hint_range(0.0, 0.8) = 0.35;
uniform float uSigScale : hint_range(0.5, 6.0) = 2.2;
uniform float uVolRegion : hint_range(0.0, 1.0) = 0.0;        // 1 = region-based hue
uniform float uVolRegionScale : hint_range(0.3, 10.0) = 0.9;  // region size (low = FAT areas)
uniform float uVolRegions : hint_range(2.0, 6.0) = 2.0;       // how many colour regions
uniform float uVolRegionSharp : hint_range(0.02, 1.0) = 0.15;  // boundary hardness
// The source's density is COLOURED: `spotted scale 3` mapped c0 -> c1 -> c0, then
// multiplied into the scattering base density. So the two palette colours are
// INTERLEAVED AS PATCHES by a small-scale pattern -- that is what makes the
// nebula obviously two-tone, and no smooth density->colour gradient can do it.
uniform float uVolToneScale : hint_range(0.5, 20.0) = 3.0;  // two-tone patch size
uniform float uVolToneSharp : hint_range(0.0, 1.0) = 0.45;  // patch edge
// The source's form uses `spherical scale 6 poly_wave 2`: concentric SHELLS.
// 0 disables; higher = more shells.
uniform float uVolShell : hint_range(0.0, 8.0) = 2.0;

uniform float uExposure : hint_range(0.0, 4.0) = 1.15;

// ---- contrast shaping ----------------------------------------------------
// Matching the mean alone gives a flat grey haze. The reference art also has a
// wide histogram: e.g. `green` = mean 0.094, sd 0.076 (sd/mean 0.81), ~28% of
// pixels near-black and ~1.7% bright. These knobs push the other two ends.
uniform float uGamma : hint_range(0.4, 3.0) = 1.0;        // spreads the histogram
uniform float uDarkLanes : hint_range(0.0, 1.0) = 0.0;     // deepen dust lanes
uniform float uKnotScale : hint_range(2.0, 40.0) = 12.0;
uniform float uKnotThreshold : hint_range(0.30, 0.95) = 0.62;
uniform float uKnotAmount : hint_range(0.0, 2.0) = 0.0;   // bright star-forming cores
uniform float uKnotGlow : hint_range(0.0, 3.0) = 1.2;     // wide halo -> lit dust cloud
uniform vec3 uKnotColor : source_color = vec3(0.95, 0.95, 1.0);
uniform vec3 uKnotEdgeColor : source_color = vec3(0.42, 0.27, 0.15);  // lit dust, cool edge

// A handful of nearby PROMINENT stars: the shipped art has a few big foreground
// stars with a halo, not only a dense faint field.
uniform float uBrightStarDensity : hint_range(0.0, 1.0) = 0.30;
uniform float uBrightStarSize : hint_range(1.0, 10.0) = 6.0;
uniform float uBrightStarBright : hint_range(0.0, 3.0) = 1.5;
uniform float uBrightStarHalo : hint_range(0.0, 3.0) = 1.5;   // wide soft halo
uniform vec3 uBrightStarColor : source_color = vec3(1.0, 0.92, 0.78);

// Angular size of one screen pixel, in direction units (a direction component
// spans -1..1 across one cube face). The baker sets it from its face resolution
// (2/res). Using fwidth() instead is NOT reliable -- derivatives differ between
// a sky/spatial pass and the canvas_item bake pass, so the lab and the bake
// would disagree.
uniform float uPxPerDir : hint_range(0.00005, 0.02) = 0.0013;

// Star ANGULAR radius, in the same direction units -- a fixed angular size, like
// real stars and like the POV-Ray sources (which place finite-size objects at a
// fixed distance). This is what makes star DENSITY resolution-independent: a
// fixed pixel size instead makes the sky thinner and thinner as resolution
// rises, because the same stars cover a smaller fraction of more pixels. Floored
// at one pixel so stars stay visible at low resolution.
uniform float uStarAngSize : hint_range(0.00005, 0.01) = 0.0007;

// ---- cube face direction (DDS/GL cubemap spec) ---------------------------
// Faces in order +X, -X, +Y, -Y, +Z, -Z. From the spec, with s = u (left to
// right) and t = v (top to bottom):
//   +X: sc=-z, tc=-y | -X: sc= z, tc=-y | +Y: sc= x, tc= z
//   -Y: sc= x, tc=-z | +Z: sc= x, tc=-y | -Z: sc=-x, tc=-y
// Inverted (major axis = +-1):
//   +X (1, 1-2v, 1-2u)   -X (-1, 1-2v, 2u-1)   +Y (2u-1,  1, 2v-1)
//   -Y (2u-1, -1, 1-2v)  +Z (2u-1, 1-2v,  1)   -Z (1-2u, 1-2v, -1)
// NOTE: a sign error here yields a ROTATED/MIRRORED face, which the
// face-centre self-test cannot see -- the test must check CORNERS too.
vec3 face_dir(int f, float u, float v) {
	if (f == 0) {        // +X
		return vec3( 1.0, 1.0 - 2.0 * v, 1.0 - 2.0 * u);
	} else if (f == 1) { // -X
		return vec3(-1.0, 1.0 - 2.0 * v, 2.0 * u - 1.0);
	} else if (f == 2) { // +Y
		return vec3(2.0 * u - 1.0,  1.0, 2.0 * v - 1.0);
	} else if (f == 3) { // -Y
		return vec3(2.0 * u - 1.0, -1.0, 1.0 - 2.0 * v);
	} else if (f == 4) { // +Z
		return vec3(2.0 * u - 1.0, 1.0 - 2.0 * v,  1.0);
	}
	return vec3(1.0 - 2.0 * u, 1.0 - 2.0 * v, -1.0); // -Z
}

// ---- noise ---------------------------------------------------------------
float hash13(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = 0.0;
	for (int z = 0; z < 2; z++) {
		for (int y = 0; y < 2; y++) {
			for (int x = 0; x < 2; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				float h = hash13(i + o + uSeed);
				n += h * (mix(1.0 - f.x, f.x, o.x)
						* mix(1.0 - f.y, f.y, o.y)
						* mix(1.0 - f.z, f.z, o.z));
			}
		}
	}
	return n;
}

float fbm(vec3 p) {
	float a = 0.5, s = 0.0, t = 0.0;
	for (int i = 0; i < 6; i++) {
		s += a * vnoise(p);
		t += a;
		p *= 2.03;
		a *= 0.5;
	}
	return s / t;
}

// Cheap 3-octave variant -- the volumetric march calls this dozens of times per
// pixel, so octaves matter more than detail here.
float fbm3(vec3 p) {
	float a = 0.5, s = 0.0, t = 0.0;
	for (int i = 0; i < 3; i++) {
		s += a * vnoise(p);
		t += a;
		p *= 2.03;
		a *= 0.5;
	}
	return s / t;
}

// ---- volumetric nebula ----------------------------------------------------
// p is in cloud units: the ray parameter t runs 0 (viewer, inside the cloud) to
// 1 (the cloud's outer edge).
const int VOL_STEPS = 96;   // must be enough to resolve the finest density feature:
                            // at ~2 steps per feature the march averages the lace away

// POV-Ray `spiral1 N` approximated: N arms unwinding with radius.
float volSpiralValue(vec3 p) {
	float ang = atan(p.z, p.x) / 6.2831853;
	float r = length(p.xz) + p.y * 0.5;
	return fract((ang + r) * max(uVolSpiral, 1e-4));
}

// The 06 family's emission spectrum. Crucially the source cuts random ZERO-width
// bands between the element stops, so the colours read as SEPARATE REGIONS with
// dark gaps between them -- not one blended hue. That separation is most of the
// character; a smooth gradient across the stops loses it.
// The source's smooth element ramp -- used to LOOK UP the colour for each band.
vec3 spectrumColour(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 C0 = vec3(1.0,    0.4518, 0.1368);  // Carbon   orange
	vec3 C1 = vec3(1.0,    0.4594, 0.5463);  // Helium   pink
	vec3 C2 = vec3(1.0,    0.2313, 0.9852);  // Hydrogen magenta/violet
	vec3 C3 = vec3(1.0,    0.2378, 0.0300);  // Neon     red
	vec3 C4 = vec3(0.6617, 0.5097, 1.0);     // Krypton  blue-violet
	vec3 C5 = vec3(1.0,    0.3007, 0.0494);  // Oxygen   orange-red
	if (t < 0.20) return mix(C0, C1, t / 0.20);
	if (t < 0.40) return mix(C1, C2, (t - 0.20) / 0.20);
	if (t < 0.60) return mix(C2, C3, (t - 0.40) / 0.20);
	if (t < 0.80) return mix(C3, C4, (t - 0.60) / 0.20);
	return mix(C4, C5, (t - 0.80) / 0.20);
}

// The 06 family's emission spectrum. The source cuts random ZERO-width bands
// between the element stops, so the colours read as SEPARATE REGIONS with dark
// gaps -- not one blended hue. uVolBands sets how many bands span the density
// range (fewer = thicker stripes).
// Multi-stop nebula palette (see uPal0..3). Driven by a LOW-frequency field so the
// hues appear as broad areas. uPal1 (purple) is a NARROW fringe at the boundary --
// the previous version ramped INTO purple across half the range and also used a
// wide band, so purple swallowed everything. Now: broad red below, broad blue/green
// above, purple only in a thin strip between them.
vec3 volPalette(vec3 p) {
	float t = clamp((fbm3(p * uVolPalScale + 101.0) - 0.30) * 1.8, 0.0, 1.0);
	float w = max(uPalPurpleW, 0.001);
	float c = 0.40;
	if (t < c - w) return uPal0;
	if (t < c)     return mix(uPal0, uPal1, (t - (c - w)) / w);
	if (t < c + w) return mix(uPal1, uPal2, (t - c) / w);
	return mix(uPal2, uPal3, (t - (c + w)) / max(1.0 - (c + w), 1e-3));
}
// Colour chosen by a low-frequency field QUANTISED into whole colours, so the sky
// is made of FAT areas that are each clearly one hue -- not a gradient (which just
// averages to a muddy in-between) and not bands (which read as contours).
// The palette is uNebulaColorA / uNebulaColorB, alternating region by region.
vec3 regionPalette(float k) {
	return mod(k, 2.0) < 0.5 ? uNebulaColorA : uNebulaColorB;
}

vec3 volRegionColour(vec3 dir) {
	// fbm3 has a NARROW distribution (sd ~0.1 about 0.5), so it must be spread out
	// before quantising or every direction lands in the same colour cell.
	float f = clamp((fbm3(dir * uVolRegionScale + 61.0) - 0.30) * 2.2, 0.0, 0.9999);
	float n = max(uVolRegions, 2.0);
	float pos = clamp(f, 0.0, 0.9999) * n;
	float idx = floor(pos);
	float frac = fract(pos);
	// only blend inside a narrow boundary band, so each area is CLEARLY one colour
	float s = max(uVolRegionSharp, 1e-3);
	float t = smoothstep(0.5 - s * 0.5, 0.5 + s * 0.5, frac);
	return mix(regionPalette(idx), regionPalette(idx + 1.0), t);
}

// The ACTUAL density_map of scene 37's mCloudNebula06, recovered by replaying
// POV-Ray's RNG (recipes/starfield3.md, probe-nebula06.pov): element stops at
// .10/.25/.40/.55/.70/.85, zero-width DARK bands at the irregular positions below,
// and the whole map shifted by phase 0.5088. Those irregular gaps -- some very
// wide, e.g. 0.27..0.39 is outright black and Hydrogen ramps down over 0.137 --
// are what separate the colours into distinct regions. Uniform banding was a
// fiction I invented before probing the source.
vec3 volSpectrum(float d) {
	d = fract(d * uVolSpectrumScale - uVolSpectrumPhase);
	vec3 C0 = vec3(1.0,    0.4518, 0.1368);  // .10 Carbon   orange
	vec3 C1 = vec3(1.0,    0.4594, 0.5463);  // .25 Helium   pink
	vec3 C2 = vec3(1.0,    0.2313, 0.9852);  // .40 Hydrogen magenta/violet
	vec3 C3 = vec3(1.0,    0.2378, 0.0300);  // .55 Neon     red
	vec3 C4 = vec3(0.6617, 0.5097, 1.0);     // .70 Krypton  blue-violet
	vec3 C5 = vec3(1.0,    0.3007, 0.0494);  // .85 Oxygen   orange-red
	vec3 Z = vec3(0.0);
	if (d < 0.1000) return mix(Z,  C0,  d / 0.1000);
	if (d < 0.2500) return mix(C0, C1, (d - 0.1000) / 0.1500);
	if (d < 0.2697) return mix(C1, Z,  (d - 0.2500) / 0.0197);
	if (d < 0.3935) return Z;                                    // wide dark gap
	if (d < 0.4000) return mix(Z,  C2, (d - 0.3935) / 0.0065);
	if (d < 0.5374) return mix(C2, Z,  (d - 0.4000) / 0.1374);
	if (d < 0.5500) return mix(Z,  C3, (d - 0.5374) / 0.0126);
	if (d < 0.5862) return mix(C3, Z,  (d - 0.5500) / 0.0362);
	if (d < 0.7000) return mix(Z,  C4, (d - 0.5862) / 0.1138);
	if (d < 0.7347) return mix(C4, Z,  (d - 0.7000) / 0.0347);
	if (d < 0.7554) return Z;
	if (d < 0.8500) return mix(Z,  C5, (d - 0.7554) / 0.0946);
	return mix(C5, Z, (d - 0.8500) / 0.1500);
}

// Kaliset field (see uVolKali). Returns a soft 0..1-ish density.
const int KALI_ITER = 18;

float kalisetField(vec3 p, float iterF) {
	float accum = 0.25;
	float prev = 0.0;
	float tw = 0.0;
	vec3 c = vec3(-0.5, -0.4, -1.487);
	for (int i = 0; i < KALI_ITER; i++) {
		if (float(i) >= iterF) break;
		float mag = dot(p, p);
		p = abs(p) / max(mag, 1e-6) + c;
		float w = exp(-float(i) / 5.0);
		accum += w * exp(-9.025 * pow(max(abs(mag - prev), 1e-6), 2.2));
		tw += w;
		prev = mag;
	}
	return max(0.0, 5.2 * accum / max(tw, 1e-6) - 0.65);
}

float volDensity(vec3 p, float symMask) {
	// octant mirror symmetry, masked to a REGION of the sky (see uVolSym*)
	vec3 q = mix(p, abs(p), uVolOctant * symMask);
	// A very large-scale "mass" field decides WHERE the cloud exists at all, so
	// the result has real cloud masses and real voids. Without it a single-scale
	// fbm integrates along the ray to a nearly uniform fog: every ray crosses
	// roughly the same amount of noise.
	float mass = fbm3(q * uVolScale * 0.35 + 31.0);
	float gate = smoothstep(uVolThreshold - 0.15, uVolThreshold + 0.25, mass);
	// granite-like turbulence. POV-Ray's `granite` has SHARP transitions, so a
	// thresholded smooth fbm gives cumulus blobs where the source has lace. A
	// RIDGED field (the mid-line of the contrast-stretched noise) produces thin
	// filaments and sheets instead. uVolRidge mixes between the two.
	float f = fbm(q * uVolScale + 13.0);
	float cs = smoothstep(0.34, 0.66, f);        // stretch the narrow fbm to 0..1
	float ridge = 1.0 - abs(2.0 * cs - 1.0);     // 1 along the mid-line
	float field = mix(cs, ridge, uVolRidge);
	if (uVolSpiral > 0.0) {
		// the spiral picks which sub-pattern applies: cellular -> banded -> bumps
		float spiral = volSpiralValue(q);
		float crackle = 1.0 - abs(2.0 * fbm(q * uVolScale * 2.0 + 53.0) - 1.0);
		float marble  = 0.5 + 0.5 * sin(q.x * uVolScale * 3.0
		                              + fbm(q * uVolScale) * 6.0);
		float bumps   = fbm(q * uVolScale * 3.0 + 17.0);
		// spiral picks the sub-pattern, keyed at the source's actal dp*0.1 = 0.1313
		// (pigment_map [0 crackle] [0.1313 marble] [1 bumps])
		float mixed = spiral < 0.1313
			? mix(crackle, marble, spiral / 0.1313)
			: mix(marble, bumps, (spiral - 0.1313) / (1.0 - 0.1313));
		field = mix(field, mixed, uVolSpiralMix);
	}
	float dense = smoothstep(uVolThreshold, uVolThreshold + uVolContrast, field);
	// optionally replace the fbm shape with the kaliset (see uVolKali)
	if (uVolKali > 0.0) {
		float k = clamp(kalisetField(q * uVolKaliScale, uVolKaliIter) * uVolKaliStrength, 0.0, 1.0);
		dense = mix(dense, k, uVolKali);
		// NOTE: do NOT bypass the mass gate here -- that lets the kaliset fill the
		// whole sky and washes the image out (mean 0.69 in testing). The gate is what
		// gives clouds-and-voids structure.
	}
	// fine texture: without it the clouds read as smooth blobs instead of the
	// source's lacy filaments
	float fine = fbm3(q * uVolScale * 5.0 + 71.0);
	dense *= mix(1.0 - uVolFine, 1.0 + uVolFine * 0.85, fine);
	// radial envelope (the source's `spherical` + poly_wave base): a cavity around
	// the viewer, fading at the outer edge. Deliberately broad -- a thin shell
	// would give every ray the same depth and flatten the result.
	float r = length(q);
	// concentric shells (the source's `spherical scale 6 poly_wave 2`)
	float shell = 1.0;
	if (uVolShell > 0.0) {
		shell = pow(clamp(1.0 - fract(r * uVolShell * 0.5 + 0.35), 0.0, 1.0), 2.0);
	}
	float env = smoothstep(uVolEnvInner, uVolEnvInner + 0.35, r)
	          * (1.0 - smoothstep(uVolEnvOuter - 0.30, uVolEnvOuter, r));
	return dense * gate * env * shell;
}

// Density -> colour. The source does NOT derive colour from the form density:
// the density is itself coloured, by a `spotted` pattern mapped c0 -> c1 -> c0.
// So the two palette colours appear as INTERLEAVED PATCHES at a small scale,
// which is what reads as a pronounced two-tone nebula.
vec3 volTone(vec3 p) {
	float t = fbm3(p * uVolToneScale + 101.0);
	// Confine the second colour to a band around t=0.42, so the first palette
	// colour stays dominant and the second reads as concentrated patches -- like
	// the source render, instead of an even patchwork.
	float w = mix(0.30, 0.08, clamp(uVolToneSharp, 0.0, 1.0));
	float gold = 1.0 - clamp(abs(t - 0.42) / max(w, 0.01), 0.0, 1.0);
	return mix(uNebulaColorA, uNebulaColorB, smoothstep(0.0, 1.0, gold));
}

// Returns the emitted colour; `outTrans` is the transmittance through the cloud
// (what still reaches us from BEHIND it -- this dims the stars).
// A full-range 0..1 PATTERN signal -- the equivalent of the source's
// f_Nebulae(abs(x),abs(y),abs(z)).gray, i.e. `spiral1 4` selecting between
// cellular / banded / bump sub-patterns, turbulence-warped.
//
// THIS IS THE CRUX. In the source the colour map is keyed by a pattern value that
// SWEEPS the whole 0..1 range as you move through space, so each colour band of
// the map (Neon=red, Krypton=blue-violet, ...) lands in a FAT spatial region.
// Feeding the map a cloud-style density (mostly near zero, sparse clumps) never
// traverses the map at all -- you only ever see its bottom, which is mud. And
// colour and brightness must come from the SAME signal, or the colour reads as
// paint over the cloud rather than belonging to it.
float volSignal(vec3 p, float symMask) {
	vec3 q = mix(p, abs(p), uVolOctant * symMask) * uVolScale;
	float spiral = volSpiralValue(q);
	float crackle = 1.0 - abs(2.0 * fbm(q + 53.0) - 1.0);
	float marble  = 0.5 + 0.5 * sin(q.x * 3.0 + fbm(q) * 6.0);
	float bumps   = fbm(q + 17.0);
	// the source's pigment_map keys: 0 crackle, 0.1313 marble, 1 bumps
	float mixed = spiral < 0.1313
		? mix(crackle, marble, spiral / 0.1313)
		: mix(marble, bumps, (spiral - 0.1313) / (1.0 - 0.1313));
	// a little turbulence, as the source's warp{turbulence}
	mixed = mix(mixed, fbm(q * 2.0 + 71.0), uVolFine);
	// stretch to the full 0..1 range the source's patterns naturally have
	return clamp((mixed - uSigBias) * uSigScale, 0.0, 1.0);
}

vec3 volMarch(vec3 dir, out float outTrans) {
	vec3 emit = vec3(0.0);
	// transmittance is per-channel: the source's density is a colour, so each
	// channel attenuates independently
	vec3 trans = vec3(1.0);
	float stepLen = 1.0 / float(VOL_STEPS);
	// colour region for this direction (constant along the ray, by design)
	vec3 regionCol = volRegionColour(dir);
	// how much of the sky gets the mirrored pattern (a patch, not the whole face)
	float symMask = 1.0;
	if (uVolOctant > 0.0) {
		float sf = clamp((fbm3(dir * uVolSymScale + 7.0) - 0.35) * 2.0, 0.0, 1.0);
		symMask = smoothstep(1.0 - uVolSymAmount - 0.30, 1.0 - uVolSymAmount + 0.30, sf);
	}
	for (int i = 0; i < VOL_STEPS; i++) {
		float t = (float(i) + 0.5) * stepLen;
		if (uVolPattern > 0.5) {
			// SOURCE-FAITHFUL: one full-range signal drives colour AND brightness.
			// volSpectrum returns the recovered element density_map, which is zero
			// in the dark bands -- so brightness comes free from the map itself.
			float sig = volSignal(dir * t, symMask);
			float r = length(dir * t);
			float env = smoothstep(uVolEnvInner, uVolEnvInner + 0.35, r)
			          * (1.0 - smoothstep(uVolEnvOuter - 0.30, uVolEnvOuter, r));
			vec3 col = volSpectrum(sig) * env;
			emit += trans * col * uVolEmission * stepLen;
			if (uVolExtinction > 0.0) {
				trans *= exp(-length(col) * uVolExtinction * stepLen);
			}
		} else if (uVolRGB > 0.5) {
			// SOURCE-FAITHFUL COLOURED DENSITY. The density is a colour: the form
			// (shape) times the palette pattern, so every channel carries its own
			// structure and the colour belongs to the cloud. Scattering colour is
			// the source's grey `rgb fDensity`, so the emitted colour is just the
			// per-channel opacity; extinction is per channel too.
			float dv = volDensity(dir * t, symMask);
			float amt = dv + uVolHaze + uVolGain * dv * dv;
			vec3 cd = volPalette(dir * t) * amt * uVolAmount;
			vec3 a = vec3(1.0) - exp(-cd * uVolExtinction * stepLen);
			emit += trans * a * uVolEmission;
			trans *= (vec3(1.0) - a);
		} else {
			float dv = volDensity(dir * t, symMask);
			if (dv > 0.002) {
				float sigma = dv * uVolAmount;
				// attenuation (`extinction`) and light (`emission`) are separate
				float a = 1.0 - exp(-sigma * uVolExtinction * stepLen);
				vec3 emiss = mix(volTone(dir * t), volSpectrum(dv), uVolSpectrum);
				if (uVolRegion > 0.0) {
					emiss = mix(emiss, regionCol, uVolRegion);
				}
				emit += trans * emiss * (a + sigma * stepLen * uVolEmission);
				trans *= 1.0 - a;
			}
		}
	}
	outTrans = clamp((trans.r + trans.g + trans.b) / 3.0, 0.0, 1.0);
	return emit;
}

// ---- star layer ----------------------------------------------------------
// One candidate star per cell of a direction-space lattice; cells that pass the
// brightness threshold draw a soft point. `out` returns the star's colour.
// The point radius is derived from the PAYLOAD's screen-space footprint
// (fwidth), so a star stays ~1-2 px at ANY bake resolution instead of growing
// into a blob as the resolution rises.
// `bias` shifts the effective presence threshold for THIS direction: a negative
// bias means "inside a cluster", so more stars appear there. That is how
// clustering changes star DENSITY rather than brightness.
float starLayer(vec3 dir, float cells, float size, float seed, float bright_cut, float bias, out vec3 col) {
	vec3 p = dir * cells + seed;
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float h = hash13(ip + seed * 1.7);
	vec3 sp = vec3(hash13(ip + 1.3), hash13(ip + 2.7), hash13(ip + 5.1));
	float d = length(fp - sp);

	// Angular radius (fixed, floored at one pixel), converted to cell units
	float angR = max(size * uStarAngSize, uPxPerDir);
	float r = max(angR * cells, 1e-9);
	float glow = exp(-(d * d) / (r * r));

	// colour: blue-white .. warm, plus a rare bright one
	float ct = hash13(ip + 9.7);
	float mag = pow(hash13(ip + 13.1), 3.0);
	col = mix(vec3(0.72, 0.80, 1.0), vec3(1.0, 0.86, 0.66), ct);
	float present = step(clamp(bright_cut + bias, 0.0, 1.0), h);
	return glow * present * (0.35 + 0.65 * mag);
}

// Clustering density field: how far inside a star cluster this direction is,
// roughly -1..1. The recipes get this from `distribu_angle` + `excentricity`.
float clusterField(vec3 dir, float scale, float seed) {
	return (fbm(dir * scale + seed) - 0.5) * 2.2;
}

// A star field as a COMPOSITION of size classes: tiny+many, medium, big+few.
// Cells scale with uStarDensity; the classes differ in star size and count just
// as `SF_NUMBERS` + the size-class ranges do in the source.
vec3 starField(vec3 dir, float bias) {
	vec3 c1, c2, c3;
	float s1 = starLayer(dir, 60.0 * uStarDensity, uStarSize * 0.70,  0.0, uStarThreshold, bias, c1);
	float s2 = starLayer(dir, 26.0 * uStarDensity, uStarSize * 1.50, 17.0,
	                     uStarThreshold + 0.08 - 0.08 * uStarClassMix, bias * 0.6, c2);
	float s3 = starLayer(dir,  9.0 * uStarDensity, uStarSize * 3.00, 43.0,
	                     uStarThreshold + 0.16, bias * 0.35, c3);
	return c1 * s1 + c2 * s2 * 0.85 + c3 * s3 * 1.10;
}

// The star density bias for this direction: broad clusters plus tight
// concentrations layered on top (the recipes' `O_StarConcentration` blocks).
float starBias(vec3 dir) {
	float broad = -uClusterStrength * max(clusterField(dir, uClusterScale, 3.0), 0.0);
	float tight = -uTightClusterAmount
	            * smoothstep(0.15, 0.60, clusterField(dir, uTightClusterScale, 57.0));
	return broad + tight;
}

// ---- the sky -------------------------------------------------------------
vec3 skyColor(vec3 dir) {
	dir = normalize(dir);

	// 1. galactic band — the MILKY WAY, fitted to the ESO panorama (2026-09-23).
	//    Measured: vertical profile 100% at the plane -> 62% at |sin lat| 0.10 ->
	//    24% at 0.20 -> ~6% at 0.50 with a long tail; a compact ±25° bulge at the
	//    galactic centre (96% -> 50% at 22° -> 35% at 45°) over a ~22% floor; and
	//    strong structure (sd/mean 0.54, p95/mean 2.05) — bright star clouds and
	//    deep filamentary rifts.
	float pole = abs(dot(dir, normalize(uPoleDir)));          // |sin(galactic lat)|
	float s = pole / max(uBandWidth, 0.05);
	float prof = 0.62 * exp(-pow(s / 0.085, 1.35))
	           + 0.38 * exp(-pow(s / 0.250, 1.10));

	float ca = clamp(dot(dir, normalize(uCenterDir)), -1.0, 1.0);
	float ang = acos(ca);                                     // radians from the centre
	float bulge = uBulgeFloor + (1.0 - uBulgeFloor)
	            * exp(-pow(ang / radians(uBulgeWidth), uBulgePow));

	// structure: star clouds brighten, ridged noise darkens as filamentary rifts
	float clouds = fbm(dir * uBandStructScale + 21.0);
	float ridged = 1.0 - abs(2.0 * fbm(dir * uBandStructScale * 0.6 + 5.0) - 1.0);
	float bandtex = mix(0.45, 1.90, pow(clouds, 1.4))
	              * (1.0 - uRiftStrength * pow(ridged, 3.0));
	float asym = mix(1.0 - uBandAsym, 1.0, ca * 0.5 + 0.5);
	float band = max(prof * bulge * bandtex * asym, 0.0);
	vec3 col = uBandColor * (band * uBandIntensity);

	// 2. far star populations — the size-class composition, with CLUSTERING
	//    (stars bunch into clusters and tight concentrations). These sit BEHIND
	//    the dust, so the dust attenuates them below.
	float sbias = starBias(dir);
	vec3 star_col = starField(dir, sbias);

	// 3. dust / nebula: filamentary emission, and extinction of what is behind it.
	// Domain-warped ridged fbm -> thin strands (not blobs); a low-frequency mask
	// carves large dark voids, as in the shipped art.
	vec3 wp = dir * uNebulaScale;
	vec3 warp = vec3(fbm(wp + 11.0), fbm(wp + 23.0), fbm(wp + 37.0));
	float n = fbm(wp + warp * uWarp);
	float filaments = pow(max(0.0, 1.0 - abs(2.0 * n - 1.0)), uFilamentSharp);
	float voids = smoothstep(uVoidThreshold, 1.0, fbm(dir * uVoidScale + 5.0));
	float dust = filaments * voids * uNebulaAmount;
	float mixv = fbm(wp * 0.5 + 11.0);
	vec3 nebula = mix(uNebulaColorA, uNebulaColorB, mixv) * dust;

	// 3b. volumetric nebula -- marched BEFORE the stars are composited, because
	// its extinction is exactly what dims the stars behind it.
	vec3 volEmit = vec3(0.0);
	float volTrans = 1.0;
	 // either path needs the march: cloud-density path (uVolAmount) or the
	 // source-faithful pattern path (uVolPattern)
	if (uVolAmount > 0.0 || uVolPattern > 0.5) {
		volEmit = volMarch(dir, volTrans);
	}
	float transmittance = clamp(1.0 - dust * uDustExtinction, 0.0, 1.0) * volTrans;

	// 4. near stars — in FRONT of the dust, so not attenuated
	vec3 near_col;
	float near = starLayer(dir, 20.0 * uStarDensity, uStarSize * 2.6, 31.0,
	                       uStarThreshold + 0.2, sbias * 0.5, near_col) * uNearStars;

	col = col * transmittance + star_col * uStarBright * transmittance + volEmit;
	col += nebula;
	col += near_col * near * uStarBright;

	// 4b. a handful of nearby bright stars: a warm compact core PLUS a wide soft
	// halo (the shipped art's "glowing yellow" spots are a bright warm star
	// lighting its neighbourhood, not a diffuse cloud).
	vec3 bcol, hcol;
	float bcore = starLayer(dir, 5.0 * uBrightStarDensity, uStarSize * uBrightStarSize,
	                        91.0, 0.78, 0.0, bcol);
	float bhalo = starLayer(dir, 5.0 * uBrightStarDensity, uStarSize * uBrightStarSize * 4.0,
	                        91.0, 0.78, 0.0, hcol);
	vec3 bstar = (bcol * bcore * uBrightStarBright + hcol * bhalo * uBrightStarHalo * 0.35)
	             * uBrightStarColor;
	col += bstar;

	// contrast shaping (see the uGamma/uDarkLanes/uKnot* uniforms)
	float lanes = fbm(dir * uBandStructScale * 0.35 + 41.0);
	col *= 1.0 - uDarkLanes * smoothstep(0.45, 0.80, lanes);
	// Lit dust clouds — REFLECTION NEBULAE: a nearby bright star lights the dust
	// around it. So the glow is coupled to (a) a bright star's halo and (b) whether
	// there is dust there to light, and its colour grades from a bright core
	// through gold to brown at the wispy edges.
	float cloud = clamp((fbm(dir * uKnotScale + 77.0) - uKnotThreshold)
	                    / max(1e-3, 1.0 - uKnotThreshold), 0.0, 1.0);
	float illumination = 0.45 + 0.55 * clamp(bhalo * uBrightStarHalo, 0.0, 1.0);
	float dust_here = clamp(dust * 3.0, 0.0, 1.0);
	float lit = pow(cloud, 1.4) * illumination * dust_here
	          + uKnotGlow * pow(cloud, 2.5) * illumination;
	vec3 litCol = mix(uKnotEdgeColor, uKnotColor, pow(cloud, 0.6));
	// give the lit cloud internal wispy structure, or it renders as a smooth
	// gradient blob instead of dust
	float litStruct = mix(0.30, 1.70, fbm(dir * uNebulaScale * 2.5 + 91.0));
	col += litCol * lit * litStruct * uKnotAmount;
	col = pow(max(col, 0.0), vec3(uGamma));

	return col * uExposure;
}
