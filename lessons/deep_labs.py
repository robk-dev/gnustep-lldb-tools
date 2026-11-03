#!/usr/bin/env python3
"""Run and record breakpoint evidence in Clang, LLDB, libobjc2 and Foundation."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import lab

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config',default=str(lab.HERE/'out/config.json'))
    p.add_argument('--only',choices=['clang','lldb','runtime','base'])
    a=p.parse_args()
    c=json.loads(Path(a.config).read_text())
    out=Path(c['out'])
    env=lab.environment(c)
    inner=out/'inner.lldb'
    cases={
      'clang': (lab.executable(c,'clang'),
        ['-cc1','-x','objective-c','-triple','x86_64-pc-windows-msvc' if lab.WIN else 'x86_64-unknown-linux-gnu',
         '-fobjc-runtime=gnustep-2.0','-emit-llvm','-o',str(out/'compiler.ll'),str(lab.HERE/'fixtures/compiler.m')],
        ['breakpoint set -f CGObjCGNU.cpp -p "return new CGObjCGNUstep2"','run','frame info','thread backtrace -c 6'], 'CGObjCGNU.cpp'),
      'lldb': (lab.executable(c,'lldb'), ['--no-lldbinit','-b','-s',str(inner),'--',str(out/('counter'+lab.SUFFIX))],
        ['breakpoint set -n lldb_private::GNUstepObjCRuntime::GetDynamicTypeAndAddress','run','frame info','thread backtrace -c 6'], 'GNUstepObjCRuntime.cpp'),
      'runtime': (str(out/('counter'+lab.SUFFIX)), [],
        ['breakpoint set -n class_createInstance','run','frame info','thread backtrace -c 6'], 'class_createInstance'),
      'base': (str(out/'foundation'/('foundation'+lab.SUFFIX)), [],
        ['breakpoint set -n "-[GSArray objectAtIndex:]"','run','frame info','thread backtrace -c 6'], 'objectAtIndex:'),
    }
    results=[]
    for name,(program,args,commands,expected) in cases.items():
        if a.only and name!=a.only: continue
        command=[lab.executable(c,'lldb'),'--no-lldbinit','-b']
        for cmd in commands: command+=['-o',cmd]
        command+=['-o','process kill','--',program,*args]
        launch_env=dict(env)
        if lab.WIN and name=='base': launch_env['PATH']=str(Path(c['base'])/'bin')+os.pathsep+env['PATH']
        r=subprocess.run(command,env=launch_env,capture_output=True,text=True,timeout=180)
        output=r.stdout+r.stderr
        (out/'validation').mkdir(exist_ok=True)
        (out/'validation'/('deep-'+name+'.log')).write_text(output,encoding='utf-8')
        passed=r.returncode==0 and 'stop reason = breakpoint' in output and expected in output
        results.append({'name':name,'status':'PASS' if passed else 'FAIL'})
        print(name,results[-1]['status'],flush=True)
    report=out/'validation/deep-results.json'
    if a.only and report.exists():
        previous=json.loads(report.read_text())
        results=[r for r in previous if r['name']!=a.only]+results
    report.write_text(json.dumps(results,indent=2)+'\n')
    return int(any(r['status']=='FAIL' for r in results))
if __name__=='__main__': raise SystemExit(main())
