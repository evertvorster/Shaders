#!/usr/bin/env python3
"""build_galaxy.py — generate every host format of the parked distant-galaxy layer.

    python3 Tools/build_galaxy.py            # generate + verify
    python3 Tools/build_galaxy.py --check    # verify only

Direction-only (a fixed backdrop at galactic distance), so no dither.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_build as sb

OUTDIR = os.path.join(sb.ROOT, "Space", "Galaxy")

sb.main(OUTDIR,
        [os.path.join(OUTDIR, "analytic-galaxy.frag")],
        "build_galaxy.py",
        glsl_body="\tcol = galaxySky(uCamPos, dir, pxPerDir, transmittance);",
        godot_body="\tcol = galaxySky(uCamPos, dir, uPxPerDir, transmittance);",
        dither=False)
