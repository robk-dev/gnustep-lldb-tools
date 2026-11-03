#!/usr/bin/env python3
"""Pinned Gorm setup and breakpoint smoke test for a provisioned Linux GNUstep GUI stack."""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import lab

REVISION='5fd8b86696574ba13c8f9e2340755bb3200b15d1'
URL='https://github.com/gnustep/apps-gorm.git'

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['setup','configure','smoke'])
    p.add_argument('--config',default=str(lab.HERE/'out/config.json'))
    p.add_argument('--source',type=Path)
    p.add_argument('--program',type=Path,help='Installed Gorm.app/Gorm; defaults to GNUSTEP_USER_APPS')
    a=p.parse_args()
    if sys.platform=='win32': p.error('Run this lab in Linux/WSL. Native Windows Gorm has not been validated.')
    c=json.loads(Path(a.config).read_text()); out=Path(c['out'])
    src=(a.source or out/'projects/gorm').resolve()
    env=lab.environment(c)
    gc=Path(c['base'])/'bin/gnustep-config'
    lab.require(gc,'Install GNUstep make/base/gui/back before the Gorm lab.')
    def variable(name): return subprocess.check_output([str(gc),'--variable='+name],text=True,env=env).strip()
    if a.action=='setup':
        if not src.exists():
            src.parent.mkdir(parents=True,exist_ok=True)
            lab.run(['git','clone',URL,src])
            lab.run(['git','-C',src,'checkout','--detach',REVISION])
        actual=subprocess.check_output(['git','-C',str(src),'rev-parse','HEAD'],text=True).strip()
        if actual!=REVISION: p.error('Existing Gorm checkout differs from the pin; pass a new --source directory.')
        dirty=subprocess.check_output(['git','-C',str(src),'status','--porcelain'],text=True)
        if dirty: p.error('Gorm source has local changes; use a clean checkout for the recorded lab.')
        env['GNUSTEP_MAKEFILES']=variable('GNUSTEP_MAKEFILES')
        env['PATH']=str(gc.parent)+os.pathsep+env['PATH']
        env['CC']=lab.executable(c,'clang'); env['CXX']=lab.executable(c,'clang++')
        lab.run(['make','-j2','debug=yes','strip=no'],cwd=src,env=env)
        # GormCore and palettes must be installed. USER avoids modifying the system prefix.
        lab.run(['make','install','debug=yes','strip=no','GNUSTEP_INSTALLATION_DOMAIN=USER'],cwd=src,env=env)
    user_apps=variable('GNUSTEP_USER_APPS')
    if not a.program and not user_apps: p.error('gnustep-config did not report GNUSTEP_USER_APPS; pass --program.')
    program=(a.program or Path(user_apps)/'Gorm.app/Gorm').resolve()
    lab.require(program,'Build/install Gorm first, or pass --program with its installed executable.')
    config={'name':'Gorm: new document','type':'lldb-dap','request':'launch','program':str(program),
        'cwd':str(program.parent),'debugAdapterExecutable':lab.executable(c,'lldb-dap'),
        'preRunCommands':['breakpoint set -n "-[GormDocumentController newDocument:]"'],
        'env':{'PATH':env['PATH']}}
    workspace={'folders':[{'path':str(src)}],'launch':{'version':'0.2.0','configurations':[config]}}
    (out/'gorm.code-workspace').write_text(json.dumps(workspace,indent=2)+'\n')
    # Also supply launch.json for opening the clone directly, without modifying its tracked files.
    (out/'gorm.launch.json').write_text(json.dumps({'version':'0.2.0','configurations':[config]},indent=2)+'\n')
    if a.action=='smoke':
        args=[lab.executable(c,'lldb'),'--no-lldbinit','-b','-o','settings set target.disable-aslr false',
              '-o','breakpoint set -n "-[GormAppDelegate applicationDidFinishLaunching:]"',
              '-o','run','-o','frame info','-o','thread backtrace -c 5','-o','process kill','--',str(program)]
        if not env.get('DISPLAY'):
            xvfb=shutil.which('xvfb-run')
            if not xvfb: p.error('No DISPLAY or xvfb-run. Install Xvfb or use a working WSLg display.')
            args=[xvfb,'-a',*args]
        process=subprocess.Popen(args,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                                 text=True,start_new_session=True)
        timed_out=False
        try:
            stdout,stderr=process.communicate(timeout=90)
        except subprocess.TimeoutExpired:
            timed_out=True
            # This session contains only the debugger/display processes launched above.
            os.killpg(process.pid,signal.SIGKILL)
            stdout,stderr=process.communicate()
        output=stdout+stderr
        (out/'validation').mkdir(exist_ok=True)
        (out/'validation/gorm.log').write_text(output)
        if timed_out: p.exit(1,'Gorm smoke test timed out; see validation/gorm.log and verify the GUI backend/display.\n')
        if process.returncode or 'stop reason = breakpoint' not in output or 'GormAppDelegate.m:' not in output:
            p.exit(1,'Gorm did not reach the expected source breakpoint; see validation/gorm.log.\n')
        print('Gorm startup source breakpoint PASS')
    print(out/'gorm.code-workspace')
if __name__=='__main__': main()
