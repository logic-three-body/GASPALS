import unreal


WS_URL = "ws://127.0.0.1:3000/"

try:
    rc_cls = unreal.load_class(None, "/Script/GraphPrinterRemoteControl.GraphPrinterRemoteControlSettings")
    rc_cdo = unreal.get_default_object(rc_cls) if rc_cls else None
    if not rc_cdo:
        unreal.log_warning("[RC] GraphPrinterRemoteControlSettings class not found")
    else:
        rc_cdo.modify()
        rc_cdo.set_editor_properties({"bEnableRemoteControl": False, "ServerURL": WS_URL})
        rc_cdo.set_editor_properties({"bEnableRemoteControl": True})
        if hasattr(rc_cdo, "reconnect"):
            rc_cdo.reconnect()
        unreal.log(f"[RC] GraphPrinter remote control enabled: {WS_URL}")
except Exception as exc:
    unreal.log_error(f"[RC] {exc}")
