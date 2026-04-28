import unreal

try:
    rc_cls = unreal.load_class(None, "/Script/GraphPrinterRemoteControl.GraphPrinterRemoteControlSettings")
    if rc_cls:
        rc_cdo = unreal.get_default_object(rc_cls)
        unreal.log(f"[RC] CDO: {rc_cdo}")

        rc_cdo.set_editor_property("bEnableRemoteControl", True)
        rc_cdo.set_editor_property("ServerURL", "ws://127.0.0.1:3000/")
        unreal.log("[RC] Properties set (bEnableRemoteControl=True, ServerURL=ws://127.0.0.1:3000/)")

        # modify() + set_editor_properties triggers PostEditChangeProperty
        # which calls OnRemoteControlEnabled.Broadcast(ServerURL) in C++
        # causing GraphPrinter to actually connect to the WS server
        rc_cdo.modify()
        rc_cdo.set_editor_properties({
            "bEnableRemoteControl": True,
            "ServerURL": "ws://127.0.0.1:3000/"
        })
        unreal.log("[RC] Broadcast triggered — GraphPrinter should connect now")
    else:
        unreal.log_warning("[RC] Class not found")
except Exception as e:
    unreal.log_error(f"[RC] {e}")

unreal.log("[RC] DONE")
