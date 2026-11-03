#!/usr/bin/env python3
"""Exercise real CLI, DAP and MCP sessions; save transcripts and a JSON report."""
import argparse
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
import traceback
import lab

class Wire:
    def __init__(self, command, env, dap=False):
        self.dap=dap
        self.seq=0
        self.messages=queue.Queue()
        self.pending=[]
        self.log=[]
        self.process=subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env=env)
        threading.Thread(target=self.read, daemon=True).start()
        threading.Thread(target=self.read_errors, daemon=True).start()

    def read_errors(self):
        for line in iter(self.process.stderr.readline,b''):
            self.log.append({'stderr':line.decode(errors='replace')})

    def read(self):
        try:
            while True:
                line=self.process.stdout.readline()
                if not line: break
                if self.dap:
                    headers={}
                    while line.strip():
                        k,v=line.decode().split(':',1)
                        headers[k.lower()]=v.strip()
                        line=self.process.stdout.readline()
                    raw=self.process.stdout.read(int(headers['content-length']))
                else: raw=line
                message=json.loads(raw)
                self.log.append({'received':message})
                self.messages.put(message)
        except Exception as e:
            self.messages.put({'reader_error':str(e)})
        self.messages.put({'eof':True})

    def send(self, method, params=None, notification=False):
        self.seq+=1
        if self.dap:
            msg={'seq':self.seq,'type':'request','command':method,'arguments':params or {}}
        else:
            msg={'jsonrpc':'2.0','method':method,'params':params or {}}
            if not notification: msg['id']=self.seq
        raw=json.dumps(msg).encode()
        self.log.append({'sent':msg})
        self.process.stdin.write((f'Content-Length: {len(raw)}\r\n\r\n'.encode()+raw) if self.dap else raw+b'\n')
        self.process.stdin.flush()
        return self.seq

    def wait(self, predicate, timeout=45):
        deadline=time.monotonic()+timeout
        while True:
            for i,msg in enumerate(self.pending):
                if predicate(msg): return self.pending.pop(i)
            remaining=deadline-time.monotonic()
            if remaining<=0: raise TimeoutError('Protocol response timed out')
            msg=self.messages.get(timeout=remaining)
            if 'eof' in msg or 'reader_error' in msg: raise RuntimeError(msg)
            self.pending.append(msg)

    def response(self, seq):
        msg=self.wait(lambda m: m.get('request_seq' if self.dap else 'id')==seq)
        if self.dap: assert msg.get('success'), msg
        else: assert 'error' not in msg, msg
        return msg.get('body',{}) if self.dap else msg.get('result',{})

    def request(self, method, params=None): return self.response(self.send(method,params))
    def event(self, name): return self.wait(lambda m: m.get('event')==name)
    def close(self):
        try:
            self.process.stdin.close()
            self.process.wait(timeout=8)
        except (subprocess.TimeoutExpired, OSError):
            self.process.kill()
            self.process.wait(timeout=8)

def check(pattern, output):
    assert re.search(pattern, output), f'Missing {pattern!r} in:\n{output}'

def cli(c, binary):
    commands=['breakpoint set -f counter.m -p LESSON_STOP','run',
      'frame variable -d no-run-target object','frame variable *counter',
      'expression -- (int)[counter twice:21]','po counter','step','frame info','continue']
    args=[lab.executable(c,'lldb'),'--no-lldbinit','-b']
    for cmd in commands: args+=['-o',cmd]
    args+=['--',str(Path(c['out'])/(binary+lab.SUFFIX))]
    r=subprocess.run(args,env=lab.environment(c),capture_output=True,text=True,timeout=90)
    output=r.stdout+r.stderr
    assert r.returncode==0, output
    for pattern in [r'Counter \*\) object',r'before = 1',r'aligned = 42',r'after = 3',
                    r'\(int\) \$\d+ = 42',r'Counter ready',r'Counter twice:',r'exited with status = 0']:
        check(pattern,output)
    return output

def dap(c):
    w=Wire([lab.executable(c,'lldb-dap')], lab.environment(c), dap=True)
    try:
        w.request('initialize',{'adapterID':'lldb','linesStartAt1':True,'columnsStartAt1':True,'pathFormat':'path'})
        launch=w.send('launch',{'program':str(Path(c['out'])/('counter'+lab.SUFFIX)),
             'cwd':c['out'],'disableASLR':False})
        w.event('initialized')
        source=Path(c['source'])/'counter.m'
        line=next(i for i,s in enumerate(source.read_text().splitlines(),1) if 'LESSON_STOP' in s)
        bp=w.request('setBreakpoints',{'source':{'path':str(source)},'breakpoints':[{'line':line}]})
        assert all(b.get('verified') for b in bp['breakpoints']),bp
        w.request('configurationDone')
        w.response(launch)
        stop=w.event('stopped')['body']
        assert stop['reason']=='breakpoint',stop
        tid=stop['threadId']
        frames=w.request('stackTrace',{'threadId':tid})['stackFrames']
        assert frames[0]['line']==line,frames
        fid=frames[0]['id']
        scopes=w.request('scopes',{'frameId':fid})['scopes']
        values=[]
        for scope in scopes:
            values+=w.request('variables',{'variablesReference':scope['variablesReference']})['variables']
        assert any(v['name']=='counter' for v in values),values
        result=w.request('evaluate',{'expression':'(int)[counter twice:21]','frameId':fid,'context':'watch'})
        check('42',result['result'])
        w.request('stepIn',{'threadId':tid})
        w.event('stopped')
        frames=w.request('stackTrace',{'threadId':tid})['stackFrames']
        check('Counter twice:',frames[0]['name'])
        w.request('continue',{'threadId':tid})
        exited=w.event('exited')['body']
        assert exited['exitCode']==0,exited
        w.request('disconnect',{'terminateDebuggee':True})
        return w.log
    except Exception as error:
        error.protocol_log=w.log
        raise
    finally:
        if w.process.poll() is None:
            try: w.request('disconnect',{'terminateDebuggee':True})
            except Exception: pass
        w.close()

def mcp(c):
    w=Wire([lab.executable(c,'lldb-mcp')], lab.environment(c))
    session=None
    def call(tool,args=None):
        r=w.request('tools/call',{'name':tool,'arguments':args or {}})
        assert not r.get('isError'),r
        return '\n'.join(x.get('text','') for x in r.get('content',[]))
    try:
        w.request('initialize',{'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'lesson-test','version':'1'}})
        w.send('notifications/initialized',notification=True)
        names={t['name'] for t in w.request('tools/list')['tools']}
        assert {'session_create','session_close','command','sessions_list'}<=names,names
        created=call('session_create')
        session=re.search(r'lldb-mcp://[^\s"<>]+',created).group(0)
        def command(cmd): return call('command',{'debugger':session,'command':cmd})
        command('script lldb.debugger.SetAsync(False)')
        command('settings set target.disable-aslr false')
        target=str(Path(c['out'])/('counter'+lab.SUFFIX)).replace('\\','/')
        command(f'target create "{target}"')
        check('Breakpoint',command('breakpoint set -f counter.m -p LESSON_STOP'))
        check('stopped',command('run'))
        check(r'Counter \*\) object',command('frame variable -d no-run-target object'))
        check('aligned = 42',command('frame variable *counter'))
        check(r'\(int\) \$\d+ = 42',command('expression -- (int)[counter twice:21]'))
        check('Counter ready',command('po counter'))
        command('step')
        check('Counter twice:',command('frame info'))
        check('exited with status = 0',command('continue'))
        return w.log
    except Exception as error:
        error.protocol_log=w.log
        raise
    finally:
        if session:
            try: call('session_close',{'session':session})
            except Exception: pass
        w.close()

def foundation(c):
    args=[lab.executable(c,'lldb'),'--no-lldbinit','-b']
    for cmd in ['breakpoint set -f foundation.m -p FOUNDATION_STOP','run','frame variable items number',
                'po items','expression -- (unsigned long long)[items count]',
                'breakpoint set -E objc -w true -h false','continue','thread exception','continue']:
        args+=['-o',cmd]
    args+=['--',str(Path(c['out'])/'foundation'/('foundation'+lab.SUFFIX))]
    env=lab.environment(c)
    if lab.WIN: env['PATH']=str(Path(c['base'])/'bin')+os.pathsep+env['PATH']
    r=subprocess.run(args,env=env,capture_output=True,text=True,timeout=90)
    output=r.stdout+r.stderr
    assert r.returncode==0,output
    for pattern in ['3 elements','apple','banana','LessonException','exited with status = 0']:
        check(pattern,output)
    return output

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config',default=str(lab.HERE/'out/config.json'))
    p.add_argument('--only',nargs='+',choices=['cli','objcxx','dap','mcp','foundation'])
    a=p.parse_args()
    c=json.loads(Path(a.config).read_text())
    dest=Path(c['out'])/'validation'
    dest.mkdir(exist_ok=True)
    results=[]
    cases={'cli':lambda:cli(c,'counter'),'objcxx':lambda:cli(c,'counter-objcxx'),
           'dap':lambda:dap(c),'mcp':lambda:mcp(c),'foundation':lambda:foundation(c)}
    for name,fn in cases.items():
        if a.only and name not in a.only: continue
        start=time.monotonic()
        try:
            output=fn()
            (dest/(name+'.log')).write_text(output if isinstance(output,str) else json.dumps(output,indent=2),encoding='utf-8')
            result={'name':name,'status':'PASS'}
        except Exception as exception:
            error=traceback.format_exc()
            if hasattr(exception,'protocol_log'):
                error+='\nProtocol transcript:\n'+json.dumps(exception.protocol_log,indent=2)
            (dest/(name+'.log')).write_text(error,encoding='utf-8')
            result={'name':name,'status':'FAIL','error':error}
        result['seconds']=round(time.monotonic()-start,2)
        results.append(result)
        print(name,result['status'],flush=True)
    (dest/'results.json').write_text(json.dumps({'config':c,'results':results},indent=2)+'\n')
    return int(any(r['status']=='FAIL' for r in results))
if __name__=='__main__': sys.exit(main())
