"""
Compatibility entry point.

The old tick-only batch screenshot script has been replaced by the JSON
GraphPrinter remote-control workflow in Tools/ue_open_assets.py. This wrapper
keeps the old filename usable from the UE Python menu.
"""

import os
import runpy

import unreal


SCRIPT = os.path.join(unreal.Paths.project_dir(), "Tools", "ue_open_assets.py")
unreal.log(f"[GPBatch] Delegating to {SCRIPT}")
runpy.run_path(SCRIPT, run_name="__main__")
