"""
GASPALS Blueprint Batch Screenshot - WebSocket Controller
=========================================================
运行方式:
  1. 先运行此脚本 (外部 Python): python Tools/ws_controller.py
  2. 再在 UE 编辑器中启动 GASPALS.uproject
  3. 在 UE 编辑器里: Edit > Project Settings > Plugins > GraphPrinter Remote Control
     - 勾选 Enable Remote Control
     - Server URL: ws://127.0.0.1:3000/
  4. 连接后本脚本自动控制截图流程

依赖: pip install websockets
"""

import asyncio
import websockets
import os
import json
import time
import subprocess
import sys

# ──────────────────────────────────────────────
#  CONFIG
# ──────────────────────────────────────────────
HOST = "127.0.0.1"
PORT = 3000
OPEN_WAIT   = 4.0   # seconds to wait after sending "open asset" command
EXPORT_WAIT = 5.0   # seconds to wait after triggering screenshot

OUTPUT_ROOT = r"d:\UE\COLMM\GASPALS\Saved\Screenshots\Blueprints"

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

def get_module_folder(pkg_path: str) -> str:
    for prefix, folder in MODULE_MAP:
        if pkg_path.startswith(prefix):
            return folder
    return "00_Other"


# ──────────────────────────────────────────────
#  MAIN SERVER LOOP
# ──────────────────────────────────────────────

connected_client = None
log_lines = []

async def handler(websocket):
    global connected_client
    connected_client = websocket
    print(f"[WS] GraphPrinter connected: {websocket.remote_address}")
    try:
        async for msg in websocket:
            print(f"[WS] recv: {msg}")
    except Exception as e:
        print(f"[WS] connection closed: {e}")
    finally:
        connected_client = None
        print("[WS] GraphPrinter disconnected")


async def send_command(cmd_name: str):
    """Send UnrealEngine-GraphPrinter-<CommandName> to GraphPrinter."""
    if connected_client is None:
        print(f"[CMD] No client connected, cannot send: {cmd_name}")
        return False
    msg = f"UnrealEngine-GraphPrinter-{cmd_name}"
    await connected_client.send(msg)
    print(f"[CMD] Sent: {msg}")
    return True


async def run_batch():
    """Main batch processing loop — runs after GraphPrinter connects."""
    print(f"\n[BATCH] Starting batch screenshot of GASPALS blueprints")
    print(f"[BATCH] Output root: {OUTPUT_ROOT}")
    os.makedirs(OUTPUT_ROOT, exist_ok=True)

    # Load asset list from the pre-generated JSON
    asset_list_path = r"d:\UE\COLMM\GASPALS\Tools\asset_list.json"
    if not os.path.exists(asset_list_path):
        print(f"[ERR] asset_list.json not found. Run ue_list_assets.py first.")
        return

    with open(asset_list_path, "r", encoding="utf-8") as f:
        assets = json.load(f)

    total = len(assets)
    success = 0
    fail = 0
    print(f"[BATCH] {total} assets to process\n")

    for idx, asset in enumerate(assets):
        pkg_path = asset["package_name"]
        name     = asset["asset_name"]
        module   = get_module_folder(pkg_path)
        out_dir  = os.path.join(OUTPUT_ROOT, module, name)
        os.makedirs(out_dir, exist_ok=True)

        print(f"[{idx+1}/{total}] {name}  ({module})")

        # Send PrintAllAreaOfWidget command
        ok = await send_command("PrintAllAreaOfWidget")
        if ok:
            await asyncio.sleep(EXPORT_WAIT)
            # Check if a file was created
            pngs = [f for f in os.listdir(out_dir) if f.endswith(".png")]
            if pngs:
                print(f"  [OK] {len(pngs)} file(s) in {out_dir}")
                success += 1
                log_lines.append(f"OK   | {module} | {name}")
            else:
                # GraphPrinter saves to its own default dir — move the latest png
                latest = find_latest_png(r"d:\UE\COLMM\GASPALS\Saved\Screenshots\Editor")
                if not latest:
                    latest = find_latest_png(r"d:\UE\UnrealEngine_Animation_Tech\Saved\Screenshots")
                if latest and (time.time() - os.path.getmtime(latest)) < 10:
                    dest = os.path.join(out_dir, os.path.basename(latest))
                    os.rename(latest, dest)
                    print(f"  [MOVED] → {dest}")
                    success += 1
                    log_lines.append(f"OK   | {module} | {name} | moved")
                else:
                    print(f"  [WARN] No PNG found after screenshot command")
                    fail += 1
                    log_lines.append(f"WARN | {module} | {name} | no output")
        else:
            fail += 1
            log_lines.append(f"FAIL | {module} | {name} | no WS client")

    # Write index
    idx_path = os.path.join(OUTPUT_ROOT, "_index.txt")
    with open(idx_path, "w", encoding="utf-8") as f:
        f.write("GASPALS Blueprint Screenshot Index\n")
        f.write(f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Total={total}  OK={success}  FAIL={fail}\n")
        f.write("=" * 60 + "\n")
        f.write("\n".join(log_lines))

    print(f"\n[BATCH] DONE — OK={success}  FAIL={fail}/{total}")
    print(f"[BATCH] Index: {idx_path}")
    os.startfile(OUTPUT_ROOT)


def find_latest_png(directory: str):
    if not os.path.exists(directory):
        return None
    pngs = []
    for root, _, files in os.walk(directory):
        for f in files:
            if f.endswith(".png"):
                pngs.append(os.path.join(root, f))
    if not pngs:
        return None
    return max(pngs, key=os.path.getmtime)


async def main():
    print(f"[WS] Starting WebSocket server on ws://{HOST}:{PORT}/")
    print(f"[WS] Waiting for GraphPrinter to connect...")
    print(f"[WS] In UE: Edit > Project Settings > Plugins > GraphPrinter Remote Control")
    print(f"[WS]   Enable Remote Control = True")
    print(f"[WS]   Server URL = ws://127.0.0.1:3000/\n")

    async with websockets.serve(handler, HOST, PORT):
        # Wait for connection
        while connected_client is None:
            await asyncio.sleep(0.5)

        print("[WS] Client connected! Starting batch in 3s...")
        await asyncio.sleep(3)
        await run_batch()


if __name__ == "__main__":
    asyncio.run(main())
