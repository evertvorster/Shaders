#!/usr/bin/env python3
"""build_all.py — regenerate every generated host file in the repo.

The generated files are committed, so they go stale if a source changes and the builder
is not run. Worse, `python3 Tools/build_*.py --check` only VERIFIES: it can leave a stale
generated file looking fine. This one command writes everything:

    python3 Tools/build_all.py            # regenerate + verify all
    python3 Tools/build_all.py --check    # verify only (no writes)

Run it before committing any shader change.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILDERS = [
    "build_starfield.py",
    "build_nebula.py",
    "build_milkyway.py",
    "build_galaxy.py",
    "build_volumetric_starfield.py",
    "build_scenes.py",
    "build_sky.py",
]


def main():
    check_only = "--check" in sys.argv
    bad = 0
    for name in BUILDERS:
        args = [sys.executable, os.path.join(HERE, name)]
        if check_only:
            args.append("--check")
        r = subprocess.run(args)
        if r.returncode != 0:
            bad += 1
            print("!! %s failed" % name)
    if bad:
        print("%d builder(s) failed" % bad)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
