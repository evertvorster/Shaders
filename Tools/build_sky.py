#!/usr/bin/env python3
"""build_sky.py — generate every host format of the sky compositor.

    python3 Tools/build_sky.py            # generate + verify
    python3 Tools/build_sky.py --check    # verify only
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shader_build as sb

OUTDIR = os.path.join(sb.ROOT, "Space", "Sky")

sb.main(OUTDIR,
        [os.path.join(OUTDIR, "sky.frag")],
        "build_sky.py",
        glsl_body="\tcol = skyColour(uCamPos, dir, pxPerDir, dither, transmittance);",
        bake_body="\tcol = skyColour(uBakePos, dir, pxPerDir, dither, transmittance);",
        godot_body="\tcol = skyColour(uCamPos, dir, uPxPerDir, dither, transmittance);")
