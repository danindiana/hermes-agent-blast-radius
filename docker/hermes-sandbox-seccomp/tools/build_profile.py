#!/usr/bin/env python3
"""Build a default-deny Docker seccomp profile from observed syscalls (+ a small, labelled margin).
usage: build_profile.py counts.json [more counts.json...] -o seccomp-hermes.json [--report report.json]"""
import json, sys, argparse

# Observed in the trace but deliberately NOT allowed (safe fallbacks verified by the validation suite).
DENY_EVEN_IF_OBSERVED = {
    "clone3":               "args live in a struct (cannot be flag-filtered); glibc falls back to clone() on ENOSYS, and clone() IS flag-filtered",
    "landlock_create_ruleset": "optional self-sandboxing probe (xz); tool continues without",
    "landlock_restrict_self":  "same",
    "pkey_alloc":           "V8/node probes for memory protection keys; falls back",
}
# Needed by the container runtime itself AFTER the filter is loaded (found via SCMP_ACT_LOG audit records, comm runc:[2:INIT]).
RUNTIME = {"openat2": "runc init resolves the exec path with openat2 after seccomp is installed"}
# Not observed, added by hand: ordinary libc/runtime calls a different run of the same tools could take.
# Each is benign without capabilities. Kept deliberately small and category-labelled.
MARGIN = {
 "process/time/signals": "getpgid setpgid getsid getresuid getresgid getrlimit setrlimit getitimer alarm pause waitid tkill "
        "rt_sigpending rt_sigsuspend rt_sigqueueinfo rt_tgsigqueueinfo signalfd signalfd4 timer_create timer_settime timer_gettime "
        "timer_delete timer_getoverrun clock_getres gettimeofday time restart_syscall get_robust_list getcpu sched_getscheduler "
        "sched_getparam sched_setparam sched_setscheduler sched_rr_get_interval sched_getattr sched_setattr set_thread_area "
        "get_thread_area fork pidfd_open pidfd_send_signal rseq membarrier futex_waitv futex_wake futex_wait futex_requeue",
 "files": "readlink lchown chown fchownat chmod utime utimes futimesat getdents dup3 sendfile splice tee preadv pwritev preadv2 pwritev2 "
        "readahead sync_file_range syncfs msync mincore mlock mlock2 munlock truncate renameat linkat mkdirat unlinkat fchmodat2 "
        "getxattr lgetxattr fgetxattr listxattr flistxattr setxattr lsetxattr fsetxattr removexattr lremovexattr fremovexattr "
        "inotify_init inotify_init1 inotify_add_watch inotify_rm_watch pipe statfs fstatfs getcwd chdir fchdir fadvise64 "
        "ioprio_get ioprio_set memfd_create epoll_pwait2 ppoll select eventfd",
 "net": "socketpair accept4 shutdown recvmmsg getsockopt setsockopt",
 "ids": "getuid geteuid getgid getegid getgroups getppid gettid getpid getpgrp getpriority setpriority umask",
}

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("counts", nargs="+"); ap.add_argument("-o", required=True); ap.add_argument("--report")
    a = ap.parse_args()
    observed = {}
    for p in a.counts:
        for k, v in json.load(open(p))["syscalls"].items():
            observed.setdefault(k, 0); observed[k] += v["count"]
    plain = (set(observed) | set(RUNTIME)) - set(DENY_EVEN_IF_OBSERVED)
    margin = {s for g in MARGIN.values() for s in g.split()} - plain
    special = {"clone", "socket"}  # emitted below with argument filters
    allow = sorted((plain | margin) - special)
    prof = {
        "defaultAction": "SCMP_ACT_ERRNO", "defaultErrnoRet": 1,
        "archMap": [{"architecture": "SCMP_ARCH_X86_64", "subArchitectures": []}],  # no x32 / ia32 compat ABI
        "syscalls": [
            {"names": allow, "action": "SCMP_ACT_ALLOW"},
            # clone: threads/processes yes, any CLONE_NEW* namespace flag no (0x7E020000 = NEWNS|NEWCGROUP|NEWUTS|NEWIPC|NEWUSER|NEWPID|NEWNET)
            {"names": ["clone"], "action": "SCMP_ACT_ALLOW",
             "args": [{"index": 0, "value": 2114060288, "valueTwo": 0, "op": "SCMP_CMP_MASKED_EQ"}]},
            # clone3 cannot be flag-filtered -> ENOSYS so libc falls back to clone()
            {"names": ["clone3"], "action": "SCMP_ACT_ERRNO", "errnoRet": 38},
        ] + [
            # socket: only AF_UNIX(1) AF_INET(2) AF_INET6(10) AF_NETLINK(16) -- the families seen in the trace
            {"names": ["socket"], "action": "SCMP_ACT_ALLOW", "args": [{"index": 0, "value": f, "op": "SCMP_CMP_EQ"}]}
            for f in (1, 2, 10, 16)
        ],
    }
    json.dump(prof, open(a.o, "w"), indent=1)
    rep = {"observed_total": len(observed), "observed_allowed": sorted(plain & set(observed)),
           "runtime_added": RUNTIME, "observed_denied_on_purpose": DENY_EVEN_IF_OBSERVED, "margin_added": sorted(margin),
           "allowlist_size": len(allow) + 2}
    if a.report: json.dump(rep, open(a.report, "w"), indent=1)
    print(f"observed={len(observed)} margin={len(margin)} allow_entries={len(allow)}+clone+socket(4 families); clone3->ENOSYS")
main()
