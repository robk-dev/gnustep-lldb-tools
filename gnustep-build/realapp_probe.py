#!/usr/bin/env python3
"""Drive a battery of LLDB probes against a real GNUstep application.

Batch mode (`lldb -b -o ...`) stops sourcing commands at the first error, which
makes it impossible to tell a failed probe from a dead inferior. This drives the
SB API instead, so every probe runs and the process state is checked explicitly
after each one.
"""

import argparse
import os
import sys
import time

import lldb


class Probe:
    def __init__(self, name, command, expect=None, reject=None):
        self.name = name
        self.command = command
        self.expect = expect          # substring that must appear
        self.reject = reject          # substring that must NOT appear

    def verdict(self, output, alive):
        if not alive:
            return "INFERIOR DIED"
        if self.expect and self.expect not in output:
            return "FAIL (missing %r)" % self.expect
        if self.reject and self.reject in output:
            return "FAIL (found %r)" % self.reject
        return "ok"


def run(exe, args, breakpoint_expr, probes, env=None, cwd=None):
    dbg = lldb.SBDebugger.Create()
    dbg.SetAsync(False)
    target = dbg.CreateTarget(exe)
    if not target:
        print("could not create target for %s" % exe, file=sys.stderr)
        return 1

    dbg.HandleCommand("settings set target.prefer-dynamic-value run-target")

    # "file.m:NN" is a source location; anything else is a function name.
    file_line = breakpoint_expr.rsplit(":", 1)
    if len(file_line) == 2 and file_line[1].isdigit() and "[" not in breakpoint_expr:
        bp = target.BreakpointCreateByLocation(file_line[0], int(file_line[1]))
    else:
        bp = target.BreakpointCreateByName(breakpoint_expr)
        if bp.GetNumLocations() == 0:
            # Fall back to a regex if the plain name missed.
            bp = target.BreakpointCreateByRegex(breakpoint_expr)

    launch = target.GetLaunchInfo()
    launch.SetArguments(args, True)
    if env:
        launch.SetEnvironmentEntries(env, True)
    if cwd:
        launch.SetWorkingDirectory(cwd)

    err = lldb.SBError()
    t0 = time.time()
    process = target.Launch(launch, err)
    launch_ms = int((time.time() - t0) * 1000)
    if not process or err.Fail():
        print("launch failed: %s" % err, file=sys.stderr)
        return 1

    if process.GetState() != lldb.eStateStopped:
        print("process did not stop at %s (state=%s)"
              % (breakpoint_expr, process.GetState()), file=sys.stderr)
        return 1

    print("| probe | ms | verdict | output |")
    print("|---|---|---|---|")
    print("| _launch to first stop_ | %d | ok | %d locations |"
          % (launch_ms, bp.GetNumLocations()))

    ci = dbg.GetCommandInterpreter()
    failures = 0
    for probe in probes:
        res = lldb.SBCommandReturnObject()
        t0 = time.time()
        ci.HandleCommand(probe.command, res)
        ms = int((time.time() - t0) * 1000)

        output = (res.GetOutput() or "") + (res.GetError() or "")
        alive = process.GetState() == lldb.eStateStopped
        verdict = probe.verdict(output, alive)
        if verdict != "ok":
            failures += 1

        flat = " ".join(output.split())
        if len(flat) > 160:
            flat = flat[:157] + "..."
        print("| %s | %d | %s | `%s` |" % (probe.name, ms, verdict, flat))

    print()
    print("inferior alive at end: %s"
          % (process.GetState() == lldb.eStateStopped))
    process.Kill()
    lldb.SBDebugger.Destroy(dbg)
    return 1 if failures else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--exe", required=True)
    ap.add_argument("--break-at", required=True)
    ap.add_argument("--cwd")
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("--probe", action="append", default=[],
                    help="name::command[::expect][::!reject]")
    ap.add_argument("args", nargs="*")
    ns = ap.parse_args()

    probes = []
    for spec in ns.probe:
        parts = spec.split("::")
        name, command = parts[0], parts[1]
        expect = reject = None
        for extra in parts[2:]:
            if extra.startswith("!"):
                reject = extra[1:]
            elif extra:
                expect = extra
        probes.append(Probe(name, command, expect, reject))

    sys.exit(run(ns.exe, ns.args, ns.break_at, probes,
                 env=ns.env or None, cwd=ns.cwd))


if __name__ == "__main__":
    main()
