#!/usr/bin/env python3
"""Launch the actual generated deep-lab configurations through DAP."""
import argparse
import json
from pathlib import Path
import traceback
import lab
from test_workflows import Wire

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config',default=str(lab.HERE/'out/config.json'))
    args=p.parse_args()
    c=json.loads(Path(args.config).read_text())
    out=Path(c['out'])
    configs=json.loads((out/'lesson.code-workspace').read_text())['launch']['configurations']
    expected={'05':'CGObjCGNU.cpp','06':'GNUstepObjCRuntime.cpp','07':'runtime.c','08':'GSArray.m'}
    results=[]
    for launch in configs:
        key=launch['name'][:2]
        if key not in expected: continue
        w=Wire([launch['debugAdapterExecutable']],lab.environment(c),dap=True)
        try:
            w.request('initialize',{'adapterID':'lldb','linesStartAt1':True,'pathFormat':'path'})
            seq=w.send('launch',launch)
            w.event('initialized')
            w.request('configurationDone')
            w.response(seq)
            stop=w.event('stopped')['body']
            assert stop['reason']=='breakpoint',stop
            frames=w.request('stackTrace',{'threadId':stop['threadId']})['stackFrames']
            assert any(expected[key] in f.get('source',{}).get('path','') for f in frames),frames
            w.request('disconnect',{'terminateDebuggee':True})
            result={'name':launch['name'],'status':'PASS'}
        except Exception:
            result={'name':launch['name'],'status':'FAIL','error':traceback.format_exc()}
        finally:
            if w.process.poll() is None:
                try: w.request('disconnect',{'terminateDebuggee':True})
                except Exception: pass
            w.close()
            (out/'validation'/('workspace-'+key+'.log')).write_text(json.dumps(w.log,indent=2),encoding='utf-8')
        results.append(result)
        print(result['name'],result['status'],flush=True)
    (out/'validation/workspace-results.json').write_text(json.dumps(results,indent=2)+'\n')
    return int(any(r['status']=='FAIL' for r in results))
if __name__=='__main__': raise SystemExit(main())
