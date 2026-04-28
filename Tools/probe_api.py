import unreal, sys
attrs = [a for a in dir(unreal) if 'tick' in a.lower() or 'callback' in a.lower() or 'timer' in a.lower() or 'deferred' in a.lower()]
for a in attrs:
    unreal.log(f'API: {a}')
unreal.log('PROBE DONE')
