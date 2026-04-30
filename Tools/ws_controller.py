"""
GraphPrinter JSON remote-control smoke test.

Run this outside UE, enable GraphPrinter Remote Control in the editor, then keep
the graph you want to test active. The script sends GraphOnly print requests
until one succeeds or the timeout expires, then verifies that every returned OK
PNG contains the GraphEditor text chunk.
"""

import argparse
import asyncio
import json
import os
import subprocess
import sys
import uuid

try:
    import websockets
except ModuleNotFoundError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "websockets"])
    import websockets


PROJECT_DIR = r"d:\UE\COLMM\GASPALS"
HOST = "127.0.0.1"
PORT = 3000
STAGING_DIR = os.path.join(PROJECT_DIR, "Saved", "Screenshots", "_staging")


def has_graph_editor_chunk(filename):
    try:
        with open(filename, "rb") as handle:
            return b"GraphEditor" in handle.read()
    except Exception:
        return False


async def run_once(timeout):
    os.makedirs(STAGING_DIR, exist_ok=True)
    connected = asyncio.Event()
    responses = {}
    client = {"socket": None}

    async def handler(websocket):
        client["socket"] = websocket
        print(f"[WS] GraphPrinter connected: {websocket.remote_address}")
        connected.set()
        try:
            async for message in websocket:
                print(f"[WS] recv: {message}")
                try:
                    response = json.loads(message)
                except json.JSONDecodeError:
                    continue
                request_id = response.get("RequestId")
                if request_id:
                    responses[request_id] = response
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            if client["socket"] is websocket:
                client["socket"] = None
                connected.clear()

    async with websockets.serve(handler, HOST, PORT):
        print(f"[WS] Listening on ws://{HOST}:{PORT}/")
        print("[WS] Enable GraphPrinter Remote Control in UE, then activate a graph tab.")
        deadline = asyncio.get_running_loop().time() + timeout
        attempt = 0
        last_result = None

        while asyncio.get_running_loop().time() < deadline:
            remaining = deadline - asyncio.get_running_loop().time()
            await asyncio.wait_for(connected.wait(), timeout=remaining)
            if client["socket"] is None:
                await asyncio.sleep(0.2)
                continue

            attempt += 1
            request_id = str(uuid.uuid4())
            request = {
                "RequestId": request_id,
                "Command": "PrintGraphModules",
                "TargetKind": "GraphOnly",
                "OutputDirectory": STAGING_DIR.replace("\\", "/"),
                "SplitMode": "SemanticModules",
                "MaxModuleNodes": 40,
                "MaxModulePixels": [6000, 6000],
                "RequireTextChunk": True,
            }

            await client["socket"].send(json.dumps(request))
            print(f"[CMD] Sent attempt={attempt}: {request}")

            response = None
            response_deadline = min(deadline, asyncio.get_running_loop().time() + 10.0)
            while asyncio.get_running_loop().time() < response_deadline:
                response = responses.get(request_id)
                if response:
                    break
                await asyncio.sleep(0.1)

            if response:
                status = response.get("Status")
                modules = response.get("Modules", [])
                ok_modules = [module for module in modules if module.get("Status") == "OK"]
                chunk_ok = all(
                    module.get("Filename") and has_graph_editor_chunk(module["Filename"])
                    for module in ok_modules
                )
                last_result = f"status={status} ok_modules={len(ok_modules)} total_modules={len(modules)} chunk={chunk_ok}"
                print(
                    f"[RESULT] attempt={attempt} {last_result}"
                )
                if status in ("Succeeded", "Partial") and ok_modules and chunk_ok:
                    return
            else:
                last_result = f"attempt={attempt} timed out waiting for response"
                print(f"[RESULT] {last_result}")

            await asyncio.sleep(1.0)

        raise TimeoutError(f"Active graph smoke failed before timeout. Last result: {last_result}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()
    asyncio.run(run_once(args.timeout))


if __name__ == "__main__":
    main()
