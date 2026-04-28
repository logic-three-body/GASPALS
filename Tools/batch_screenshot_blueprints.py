"""
GASPALS Blueprint Batch Screenshot - Tick-Based State Machine
=============================================================
Run inside UE Editor: Tools > Execute Python Script
File: d:/UE/COLMM/GASPALS/Tools/batch_screenshot_blueprints.py

Uses unreal.register_slate_tick_callback() so UE can keep rendering
between operations. Does NOT use time.sleep() which would freeze the editor.

Output:
  Saved/Screenshots/Blueprints/<Module>/<AssetName>/<AssetName>.png
"""

import unreal
import os
import time as _time

# ──────────────────────────────────────────────
#  CONFIG
# ──────────────────────────────────────────────
OUTPUT_ROOT = os.path.normpath(
    os.path.join(unreal.Paths.project_saved_dir(), "Screenshots", "Blueprints")
)

TICKS_AFTER_OPEN   = 180   # ~3 s at 60 fps — wait for graph to render
TICKS_AFTER_PRINT  = 240   # ~4 s for GraphPrinter to export

MODULE_MAP = [
    ("/GASPALS/Blueprints/AnimNotifies",             "02_AnimNotifies"),
    ("/GASPALS/Blueprints/Cameras",                  "07_Components_Cameras"),
    ("/GASPALS/Blueprints/Components",               "07_Components_Cameras"),
    ("/GASPALS/Blueprints/Data",                     "07_Components_Cameras"),
    ("/GASPALS/Blueprints/RetargetedCharacters",     "03_RetargetedCharacters"),
    ("/GASPALS/Blueprints",                          "01_Core"),
    ("/GASPALS/Characters",                          "06_Characters_Rigs"),
    ("/GASPALS/MetaHumans",                          "05_MetaHumans"),
    ("/GASPALS/OverlaySystem/Overlays/Bases",        "04_OverlaySystem/Bases"),
    ("/GASPALS/OverlaySystem/Overlays/Poses",        "04_OverlaySystem/Poses"),
    ("/GASPALS/OverlaySystem",                       "04_OverlaySystem"),
    ("/GASPALS/Widgets",                             "08_Widgets"),
    ("/GASPALS/Audio",                               "09_Audio"),
]

TARGET_CLASSES = ["Blueprint", "AnimBlueprint", "WidgetBlueprint"]

# ──────────────────────────────────────────────
#  HELPERS
# ──────────────────────────────────────────────

def get_module_folder(pkg_path: str) -> str:
    for prefix, folder in MODULE_MAP:
        if pkg_path.startswith(prefix):
            return folder
    return "00_Other"

def ensure_dir(path: str):
    os.makedirs(path, exist_ok=True)

def set_output_dir(path: str) -> bool:
    """Point GraphPrinter at a specific output folder via its settings CDO."""
    try:
        cls = unreal.load_class(None, "/Script/WidgetPrinter.WidgetPrinterSettings")
        if not cls:
            return False
        cdo = unreal.get_default_object(cls)
        dp  = unreal.DirectoryPath()
        dp.set_editor_property("path", path.replace("\\", "/"))
        cdo.set_editor_property("output_directory", dp)
        return True
    except Exception as e:
        unreal.log_warning(f"[SS] set_output_dir: {e}")
        return False

def trigger_print() -> bool:
    """Call GraphPrinter's PrintAllAreaOfWidget via the command bindings."""
    try:
        # Try registered console command first
        unreal.SystemLibrary.execute_console_command(
            None, "GraphPrinter.PrintAllAreaOfWidget"
        )
        return True
    except Exception:
        pass
    # Fallback: simulate Ctrl+F9 via InputBinding name
    try:
        subsystem = unreal.get_editor_subsystem(unreal.AssetEditorSubsystem)
        unreal.log_warning("[SS] Console command not found; please press Ctrl+F9 manually.")
    except Exception:
        pass
    return False

def collect_assets() -> list:
    ar = unreal.AssetRegistryHelpers.get_asset_registry()
    ar.search_all_assets(True)
    seen, result = set(), []
    for cls in TARGET_CLASSES:
        # UE 5.7: ARFilter is a struct — pass all fields as constructor kwargs
        try:
            f = unreal.ARFilter(
                package_paths=["/GASPALS"],
                recursive_paths=True,
                class_paths=[unreal.TopLevelAssetPath("/Script/Engine", cls)]
            )
        except Exception:
            # Fallback: use class_names (pre-5.1 style)
            f = unreal.ARFilter(
                package_paths=["/GASPALS"],
                recursive_paths=True,
                class_names=[cls]
            )
        for a in ar.get_assets(f):
            k = str(a.package_name)
            if k not in seen:
                seen.add(k)
                result.append(a)
    unreal.log(f"[SS] Found {len(result)} assets.")
    return result

# ──────────────────────────────────────────────
#  TICK-BASED STATE MACHINE
# ──────────────────────────────────────────────

class BatchScreenshotRunner:
    STATE_NEXT     = "next"       # pick next asset
    STATE_WAIT_OPEN= "wait_open"  # counting ticks after editor open
    STATE_PRINT    = "print"      # trigger screenshot
    STATE_WAIT_OUT = "wait_out"   # counting ticks after screenshot
    STATE_DONE     = "done"

    def __init__(self, assets: list):
        self.assets    = assets
        self.total     = len(assets)
        self.idx       = 0
        self.state     = self.STATE_NEXT
        self.tick_cnt  = 0
        self.success   = 0
        self.fail      = 0
        self.log_lines = []
        self.editor_sub = unreal.get_editor_subsystem(unreal.AssetEditorSubsystem)
        self._handle   = None   # tick callback handle
        ensure_dir(OUTPUT_ROOT)

        unreal.log("=" * 56)
        unreal.log(f"[SS] Batch Screenshot START — {self.total} assets")
        unreal.log(f"[SS] Output root: {OUTPUT_ROOT}")
        unreal.log("=" * 56)

    def start(self):
        self._handle = unreal.register_slate_post_tick_callback(self._tick)

    def _tick(self, delta: float):
        if self.state == self.STATE_DONE:
            self._finish()
            return

        if self.state == self.STATE_NEXT:
            self._advance()

        elif self.state == self.STATE_WAIT_OPEN:
            self.tick_cnt += 1
            if self.tick_cnt >= TICKS_AFTER_OPEN:
                self.state    = self.STATE_PRINT
                self.tick_cnt = 0

        elif self.state == self.STATE_PRINT:
            ok = trigger_print()
            if ok:
                self.success += 1
                unreal.log(f"  [OK] {self._cur_name}")
                self.log_lines.append(f"OK   | {self._cur_module} | {self._cur_name}")
            else:
                self.fail += 1
                unreal.log_warning(f"  [FAIL] trigger failed: {self._cur_name}")
                self.log_lines.append(f"FAIL | {self._cur_module} | {self._cur_name} | trigger")
            self.state    = self.STATE_WAIT_OUT
            self.tick_cnt = 0

        elif self.state == self.STATE_WAIT_OUT:
            self.tick_cnt += 1
            if self.tick_cnt >= TICKS_AFTER_PRINT:
                self.idx  += 1
                self.state = self.STATE_NEXT if self.idx < self.total else self.STATE_DONE
                self.tick_cnt = 0

    def _advance(self):
        if self.idx >= self.total:
            self.state = self.STATE_DONE
            return

        a = self.assets[self.idx]
        pkg  = str(a.package_name)
        name = str(a.asset_name)

        self._cur_name   = name
        self._cur_module = get_module_folder(pkg)

        out_dir = os.path.join(OUTPUT_ROOT, self._cur_module, name)
        ensure_dir(out_dir)

        unreal.log(f"\n[{self.idx+1}/{self.total}] {name}")

        # set output dir
        set_output_dir(out_dir)

        # open asset editor
        try:
            obj = unreal.load_asset(pkg)
            if obj is None:
                raise RuntimeError("load_asset returned None")
            opened = self.editor_sub.open_editor_for_assets([obj])
            if not opened:
                raise RuntimeError("open_editor_for_assets failed")
        except Exception as e:
            unreal.log_warning(f"  [SKIP] {name}: {e}")
            self.fail += 1
            self.log_lines.append(f"SKIP | {self._cur_module} | {name} | {e}")
            self.idx  += 1
            return  # stay in STATE_NEXT, advance next tick

        self.state    = self.STATE_WAIT_OPEN
        self.tick_cnt = 0

    def _finish(self):
        # unregister tick
        if self._handle is not None:
            unreal.unregister_slate_post_tick_callback(self._handle)
            self._handle = None

        # write index
        idx_path = os.path.join(OUTPUT_ROOT, "_index.txt")
        with open(idx_path, "w", encoding="utf-8") as f:
            import time as t
            f.write("GASPALS Blueprint Screenshot Index\n")
            f.write(f"Generated : {t.strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Total={self.total}  OK={self.success}  FAIL={self.fail}\n")
            f.write("=" * 60 + "\n")
            f.write("\n".join(self.log_lines))

        unreal.log("\n" + "=" * 56)
        unreal.log(f"[SS] DONE  OK={self.success}  FAIL={self.fail}/{self.total}")
        unreal.log(f"[SS] Output : {OUTPUT_ROOT}")
        unreal.log(f"[SS] Index  : {idx_path}")
        unreal.log("=" * 56)

        try:
            os.startfile(OUTPUT_ROOT)
        except Exception:
            pass


# ──────────────────────────────────────────────
#  ENTRY POINT
# ──────────────────────────────────────────────
assets = collect_assets()
if assets:
    _runner = BatchScreenshotRunner(assets)
    _runner.start()
    unreal.log("[SS] Tick runner registered. Processing will continue in background...")
else:
    unreal.log_warning("[SS] No assets found — check /GASPALS content path.")
