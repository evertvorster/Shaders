#!/usr/bin/env python3
"""build_milkyway.py — generate every host format of the Milky Way layer.

    python3 Tools/build_milkyway.py            # generate + verify
    python3 Tools/build_milkyway.py --check    # verify only

The layer is direction-only (we are inside the galaxy, so there is no parallax to show),
which is why its host call passes no camPos and needs no dither.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_build as sb

OUTDIR = os.path.join(sb.ROOT, "Space", "MilkyWay")

sb.main(OUTDIR,
        [os.path.join(OUTDIR, "milkyway.frag")],
        "build_milkyway.py",
        glsl_body="\tcol = milkywaySky(dir, pxPerDir, transmittance);",
        godot_body="\tcol = milkywaySky(dir, uPxPerDir, transmittance);",
        dither=False)
