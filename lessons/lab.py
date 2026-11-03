#!/usr/bin/env python3
"""Reproducible LLDB lesson builds and workspace configuration (stdlib only)."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent
WIN = sys.platform == "win32"
SUFFIX = ".exe" if WIN else ""

def run(args, **kw):
    print("+", subprocess.list2cmdline([str(x) for x in args]), flush=True)
    subprocess.run([str(x) for x in args], check=True, **kw)

def config(args):
    llvm = Path(args.llvm_root).resolve()
    build = Path(args.build_dir or llvm / "build").resolve()
    prefix = Path(args.prefix or (ROOT.parent / "gnustep-prefix" if WIN else "/usr/local")).resolve()
    base = Path(args.base_prefix or (ROOT.parent / "gnustep-msvc/x64/Release" if WIN else prefix)).resolve()
    out = Path(args.out).resolve()
    return dict(llvm=str(llvm), build=str(build), prefix=str(prefix), base=str(base),
                out=str(out), abi=args.abi, source=str(HERE / "fixtures"),
                tools=str(ROOT), platform=sys.platform)

def environment(c):
    env = dict(os.environ)
    dirs = [str(Path(c['build']) / 'bin')]
    if WIN:
        # Foundation and bare-runtime fixtures launch with their own runtime path.
        dirs += [str(Path(sys.executable).parent)]
    env['PATH'] = os.pathsep.join(dirs + [env.get('PATH', '')])
    return env

def executable(c, name):
    return str(Path(c['build']) / 'bin' / (name + SUFFIX))

def require(path, explanation):
    if not Path(path).exists():
        raise RuntimeError(f"Missing {path}. {explanation}")

def build(c):
    out = Path(c['out'])
    out.mkdir(parents=True, exist_ok=True)
    clang = executable(c, 'clang')
    require(clang, 'Build clang, lldb, lldb-dap and lldb-mcp first; see the repository README.')
    require(Path(c['prefix']) / 'include/objc/runtime.h', 'Pass --prefix with your libobjc2 install prefix.')
    env = environment(c)
    common = ['-g', '-O0', '-fobjc-runtime=gnustep-2.0', '-I' + str(Path(c['prefix']) / 'include')]
    link = ['-L' + str(Path(c['prefix']) / 'lib'), '-lobjc']
    if WIN:
        common[0] = '-gdwarf'
        if c['abi'] != 'msvc':
            raise RuntimeError('This Windows fixture builder currently supports --abi msvc. Use existing MinGW recipes for GNU ABI.')
        common += ['-Xclang', '--dependent-lib=msvcrtd']
        link += ['-fuse-ld=lld-link', '-Wl,/debug:dwarf']
    else:
        link += ['-Wl,-rpath,' + str(Path(c['prefix']) / 'lib')]
    for name, lang in [('counter', 'objective-c'), ('counter-objcxx', 'objective-c++')]:
        run([clang, '-x', lang, *common, '-c', HERE / 'fixtures/counter.m', '-o', out / (name + '.o')], env=env)
        run([clang, out / (name + '.o'), *link, '-o', out / (name + SUFFIX)], env=env)
    run([clang, '-g', '-O0', HERE / 'fixtures/basics.c', '-o', out / ('basics' + SUFFIX)], env=env)
    if WIN:
        # Keep the fixture's runtime adjacent to it; do not mix MSVC and MinGW DLLs.
        import shutil
        require(Path(c['prefix']) / 'lib/objc.dll', 'Use an MSVC libobjc2 prefix for this recipe.')
        shutil.copy2(Path(c['prefix']) / 'lib/objc.dll', out / 'objc.dll')
        foundation_out = out / 'foundation'
        run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
             ROOT / 'demos/build-foundation.ps1', '-Clang', clang, '-GnustepRoot', c['base'],
             '-Source', HERE / 'fixtures/foundation.m', '-Name', 'foundation', '-OutDir', foundation_out], env=env)
    else:
        gc = Path(c['base']) / 'bin/gnustep-config'
        require(gc, 'Install gnustep-base and tools-make, or pass --base-prefix.')
        flags = shlex.split(subprocess.check_output([str(gc), '--objc-flags'], text=True))
        libs = shlex.split(subprocess.check_output([str(gc), '--base-libs'], text=True))
        (out / 'foundation').mkdir(exist_ok=True)
        run([clang, *flags, '-O0', '-g', '-fobjc-runtime=gnustep-2.0', HERE / 'fixtures/foundation.m',
             *libs, '-o', out / 'foundation/foundation'], env=env)

def generate(c):
    out = Path(c['out'])
    out.mkdir(parents=True, exist_ok=True)
    (out / 'config.json').write_text(json.dumps(c, indent=2) + '\n')
    env = environment(c)
    configs = []
    for name, binary in [('01 Basics', 'basics'), ('02 Runtime', 'counter'), ('03 Objective-C++', 'counter-objcxx'), ('04 Foundation', 'foundation/foundation')]:
        launch_env = dict(PATH=env['PATH'])
        if WIN and 'Foundation' in name:
            launch_env['PATH'] = str(Path(c['base']) / 'bin') + os.pathsep + env['PATH']
        configs.append(dict(name=name, type='lldb-dap', request='launch',
            program=str(out / (binary + SUFFIX)), cwd=str(out),
            debugAdapterExecutable=executable(c, 'lldb-dap'), env=launch_env,
            stopOnEntry=False))
    configs.append(dict(name='05 Clang: compile Objective-C', type='lldb-dap', request='launch',
        program=executable(c, 'clang'), debugAdapterExecutable=executable(c, 'lldb-dap'),
        args=['-cc1', '-x', 'objective-c', '-triple', 'x86_64-pc-windows-msvc' if WIN else 'x86_64-unknown-linux-gnu',
              '-fobjc-runtime=gnustep-2.0', '-emit-llvm', '-o', str(out/'counter.ll'),
              '-I', str(Path(c['prefix'])/'include'), str(HERE/'fixtures/compiler.m')],
        preRunCommands=['breakpoint set -f CGObjCGNU.cpp -p "return new CGObjCGNUstep2"'], env={'PATH': env['PATH']}))
    configs.append(dict(name='06 LLDB: debug the debugger', type='lldb-dap', request='launch',
        program=executable(c, 'lldb'), debugAdapterExecutable=executable(c, 'lldb-dap'),
        args=['--no-lldbinit', '-b', '-s', str(out/'inner.lldb'), '--', str(out/('counter'+SUFFIX))],
        preRunCommands=['breakpoint set -n lldb_private::GNUstepObjCRuntime::GetDynamicTypeAndAddress'],
        env={'PATH': env['PATH']}))
    configs.append(dict(name='07 libobjc2: allocate an object', type='lldb-dap', request='launch',
        program=str(out/('counter'+SUFFIX)), debugAdapterExecutable=executable(c,'lldb-dap'),
        preRunCommands=['breakpoint set -n class_createInstance'], env={'PATH':env['PATH']}))
    base_env=env['PATH']
    if WIN: base_env=str(Path(c['base'])/'bin')+os.pathsep+base_env
    configs.append(dict(name='08 gnustep-base: array access',type='lldb-dap',request='launch',
        program=str(out/'foundation'/('foundation'+SUFFIX)),debugAdapterExecutable=executable(c,'lldb-dap'),
        preRunCommands=['breakpoint set -n "-[GSArray objectAtIndex:]"'],env={'PATH':base_env}))
    (out/'inner.lldb').write_text('breakpoint set -f counter.m -p LESSON_STOP\nrun\nframe variable -d no-run-target object\nquit\n')
    workspace = {'folders': [{'name':'lesson-tools','path':str(ROOT)}, {'name':'llvm-project','path':c['llvm']}],
                 'launch': {'version':'0.2.0','configurations':configs},
                 'extensions':{'recommendations':['llvm-vs-code-extensions.lldb-dap']}}
    (out/'lesson.code-workspace').write_text(json.dumps(workspace, indent=2)+'\n')
    (out/'launch.json').write_text(json.dumps(workspace['launch'],indent=2)+'\n')
    (out/'mcp.json').write_text(json.dumps({'servers':{'lldb':{'type':'stdio','command':executable(c,'lldb-mcp'),
        'env':{'PATH':env['PATH']}}}}, indent=2)+'\n')
    (out/'runtime.lldb').write_text('breakpoint set -f counter.m -p LESSON_STOP\nrun\nframe variable -d no-run-target object\nframe variable *counter\nexpression -- (int)[counter twice:21]\npo counter\nstep\nframe info\n')
    print('Workspace:', out/'lesson.code-workspace')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['setup','configure','doctor'])
    p.add_argument('--llvm-root', default=os.environ.get('PROJECT_ROOT', str(ROOT.parent/'llvm-project')))
    p.add_argument('--build-dir', default=os.environ.get('LLVM_BUILD_DIR'))
    p.add_argument('--prefix', default=os.environ.get('GNUSTEP_INSTALL_DIR'))
    p.add_argument('--base-prefix', default=os.environ.get('GNUSTEP_BASE_DIR'))
    p.add_argument('--out', default=str(HERE/'out'))
    p.add_argument('--abi', choices=['msvc','gnu'], default='msvc' if WIN else 'gnu')
    args=p.parse_args()
    c=config(args)
    try:
        for name in ['clang','lldb','lldb-dap','lldb-mcp']:
            require(executable(c,name), 'Build this target or pass --build-dir.')
        require(Path(c['prefix'])/'include/objc/runtime.h', 'Pass --prefix with the libobjc2 installation.')
        require(Path(c['base'])/'include/Foundation/Foundation.h', 'Pass --base-prefix with the gnustep-base installation.')
        if WIN:
            require(Path(c['prefix'])/'lib/objc.dll','Use the MSVC runtime prefix for the Windows lesson builder.')
            require(Path(c['base'])/'lib/gnustep-base.lib','Install the Foundation import library.')
        if args.action=='setup': build(c)
        if args.action!='doctor': generate(c)
        else: print(json.dumps(c, indent=2))
    except (RuntimeError, subprocess.CalledProcessError) as e:
        p.exit(1, str(e)+'\n')
if __name__=='__main__': main()
