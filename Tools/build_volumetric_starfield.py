#!/usr/bin/env python3
"""build_volumetric_starfield.py — generate every host format of the star-volume sources.

    python3 Tools/build_volumetric_starfield.py            # generate + verify
    python3 Tools/build_volumetric_starfield.py --check    # verify only
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_build as sb

OUTDIR = os.path.join(sb.ROOT, "Space", "volumetric_starfield")

sb.main(OUTDIR, sb.glob_sources(OUTDIR), "build_volumetric_starfield.py",
        glsl_body="\tcol = volumetricStarfieldSky(uCamPos, dir, pxPerDir, dither, transmittance);",
        godot_body="\tcol = volumetricStarfieldSky(uCamPos, dir, uPxPerDir, dither, transmittance);")
