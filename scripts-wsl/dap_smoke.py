#!/usr/bin/env python3
"""Drive lldb-dap the way VS Code does and print the Locals a user would see.

Checks the path the editor uses (lldb-dap, not the lldb command line): launch,
stop at a source breakpoint, list the locals with their display values, and
expand the ones named with --expand.

Usage:
  dap_smoke.py --dap <lldb-dap> --program <exe> --source <file> --line <n>
               [--cwd <dir>] [--env NAME=VALUE ...] [--expand var ...]

Works against a Windows lldb-dap.exe from WSL too: give /mnt/c paths for
--dap, and Windows paths (C:\\...) for --program, --source and --cwd, since
those are interpreted by the adapter.
"""
import argparse
import json
import subprocess
import sys
import threading
import queue


class Dap:
    def __init__(self, argv):
        self.proc = subprocess.Popen(argv, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL)
        self.seq = 0
        self.messages = queue.Queue()
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        stream = self.proc.stdout
        while True:
            header = b""
            while not header.endswith(b"\r\n\r\n"):
                byte = stream.read(1)
                if not byte:
                    return
                header += byte
            length = int(header.split(b"Content-Length:")[1].split(b"\r\n")[0])
            self.messages.put(json.loads(stream.read(length)))

    def send(self, command, arguments=None):
        self.seq += 1
        body = json.dumps({"seq": self.seq, "type": "request",
                           "command": command,
                           "arguments": arguments or {}}).encode()
        self.proc.stdin.write(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.proc.stdin.flush()
        return self.seq

    def wait(self, predicate, timeout=120):
        while True:
            message = self.messages.get(timeout=timeout)
            if predicate(message):
                return message

    def request(self, command, arguments=None, timeout=120):
        seq = self.send(command, arguments)
        response = self.wait(lambda m: m.get("type") == "response"
                             and m.get("request_seq") == seq, timeout)
        if not response.get("success"):
            raise SystemExit(f"{command} failed: {response.get('message')}")
        return response.get("body", {})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dap", required=True)
    parser.add_argument("--program", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--line", type=int, required=True)
    parser.add_argument("--cwd")
    parser.add_argument("--env", action="append", default=[])
    parser.add_argument("--expand", action="append", default=[])
    args = parser.parse_args()

    dap = Dap([args.dap])
    dap.request("initialize", {"adapterID": "lldb-dap", "clientID": "smoke",
                               "linesStartAt1": True, "columnsStartAt1": True,
                               "pathFormat": "path"})
    launch = {"program": args.program, "stopOnEntry": False}
    if args.cwd:
        launch["cwd"] = args.cwd
    if args.env:
        launch["env"] = dict(e.split("=", 1) for e in args.env)
    dap.send("launch", launch)
    dap.wait(lambda m: m.get("type") == "event" and m.get("event") == "initialized")
    body = dap.request("setBreakpoints", {"source": {"path": args.source},
                                          "breakpoints": [{"line": args.line}]})
    print("breakpoint verified:", body["breakpoints"][0].get("verified"))
    dap.request("configurationDone")
    stopped = dap.wait(lambda m: m.get("type") == "event"
                       and m.get("event") in ("stopped", "exited", "terminated"))
    if stopped["event"] != "stopped":
        raise SystemExit(f"process {stopped['event']} before the breakpoint")
    thread = stopped["body"]["threadId"]
    frame = dap.request("stackTrace", {"threadId": thread})["stackFrames"][0]
    print("stopped in:", frame["name"])
    scopes = dap.request("scopes", {"frameId": frame["id"]})["scopes"]
    locals_ref = next(s for s in scopes if s["name"] == "Locals")["variablesReference"]
    for var in dap.request("variables", {"variablesReference": locals_ref})["variables"]:
        print(f"  {var['name']} = {var['value']}")
        if var["name"] in args.expand and var.get("variablesReference"):
            children = dap.request("variables",
                                   {"variablesReference": var["variablesReference"]})
            for child in children["variables"]:
                print(f"      {child['name']} = {child['value']}")
    dap.send("disconnect", {"terminateDebuggee": True})
    dap.proc.wait(timeout=30)


if __name__ == "__main__":
    main()
