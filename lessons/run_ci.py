#!/usr/bin/env python3
"""Runner entry point for an already provisioned GNUstep/LLVM build."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import lab

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--config',default=str(lab.HERE/'out/config.json'))
    p.add_argument('--llvm-revision',required=True)
    p.add_argument('--deep',action='store_true',help='Also validate generated debugger/compiler/library source launches (requires their debug symbols).')
    a=p.parse_args()
    c=json.loads(Path(a.config).read_text())
    revision=subprocess.check_output(['git','-C',c['llvm'],'rev-parse','HEAD'],text=True).strip()
    if revision!=a.llvm_revision:
        p.error(f'Expected exact LLVM revision {a.llvm_revision}; found {revision}')
    dest=Path(c['out'])/'validation'; dest.mkdir(exist_ok=True)
    env=lab.environment(c)
    if lab.WIN:
        git=shutil.which('git')
        unix_tools=Path(git).parent.parent/'usr/bin' if git else None
        if not unix_tools or not (unix_tools/'cp.exe').exists():
            p.error('LLVM API tests need Git for Windows usr/bin tools (cp, dirname, pwd). Install Git or configure PATH.')
        env['PATH']=str(unix_tools)+__import__('os').pathsep+env['PATH']
    meta={'llvm_revision':revision,'config':c,'versions':{},'sha256':{}}
    for name in ['clang','lldb','lldb-dap','lldb-mcp']:
        binary=lab.executable(c,name)
        meta['versions'][name]=subprocess.check_output([binary,'--version'],env=env,text=True,stderr=subprocess.STDOUT,timeout=30)
        with open(binary,'rb') as f: meta['sha256'][name]=hashlib.file_digest(f,'sha256').hexdigest()
    libraries=[]
    if lab.WIN:
        libraries=[Path(c['prefix'])/'lib/objc.dll',*list((Path(c['base'])/'bin').glob('gnustep-base*.dll'))]
    else:
        libraries=[Path(c['prefix'])/'lib/libobjc.so',Path(c['base'])/'lib/libgnustep-base.so']
    for library in libraries:
        if library.exists():
            with library.open('rb') as f: meta['sha256'][str(library)]=hashlib.file_digest(f,'sha256').hexdigest()
    cache=Path(c['build'])/'CMakeCache.txt'
    meta['cmake']=[s for s in cache.read_text().splitlines() if re.match(r'(LLDB_TEST_OBJC|LLDB_TEST_TRIPLE|LLDB_TEST_SYSROOT|CMAKE_BUILD_TYPE|CMAKE_CXX_COMPILER):?',s)]
    (dest/'provenance.json').write_text(json.dumps(meta,indent=2)+'\n')
    command=[sys.executable,str(lab.HERE/'test_workflows.py'),'--config',a.config]
    result=subprocess.run(command,env=env,timeout=600).returncode
    if a.deep:
        deep=subprocess.run([sys.executable,str(lab.HERE/'test_workspace.py'),'--config',a.config],env=env,timeout=600)
        if deep.returncode: result=1
    lit=Path(c['build'])/'bin/llvm-lit'
    if not lit.exists(): lit=Path(c['llvm'])/'llvm/utils/lit/lit.py'
    suites=[Path(c['build'])/'tools/lldb/test/Shell',Path(c['build'])/'tools/lldb/test/API']
    r=subprocess.run([sys.executable,str(lit),'-v','--filter=objc-gnustep',*[str(s) for s in suites]],
        env=env,capture_output=True,text=True,timeout=1200)
    output=r.stdout+r.stderr
    (dest/'llvm-gnustep.log').write_text(output,encoding='utf-8')
    passed=re.search(r'Passed\s*:\s*(\d+)',output)
    unsupported=re.search(r'Unsupported\s*:\s*([1-9]\d*)',output)
    if r.returncode or not passed or not int(passed[1]) or unsupported: result=1
    for relative,name,extra in [
        ('LanguageRuntime/ObjC/GNUstepObjCRuntime/LanguageRuntimeObjCGNUstepTests','runtime-unit',[]),
        ('Language/ObjC/LanguageObjCTests','formatter-unit',['--gtest_filter=*GNUstep*'])]:
        binary=Path(c['build'])/'tools/lldb/unittests'/(relative+lab.SUFFIX)
        r=subprocess.run([str(binary),*extra,'--gtest_output=json:'+str(dest/(name+'.json'))],env=env,
            capture_output=True,text=True,timeout=120)
        (dest/(name+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
        if r.returncode: result=1
    print('CI integration', 'PASS' if result==0 else 'FAIL; inspect '+str(dest))
    return result
if __name__=='__main__': raise SystemExit(main())
