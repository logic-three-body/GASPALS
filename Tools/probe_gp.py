import unreal

# Find GraphPrinter exposed classes
gp_things = [a for a in dir(unreal) if "graph" in a.lower() or "printer" in a.lower() or "widget_printer" in a.lower()]
for t in gp_things:
    unreal.log(f"GP: {t}")

# Try to call PrintAllAreaOfWidget directly via command bindings
try:
    # Look for the command function
    unreal.log("Trying InputChord...")
    unreal.SystemLibrary.execute_console_command(None, "GraphPrinter PrintAllAreaOfWidget")
except Exception as e:
    unreal.log(f"err1: {e}")

# Find WidgetPrinterSettings correct property names
try:
    cls = unreal.load_class(None, "/Script/WidgetPrinter.WidgetPrinterSettings")
    if cls:
        cdo = unreal.get_default_object(cls)
        props = [p for p in dir(cdo) if not p.startswith("_")]
        for p in props:
            if "dir" in p.lower() or "output" in p.lower() or "path" in p.lower():
                unreal.log(f"PROP: {p} = {getattr(cdo, p, '?')}")
except Exception as e:
    unreal.log(f"err2: {e}")

unreal.log("PROBE2 DONE")
