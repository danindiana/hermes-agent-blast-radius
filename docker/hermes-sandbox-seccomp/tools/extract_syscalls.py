#!/usr/bin/env python3
"""Aggregate `perf trace` text output into per-syscall counts (and per-comm), excluding runc setup comms.
usage: extract_syscalls.py trace.txt [more traces...] > counts.json"""
import re, sys, json, collections
pat = re.compile(r'\s(\S+?)/(\d+)\s+(?:\.\.\.\s+\[continued\]:\s+)?([a-z_0-9]+)\(')
cont = re.compile(r'\[continued\]:\s+([a-z_0-9]+)\(')
counts = collections.Counter(); comms = collections.defaultdict(set); runc = collections.Counter()
for path in sys.argv[1:]:
    for line in open(path, errors='replace'):
        m = pat.search(line)
        if not m: continue
        comm, pid, sc = m.groups()
        if sc in ('continued',):
            m2 = cont.search(line); sc = m2.group(1) if m2 else sc
        if comm.startswith('runc') or comm.startswith(':') or comm == '':
            runc[sc] += 1; continue
        counts[sc] += 1; comms[sc].add(comm)
json.dump({'syscalls': {k: {'count': v, 'comms': sorted(comms[k])[:6]} for k, v in sorted(counts.items())},
           'runc_init_only': dict(runc)}, sys.stdout, indent=1)
