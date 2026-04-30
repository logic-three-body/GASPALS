# This runs on every UE editor startup (Content/Python/init_unreal.py)
import unreal, os

# Re-probe the RC settings every startup
try:
    rc_cls = unreal.load_class(None, "/Script/GraphPrinterRemoteControl.GraphPrinterRemoteControlSettings")
    rc_cdo = unreal.get_default_object(rc_cls) if rc_cls else None
    if rc_cdo:
        props = {p: str(getattr(rc_cdo, p, "N/A")) for p in dir(rc_cdo) if not p.startswith("_") and not callable(getattr(rc_cdo, p, None))}
        for k,v in props.items():
            unreal.log(f"[init] RC prop: {k} = {v}")
except Exception as e:
    unreal.log(f"[init] RC probe: {e}")
