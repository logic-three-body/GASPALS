"""
ue_open_assets.py — Final Version
==================================
Run inside UE Editor via -ExecCmds or Tools > Execute Python Script

Architecture:
  - Background thread: asyncio WebSocket server on ws://127.0.0.1:3000/
    GraphPrinter auto-connects (pre-configured via ini by setup_and_launch.ps1)
  - Slate tick state machine: opens each asset, waits, sends WS screenshot
    command, waits, moves PNG from staging dir to module subfolder
"""

import unreal
import os
import threading
import asyncio
import time
import json
import glob

# ──────────────────────────────────────────────────────────
#  CONFIG
# ──────────────────────────────────────────────────────────
PROJECT_SAVED  = unreal.Paths.project_saved_dir().replace("\\", "/")
OUTPUT_ROOT    = PROJECT_SAVED + "Screenshots/Blueprints"
STAGING_DIR    = PROJECT_SAVED + "GraphPrinter"   # GraphPrinter's actual default output dir
ASSET_LIST     = r"d:/UE/COLMM/GASPALS/Tools/asset_list.json"

WS_HOST = "127.0.0.1"
WS_PORT = 3000

TICKS_AFTER_OPEN  = 200   # ~3.3 s at 60 fps — wait for graph render
TICKS_AFTER_PRINT = 360   # ~6 s for GraphPrinter to export

TARGET_CLASSES = ["Blueprint", "AnimBlueprint", "WidgetBlueprint"]

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

def get_module_folder(pkg):
    for prefix, folder in MODULE_MAP:
        if pkg.startswith(prefix):
            return folder
    return "00_Other"

def ensure(path):
    os.makedirs(path.replace("/", "\\"), exist_ok=True)

# ──────────────────────────────────────────────────────────
#  STEP 1 — Collect assets & save list
# ──────────────────────────────────────────────────────────
ar = unreal.AssetRegistryHelpers.get_asset_registry()
ar.search_all_assets(True)

seen, assets = set(), []
for cls in TARGET_CLASSES:
    try:
        f = unreal.ARFilter(
            package_paths=["/GASPALS"],
            recursive_paths=True,
            class_paths=[unreal.TopLevelAssetPath("/Script/Engine", cls)]
        )
    except Exception:
        f = unreal.ARFilter(
            package_paths=["/GASPALS"],
            recursive_paths=True,
            class_names=[cls]
        )
    for a in ar.get_assets(f):
        k = str(a.package_name)
        if k not in seen:
            seen.add(k)
            assets.append({
                "package_name": str(a.package_name),
                "asset_name":   str(a.asset_name),
                "module":       get_module_folder(str(a.package_name))
            })

with open(ASSET_LIST, "w", encoding="utf-8") as jf:
    json.dump(assets, jf, indent=2)

unreal.log(f"[SS] {len(assets)} assets collected → {ASSET_LIST}")
ensure(OUTPUT_ROOT)
ensure(STAGING_DIR)

# ──────────────────────────────────────────────────────────
#  STEP 2 — WebSocket server (background thread)
# ──────────────────────────────────────────────────────────
_ws_client    = None       # the connected GraphPrinter socket
_ws_loop      = None       # asyncio event loop in the WS thread
_ws_ready     = threading.Event()

async def _ws_handler(websocket):
    global _ws_client
    _ws_client = websocket
    unreal.log(f"[SS][WS] GraphPrinter connected ✓")
    try:
        async for _ in websocket:
            pass
    except Exception:
        pass
    finally:
        _ws_client = None
        unreal.log("[SS][WS] GraphPrinter disconnected")

def _ws_thread_main():
    global _ws_loop
    try:
        import websockets
    except ImportError:
        # Install websockets into UE's embedded Python
        import subprocess, sys
        subprocess.check_call([sys.executable, "-m", "pip", "install", "websockets"])
        import websockets

    async def _serve():
        async with websockets.serve(_ws_handler, WS_HOST, WS_PORT):
            unreal.log(f"[SS][WS] Server listening on ws://{WS_HOST}:{WS_PORT}/")
            _ws_ready.set()
            await asyncio.Future()   # run forever

    _ws_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(_ws_loop)
    _ws_loop.run_until_complete(_serve())

_ws_thread = threading.Thread(target=_ws_thread_main, daemon=True)
_ws_thread.start()
_ws_ready.wait(timeout=8)
unreal.log("[SS][WS] Server ready. Triggering GraphPrinter RemoteControl connection...")

# ── Enable GraphPrinter RemoteControl AFTER WS server is ready ───────────────
try:
    rc_cls = unreal.load_class(None, "/Script/GraphPrinterRemoteControl.GraphPrinterRemoteControlSettings")
    if rc_cls:
        rc_cdo = unreal.get_default_object(rc_cls)
        rc_cdo.set_editor_property("bEnableRemoteControl", True)
        rc_cdo.set_editor_property("ServerURL", f"ws://{WS_HOST}:{WS_PORT}/")
        # modify() + set_editor_properties triggers PostEditChangeProperty →
        # OnRemoteControlEnabled.Broadcast() → GraphPrinter connects to our server
        rc_cdo.modify()
        rc_cdo.set_editor_properties({
            "bEnableRemoteControl": True,
            "ServerURL": f"ws://{WS_HOST}:{WS_PORT}/"
        })
        unreal.log("[SS][WS] GraphPrinter RemoteControl broadcast sent — waiting for connection...")
    else:
        unreal.log_warning("[SS][WS] GraphPrinterRemoteControlSettings class not found")
except Exception as e:
    unreal.log_warning(f"[SS][WS] RC enable failed: {e}")


def send_print_command():
    """Thread-safe: send PrintAllAreaOfWidget to GraphPrinter."""
    if _ws_client is None:
        unreal.log_warning("[SS][WS] No client — GraphPrinter not connected yet.")
        return False
    async def _send():
        await _ws_client.send("UnrealEngine-GraphPrinter-PrintAllAreaOfWidget")
    asyncio.run_coroutine_threadsafe(_send(), _ws_loop)
    return True

# ──────────────────────────────────────────────────────────
#  STEP 3 — Staging dir helper
# ──────────────────────────────────────────────────────────
_snapshot_before = set()

def snapshot_staging():
    """Record current PNGs in staging before triggering screenshot."""
    global _snapshot_before
    pattern = STAGING_DIR.replace("/", "\\") + "\\**\\*.png"
    _snapshot_before = set(glob.glob(pattern, recursive=True))

def collect_new_pngs():
    """Return PNGs created in staging since last snapshot."""
    pattern = STAGING_DIR.replace("/", "\\") + "\\**\\*.png"
    current = set(glob.glob(pattern, recursive=True))
    return list(current - _snapshot_before)

def move_pngs_to_module(asset_name, module):
    """Move any newly created PNGs to the correct module/asset subfolder."""
    new_files = collect_new_pngs()
    if not new_files:
        # Also scan the whole staging dir for recently modified files (< 15 s old)
        pattern = STAGING_DIR.replace("/", "\\") + "\\**\\*.png"
        all_pngs = glob.glob(pattern, recursive=True)
        cutoff = time.time() - 15
        new_files = [p for p in all_pngs if os.path.getmtime(p) > cutoff]

    if not new_files:
        return 0

    dest_dir = os.path.join(
        OUTPUT_ROOT.replace("/", "\\"), module, asset_name
    )
    os.makedirs(dest_dir, exist_ok=True)

    moved = 0
    for src in new_files:
        fname = os.path.basename(src)
        dst   = os.path.join(dest_dir, fname)
        try:
            if os.path.exists(dst):
                os.remove(dst)
            os.rename(src, dst)
            moved += 1
            unreal.log(f"  [MOVE] {fname} → {module}/{asset_name}/")
        except Exception as e:
            unreal.log_warning(f"  [MOVE ERR] {e}")
    return moved

# ──────────────────────────────────────────────────────────
#  STEP 4 — Tick state machine
# ──────────────────────────────────────────────────────────
editor_sub = unreal.get_editor_subsystem(unreal.AssetEditorSubsystem)

_state     = "next"
_idx       = 0
_tick_cnt  = 0
_success   = 0
_fail      = 0
_log_lines = []
_handle    = None
_total     = len(assets)

def _tick(delta):
    global _state, _idx, _tick_cnt, _success, _fail, _handle

    if _idx >= _total:
        _finish()
        return

    # ── STATE: next ──────────────────────────────────────
    if _state == "next":
        a      = assets[_idx]
        pkg    = a["package_name"]
        name   = a["asset_name"]
        module = a["module"]

        unreal.log(f"\n[SS] [{_idx+1}/{_total}] {name}  ({module})")

        snapshot_staging()   # record what was in staging before open

        try:
            obj = unreal.load_asset(pkg)
            if obj is None:
                raise RuntimeError("load_asset returned None")
            editor_sub.open_editor_for_assets([obj])
        except Exception as e:
            unreal.log_warning(f"  [SKIP] {e}")
            _fail += 1
            _log_lines.append(f"SKIP | {module} | {name} | {e}")
            _idx += 1
            return   # stay in "next", advance next frame

        _tick_cnt = 0
        _state    = "wait_open"

    # ── STATE: wait_open ─────────────────────────────────
    elif _state == "wait_open":
        _tick_cnt += 1
        if _tick_cnt >= TICKS_AFTER_OPEN:
            a      = assets[_idx]
            module = a["module"]
            name   = a["asset_name"]
            snapshot_staging()   # fresh snapshot just before trigger
            ok = send_print_command()
            if ok:
                unreal.log(f"  [TRIGGER] PrintAllAreaOfWidget → {name}")
            else:
                unreal.log_warning(f"  [NO WS] GraphPrinter not connected, skipping trigger")
            _tick_cnt = 0
            _state    = "wait_print"

    # ── STATE: wait_print ────────────────────────────────
    elif _state == "wait_print":
        _tick_cnt += 1
        if _tick_cnt >= TICKS_AFTER_PRINT:
            a      = assets[_idx]
            module = a["module"]
            name   = a["asset_name"]
            moved  = move_pngs_to_module(name, module)
            if moved > 0:
                _success += 1
                _log_lines.append(f"OK   | {module} | {name} | {moved} file(s)")
                unreal.log(f"  [OK] {moved} PNG(s) saved")
            else:
                _fail += 1
                _log_lines.append(f"WARN | {module} | {name} | no PNG found")
                unreal.log_warning(f"  [WARN] No PNG found — GraphPrinter may not be connected")

            _idx      += 1
            _tick_cnt  = 0
            _state     = "next"

def _finish():
    global _handle
    if _handle:
        unreal.unregister_slate_post_tick_callback(_handle)
        _handle = None

    # Write index
    idx_path = os.path.join(OUTPUT_ROOT.replace("/", "\\"), "_index.txt")
    with open(idx_path, "w", encoding="utf-8") as f:
        f.write("GASPALS Blueprint Screenshot Index\n")
        f.write(f"Generated : {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Total={_total}  OK={_success}  FAIL={_fail}\n")
        f.write("=" * 64 + "\n")
        f.write("\n".join(_log_lines))

    unreal.log("\n" + "=" * 56)
    unreal.log(f"[SS] DONE  OK={_success}  FAIL={_fail}/{_total}")
    unreal.log(f"[SS] Output : {OUTPUT_ROOT}")
    unreal.log(f"[SS] Index  : {idx_path}")
    unreal.log("=" * 56)

    try:
        import subprocess
        subprocess.Popen(["explorer", OUTPUT_ROOT.replace("/", "\\")])
    except Exception:
        pass

# ── Start ─────────────────────────────────────────────────
_handle = unreal.register_slate_post_tick_callback(_tick)

unreal.log("=" * 56)
unreal.log(f"[SS] Tick runner started — {_total} assets queued")
unreal.log(f"[SS] GraphPrinter should auto-connect (ini pre-configured)")
unreal.log(f"[SS] If not connected: Edit>ProjectSettings>Plugins>GraphPrinter Remote Control")
unreal.log(f"[SS]   Enable=True  URL=ws://127.0.0.1:3000/")
unreal.log("=" * 56)
