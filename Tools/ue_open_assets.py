"""
GASPALS GraphPrinter batch export.

Runs inside the Unreal Editor. The script opens each target asset, sends a JSON
GraphPrinter remote-control request, waits for a per-request response, validates
that successful PNGs contain the GraphEditor text chunk, then moves them into the
per-module output tree.
"""

import asyncio
import glob
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import uuid

import unreal


PROJECT_SAVED = unreal.Paths.project_saved_dir().replace("\\", "/")
PROJECT_DIR = unreal.Paths.project_dir().replace("\\", "/").rstrip("/")
OUTPUT_ROOT = PROJECT_SAVED + "Screenshots/Blueprints"
STAGING_DIR = PROJECT_SAVED + "Screenshots/_staging"
ASSET_LIST = OUTPUT_ROOT + "/_asset_list.json"
QA_SUMMARY_PATH = os.path.join(PROJECT_DIR.replace("/", "\\"), "Docs", "GraphPrinter_QA_2026-04-29.md")

WS_HOST = "127.0.0.1"
WS_PORT = 3000
WS_URL = f"ws://{WS_HOST}:{WS_PORT}/"

TICKS_AFTER_OPEN = 200
TICKS_WAIT_FOR_WS = 300
TICKS_RESPONSE_TIMEOUT = 7200

ASSET_FILTER = os.environ.get("GPBATCH_FILTER", "").strip()
ASSET_START_INDEX = int(os.environ.get("GPBATCH_START_INDEX", "0") or "0")
ASSET_LIMIT = int(os.environ.get("GPBATCH_LIMIT", "0") or "0")
QUIT_ON_FINISH = os.environ.get("GPBATCH_QUIT_ON_FINISH", "0") == "1"

TARGET_CLASSES = ["Blueprint", "AnimBlueprint", "WidgetBlueprint"]

MODULE_MAP = [
    ("/GASPALS/Blueprints/AnimNotifies", "02_AnimNotifies"),
    ("/GASPALS/Blueprints/Cameras", "07_Components_Cameras"),
    ("/GASPALS/Blueprints/Components", "07_Components_Cameras"),
    ("/GASPALS/Blueprints/Data", "07_Components_Cameras"),
    ("/GASPALS/Blueprints/RetargetedCharacters", "03_RetargetedCharacters"),
    ("/GASPALS/Blueprints", "01_Core"),
    ("/GASPALS/Characters", "06_Characters_Rigs"),
    ("/GASPALS/MetaHumans", "05_MetaHumans"),
    ("/GASPALS/OverlaySystem/Overlays/Bases", "04_OverlaySystem/Bases"),
    ("/GASPALS/OverlaySystem/Overlays/Poses", "04_OverlaySystem/Poses"),
    ("/GASPALS/OverlaySystem", "04_OverlaySystem"),
    ("/GASPALS/Widgets", "08_Widgets"),
    ("/GASPALS/Audio", "09_Audio"),
]


def module_for_package(package_name):
    for prefix, folder in MODULE_MAP:
        if package_name.startswith(prefix):
            return folder
    return "00_Other"


def ensure_dir(path):
    os.makedirs(path.replace("/", "\\"), exist_ok=True)


def has_graph_editor_chunk(filename):
    try:
        with open(filename, "rb") as handle:
            return b"GraphEditor" in handle.read()
    except Exception:
        return False


def normalize_path(path):
    return os.path.abspath(path.replace("/", "\\"))


def clean_staging_dir():
    ensure_dir(STAGING_DIR)
    pattern = normalize_path(STAGING_DIR) + "\\**\\*.png"
    for filename in glob.glob(pattern, recursive=True):
        try:
            os.remove(filename)
        except Exception:
            pass


def move_validated_png(filename, asset_name, module_name):
    source = normalize_path(filename)
    if not os.path.exists(source):
        raise RuntimeError(f"reported file does not exist: {source}")
    if not has_graph_editor_chunk(source):
        raise RuntimeError(f"reported PNG lacks GraphEditor text chunk: {source}")

    dest_dir = os.path.join(normalize_path(OUTPUT_ROOT), module_name, asset_name)
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, os.path.basename(source))
    if os.path.exists(dest):
        os.remove(dest)
    shutil.move(source, dest)
    return dest


def validate_and_move_module(module, asset_name, module_name):
    filename = module.get("Filename", "")
    moved_to = move_validated_png(filename, asset_name, module_name)
    moved_module = dict(module)
    moved_module["SourceFilename"] = filename
    moved_module["Filename"] = moved_to
    return moved_module


def collect_assets():
    registry = unreal.AssetRegistryHelpers.get_asset_registry()
    registry.search_all_assets(True)

    seen = set()
    collected = []
    for class_name in TARGET_CLASSES:
        try:
            asset_filter = unreal.ARFilter(
                package_paths=["/GASPALS"],
                recursive_paths=True,
                class_paths=[unreal.TopLevelAssetPath("/Script/Engine", class_name)],
            )
        except Exception:
            asset_filter = unreal.ARFilter(
                package_paths=["/GASPALS"],
                recursive_paths=True,
                class_names=[class_name],
            )

        for asset in registry.get_assets(asset_filter):
            package_name = str(asset.package_name)
            if package_name in seen:
                continue
            seen.add(package_name)
            collected.append(
                {
                    "package_name": package_name,
                    "asset_name": str(asset.asset_name),
                    "module": module_for_package(package_name),
                }
            )

    for original_index, asset in enumerate(collected):
        asset["original_index"] = original_index
    collected.sort(key=lambda item: item["package_name"])
    for sorted_index, asset in enumerate(collected):
        asset["sorted_index"] = sorted_index

    with open(ASSET_LIST, "w", encoding="utf-8") as handle:
        json.dump(collected, handle, indent=2, ensure_ascii=False)
    return collected


ensure_dir(OUTPUT_ROOT)
ensure_dir(STAGING_DIR)
clean_staging_dir()
assets = collect_assets()
if ASSET_FILTER:
    assets = [
        asset
        for asset in assets
        if ASSET_FILTER.lower() in asset["asset_name"].lower()
        or ASSET_FILTER.lower() in asset["package_name"].lower()
    ]
if ASSET_START_INDEX > 0:
    assets = assets[ASSET_START_INDEX:]
if ASSET_LIMIT > 0:
    assets = assets[:ASSET_LIMIT]
unreal.log(f"[GPBatch] {len(assets)} assets collected -> {ASSET_LIST}")


_ws_client = None
_ws_loop = None
_ws_ready = threading.Event()
_response_lock = threading.Lock()
_responses = {}
_opened_assets = []


def _store_response(response):
    request_id = response.get("RequestId")
    if not request_id:
        return
    with _response_lock:
        _responses[request_id] = response


def _pop_response(request_id):
    with _response_lock:
        return _responses.pop(request_id, None)


async def _ws_handler(websocket):
    global _ws_client
    _ws_client = websocket
    unreal.log("[GPBatch][WS] GraphPrinter connected")
    try:
        async for message in websocket:
            try:
                response = json.loads(message)
                _store_response(response)
                unreal.log(f"[GPBatch][WS] response {response.get('RequestId')} {response.get('Status')}")
            except Exception as exc:
                unreal.log_warning(f"[GPBatch][WS] ignored non-JSON message: {exc}")
    except Exception as exc:
        unreal.log_warning(f"[GPBatch][WS] connection closed: {exc}")
    finally:
        _ws_client = None
        unreal.log("[GPBatch][WS] GraphPrinter disconnected")


def _ws_thread_main():
    global _ws_loop
    try:
        import websockets
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "websockets"])
        import websockets

    async def serve_forever():
        async with websockets.serve(_ws_handler, WS_HOST, WS_PORT):
            unreal.log(f"[GPBatch][WS] Server listening on {WS_URL}")
            _ws_ready.set()
            await asyncio.Future()

    _ws_loop = asyncio.new_event_loop()
    asyncio.set_event_loop(_ws_loop)
    _ws_loop.run_until_complete(serve_forever())


threading.Thread(target=_ws_thread_main, daemon=True).start()
_ws_ready.wait(timeout=8)


def enable_remote_control():
    try:
        rc_cls = unreal.load_class(None, "/Script/GraphPrinterRemoteControl.GraphPrinterRemoteControlSettings")
        rc_cdo = unreal.get_default_object(rc_cls) if rc_cls else None
        if not rc_cdo:
            unreal.log_warning("[GPBatch][WS] GraphPrinterRemoteControlSettings class not found")
            return

        rc_cdo.modify()
        rc_cdo.set_editor_properties({"bEnableRemoteControl": False, "ServerURL": WS_URL})
        rc_cdo.set_editor_properties({"bEnableRemoteControl": True})
        if hasattr(rc_cdo, "reconnect"):
            rc_cdo.reconnect()
        unreal.log(f"[GPBatch][WS] Remote control enabled: {WS_URL}")
    except Exception as exc:
        unreal.log_warning(f"[GPBatch][WS] RC enable failed: {exc}")


enable_remote_control()


def send_print_request(asset):
    if _ws_client is None or _ws_loop is None:
        return None

    request_id = str(uuid.uuid4())
    payload = {
        "RequestId": request_id,
        "Command": "PrintGraphModules",
        "TargetKind": "GraphOnly",
        "PackageName": asset["package_name"],
        "OutputDirectory": STAGING_DIR,
        "SplitMode": "SemanticModules",
        "MaxModuleNodes": 40,
        "MaxModulePixels": [6000, 6000],
        "RequireTextChunk": True,
        "AssetName": asset["asset_name"],
    }

    async def send():
        await _ws_client.send(json.dumps(payload))

    future = asyncio.run_coroutine_threadsafe(send(), _ws_loop)
    try:
        future.result(timeout=2)
    except Exception as exc:
        unreal.log_warning(f"[GPBatch][WS] failed to send request: {exc}")
        return None
    return request_id


editor_subsystem = unreal.get_editor_subsystem(unreal.AssetEditorSubsystem)


def close_opened_asset_editors():
    global _opened_assets
    remaining = []
    for asset in _opened_assets:
        try:
            editor_subsystem.close_all_editors_for_asset(asset)
        except Exception as exc:
            remaining.append(asset)
            unreal.log_warning(f"[GPBatch] close_all_editors_for_asset failed: {exc}")
    _opened_assets = remaining

_state = "next"
_idx = 0
_tick_count = 0
_active_request_id = None
_entries = []
_ok = 0
_skipped = 0
_failed = 0
_handle = None
_quit_handle = None
_quit_tick_count = 0
_finished = False


def _diagnostic_stage(module):
    return (module.get("Diagnostics") or {}).get("FailureStage", "")


def _recovery_reason(module):
    recovery = module.get("Recovery") or {}
    return recovery.get("FailureReason") or _diagnostic_stage(module) or module.get("Error", "")


def _known_unrecoverable_modules(entries):
    known = []
    for entry in entries:
        for module in entry.get("modules", []):
            if module.get("Status") != "FAIL":
                continue
            known.append((entry, module, _recovery_reason(module)))
    return known


def _write_qa_summary(summary, known_unrecoverable):
    ensure_dir(os.path.dirname(QA_SUMMARY_PATH))
    with open(QA_SUMMARY_PATH, "w", encoding="utf-8") as handle:
        handle.write("# GraphPrinter QA Summary - 2026-04-29\n\n")
        handle.write(f"Generated: {summary['generated']}\n\n")
        handle.write("## Counts\n")
        handle.write(f"- Assets: total={summary['total']} ok={summary['ok']} skip={summary['skipped']} fail={summary['failed']}\n")
        handle.write(
            f"- Modules: ok={summary['module_ok']} skip={summary['module_skipped']} fail={summary['module_failed']}\n\n"
        )

        handle.write("## Validation Commands\n")
        handle.write(
            "- Build: `D:\\UE\\UnrealEngine_Animation_Tech\\Engine\\Build\\BatchFiles\\Build.bat "
            "GASPALSEditor Win64 Development -Project=\"D:\\UE\\COLMM\\GASPALS\\GASPALS.uproject\"`\n"
        )
        handle.write("- Targeted: `$env:GPBATCH_FILTER='ABP_SandboxCharacter'; .\\Tools\\setup_and_launch.ps1`\n")
        handle.write("- Targeted: `$env:GPBATCH_FILTER='ABP_OverlayPose_Base'; .\\Tools\\setup_and_launch.ps1`\n")
        handle.write("- Targeted: `$env:GPBATCH_FILTER='ALI_Overlay'; .\\Tools\\setup_and_launch.ps1`\n")
        handle.write("- Full: clear `GPBATCH_FILTER`, then run `.\\Tools\\setup_and_launch.ps1`\n")
        handle.write("- Active graph smoke: `python Tools\\ws_controller.py --timeout 120`\n\n")

        handle.write("## Log Conclusions To Check\n")
        handle.write("- No `Fatal error` in `Saved\\Logs\\batch_graphprinter.log`.\n")
        handle.write("- No `Traceback` in `Saved\\Logs\\batch_graphprinter.log`.\n")
        handle.write("- Every `OK` module PNG exists and contains the `GraphEditor` text chunk.\n")
        handle.write("- `Tools\\asset_list.json` remains untouched; generated list is `Saved\\Screenshots\\Blueprints\\_asset_list.json`.\n\n")

        handle.write("## Known Unrecoverable Modules\n")
        if not known_unrecoverable:
            handle.write("- None in the current index.\n")
        else:
            for entry, module, reason in known_unrecoverable:
                title = module.get("ModuleTitle") or module.get("GraphName") or module.get("ModuleId")
                handle.write(
                    f"- {entry['module']} | {entry['asset_name']} | {module.get('GraphName', '')} | "
                    f"{module.get('ModuleId', '')} | {title} | {reason}\n"
                )

        handle.write("\n## Assets With Failures\n")
        failed_entries = [entry for entry in summary["entries"] if entry.get("status") == "FAIL"]
        if not failed_entries:
            handle.write("- None in the current index.\n")
        else:
            for entry in failed_entries:
                handle.write(f"- {entry['module']} | {entry['asset_name']} | {entry['detail']}\n")


def _record(asset, status, detail, filename="", modules=None, response_summary=None):
    _entries.append(
        {
            "status": status,
            "module": asset["module"],
            "asset_name": asset["asset_name"],
            "package_name": asset["package_name"],
            "original_index": asset.get("original_index"),
            "sorted_index": asset.get("sorted_index"),
            "filename": filename,
            "detail": detail,
            "modules": modules or [],
            "summary": response_summary or {},
        }
    )


def _write_index():
    index_json = os.path.join(normalize_path(OUTPUT_ROOT), "_index.json")
    index_txt = os.path.join(normalize_path(OUTPUT_ROOT), "_index.txt")
    summary = {
        "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "total": len(assets),
        "ok": _ok,
        "skipped": _skipped,
        "failed": _failed,
        "module_ok": sum(1 for entry in _entries for module in entry.get("modules", []) if module.get("Status") == "OK"),
        "module_skipped": sum(1 for entry in _entries for module in entry.get("modules", []) if module.get("Status") == "SKIP_NO_GRAPH"),
        "module_failed": sum(1 for entry in _entries for module in entry.get("modules", []) if module.get("Status") == "FAIL"),
        "entries": _entries,
    }
    known_unrecoverable = _known_unrecoverable_modules(_entries)

    with open(index_json, "w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, ensure_ascii=False)

    with open(index_txt, "w", encoding="utf-8") as handle:
        handle.write("GASPALS GraphPrinter Batch Index\n")
        handle.write(f"Generated: {summary['generated']}\n")
        handle.write(f"Total={summary['total']} OK={_ok} SKIP={_skipped} FAIL={_failed}\n")
        handle.write(
            f"Modules OK={summary['module_ok']} SKIP={summary['module_skipped']} FAIL={summary['module_failed']}\n"
        )
        handle.write("=" * 80 + "\n")
        for entry in _entries:
            handle.write(
                f"{entry['status']:<12} | {entry['module']:<34} | {entry['asset_name']} | {entry['detail']}\n"
            )
            for module in entry.get("modules", []):
                diagnostic_stage = _diagnostic_stage(module)
                diagnostic_suffix = f" | diag={diagnostic_stage}" if diagnostic_stage else ""
                recovery = module.get("Recovery") or {}
                if recovery.get("bRecovered"):
                    diagnostic_suffix += (
                        f" | recovered_from={recovery.get('OriginalGraphName', '')}"
                        f" via={recovery.get('ContainerGraphName', '')}"
                    )
                handle.write(
                    f"  - {module.get('Status', ''):<12} | {module.get('GraphName', '')} | "
                    f"{module.get('ModuleId', '')} | nodes={module.get('NodeCount', 0)} | "
                    f"{module.get('Filename', '') or module.get('Error', '')}{diagnostic_suffix}\n"
                )
        handle.write("\nKnown unrecoverable modules\n")
        if not known_unrecoverable:
            handle.write("  - None\n")
        else:
            for entry, module, reason in known_unrecoverable:
                handle.write(
                    f"  - {entry['module']} | {entry['asset_name']} | {module.get('GraphName', '')} | "
                    f"{module.get('ModuleId', '')} | {reason}\n"
                )

    _write_qa_summary(summary, known_unrecoverable)

    return index_txt


def _finish():
    global _handle, _finished
    if _finished:
        return
    _finished = True
    if _handle:
        unreal.unregister_slate_post_tick_callback(_handle)
        _handle = None

    index_txt = _write_index()

    unreal.log("=" * 60)
    unreal.log(f"[GPBatch] DONE OK={_ok} SKIP={_skipped} FAIL={_failed}/{len(assets)}")
    unreal.log(f"[GPBatch] Output: {OUTPUT_ROOT}")
    unreal.log(f"[GPBatch] Index: {index_txt}")
    unreal.log("=" * 60)
    if QUIT_ON_FINISH:
        _schedule_quit()


def _schedule_quit():
    global _quit_handle, _quit_tick_count
    close_opened_asset_editors()
    _quit_tick_count = 0
    _quit_handle = unreal.register_slate_post_tick_callback(_quit_after_close)


def _quit_after_close(_delta):
    global _quit_handle, _quit_tick_count
    _quit_tick_count += 1
    if _quit_tick_count < 60:
        return
    if _quit_handle:
        unreal.unregister_slate_post_tick_callback(_quit_handle)
        _quit_handle = None
    unreal.SystemLibrary.execute_console_command(None, "QUIT_EDITOR")


def _tick(_delta):
    global _state, _idx, _tick_count, _active_request_id, _ok, _skipped, _failed

    if _idx >= len(assets):
        _finish()
        return

    asset = assets[_idx]
    asset_name = asset["asset_name"]
    module_name = asset["module"]

    if _state == "next":
        unreal.log(f"[GPBatch] [{_idx + 1}/{len(assets)}] {asset_name} ({module_name})")
        try:
            close_opened_asset_editors()
            loaded_asset = unreal.load_asset(asset["package_name"])
            if loaded_asset is None:
                raise RuntimeError("load_asset returned None")
            _opened_assets.append(loaded_asset)
            editor_subsystem.open_editor_for_assets([loaded_asset])
        except Exception as exc:
            _failed += 1
            _record(asset, "FAIL", f"open failed: {exc}")
            _write_index()
            unreal.log_warning(f"[GPBatch] open failed: {exc}")
            _idx += 1
            return

        _tick_count = 0
        _state = "wait_open"
        return

    if _state == "wait_open":
        _tick_count += 1
        if _tick_count < TICKS_AFTER_OPEN:
            return
        if _ws_client is None:
            if _tick_count < TICKS_AFTER_OPEN + TICKS_WAIT_FOR_WS:
                return
            _failed += 1
            _record(asset, "FAIL", "GraphPrinter WebSocket did not connect")
            _write_index()
            unreal.log_warning("[GPBatch] GraphPrinter WebSocket did not connect")
            _idx += 1
            _tick_count = 0
            _state = "next"
            return

        clean_staging_dir()
        _active_request_id = send_print_request(asset)
        if not _active_request_id:
            _failed += 1
            _record(asset, "FAIL", "failed to send print request")
            _write_index()
            _idx += 1
            _tick_count = 0
            _state = "next"
            return

        unreal.log(f"[GPBatch] request {_active_request_id} -> {asset_name}")
        _tick_count = 0
        _state = "wait_response"
        return

    if _state == "wait_response":
        _tick_count += 1
        response = _pop_response(_active_request_id)
        if response is None:
            if _tick_count < TICKS_RESPONSE_TIMEOUT:
                return
            _failed += 1
            _record(asset, "FAIL", f"response timeout: {_active_request_id}")
            _write_index()
            unreal.log_warning(f"[GPBatch] response timeout: {_active_request_id}")
            _idx += 1
            _tick_count = 0
            _active_request_id = None
            _state = "next"
            return

        status = response.get("Status", "Failed")
        response_summary = response.get("Summary", {})
        response_modules = response.get("Modules", [])

        moved_modules = []
        module_failures = []
        module_skips = []
        for module in response_modules:
            module_status = module.get("Status", "FAIL")
            if module_status == "OK":
                try:
                    moved_modules.append(validate_and_move_module(module, asset_name, module_name))
                except Exception as exc:
                    failed_module = dict(module)
                    failed_module["Status"] = "FAIL"
                    failed_module["Error"] = str(exc)
                    moved_modules.append(failed_module)
                    module_failures.append(str(exc))
            elif module_status == "SKIP_NO_GRAPH":
                moved_modules.append(dict(module))
                module_skips.append(module.get("Error", "SKIP_NO_GRAPH"))
            else:
                moved_modules.append(dict(module))
                module_failures.append(module.get("Error", "remote module print failed"))

        if moved_modules and not module_failures and any(module.get("Status") == "OK" for module in moved_modules):
            _ok += 1
            detail = f"{len([m for m in moved_modules if m.get('Status') == 'OK'])} module PNG(s)"
            first_file = next((m.get("Filename", "") for m in moved_modules if m.get("Filename")), "")
            _record(asset, "OK", detail, first_file, moved_modules, response_summary)
            unreal.log(f"[GPBatch] OK {asset_name}: {detail}")
        elif moved_modules and module_skips and not module_failures and not any(module.get("Status") == "OK" for module in moved_modules):
            _skipped += 1
            detail = "; ".join(module_skips) or "SKIP_NO_GRAPH"
            _record(asset, "SKIP_NO_GRAPH", detail, modules=moved_modules, response_summary=response_summary)
            unreal.log_warning(f"[GPBatch] SKIP {asset_name}: {detail}")
        else:
            _failed += 1
            detail = "; ".join(module_failures) or response.get("Error", "") or f"remote status: {status}"
            _record(asset, "FAIL", detail, modules=moved_modules, response_summary=response_summary)
            unreal.log_warning(f"[GPBatch] FAIL {asset_name}: {detail}")

        clean_staging_dir()
        _write_index()
        _idx += 1
        _tick_count = 0
        _active_request_id = None
        _state = "next"


_handle = unreal.register_slate_post_tick_callback(_tick)

unreal.log("=" * 60)
unreal.log(f"[GPBatch] Tick runner started: {len(assets)} assets queued")
unreal.log(f"[GPBatch] WebSocket: {WS_URL}")
unreal.log(f"[GPBatch] Staging: {STAGING_DIR}")
unreal.log(f"[GPBatch] Output: {OUTPUT_ROOT}")
unreal.log("=" * 60)
