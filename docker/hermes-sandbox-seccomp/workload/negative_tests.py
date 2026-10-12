#!/usr/bin/env python3
"""Run INSIDE the sandbox: each dangerous syscall must be refused (EPERM), clone3 must give ENOSYS, allowed ones must work."""
import ctypes, os, socket, sys
libc = ctypes.CDLL(None, use_errno=True)
NR = dict(ptrace=101, mount=165, umount2=166, unshare=272, setns=308, bpf=321, perf_event_open=298, userfaultfd=323,
          io_uring_setup=425, keyctl=250, add_key=248, kexec_load=246, init_module=175, finit_module=313, reboot=169,
          chroot=161, pivot_root=155, personality=135, process_vm_readv=310, open_by_handle_at=304, name_to_handle_at=303,
          swapon=167, acct=163, settimeofday=164, clone3=435, fsopen=430, open_tree=428, move_mount=429, mknod=133,
          setuid=105, capset=126, mlockall=151, syslog=103, modify_ldt=154, pidfd_getfd=438, quotactl=179, sethostname=170)
def call(name, *args):
    ctypes.set_errno(0); r = libc.syscall(NR[name], *[ctypes.c_long(a) for a in args]); return r, ctypes.get_errno()
fails = 0
def expect(label, ok, detail=""):
    global fails; fails += (not ok); print(("PASS " if ok else "FAIL ") + label, detail, flush=True)
EPERM, ENOSYS = 1, 38
for n in ["ptrace","mount","umount2","unshare","setns","bpf","perf_event_open","userfaultfd","io_uring_setup","keyctl","add_key","kexec_load",
          "init_module","finit_module","reboot","chroot","pivot_root","personality","process_vm_readv","open_by_handle_at","name_to_handle_at",
          "swapon","acct","settimeofday","fsopen","open_tree","move_mount","mknod","setuid","capset","mlockall","syslog","modify_ldt",
          "pidfd_getfd","quotactl","sethostname"]:
    a = (16, 1, 0, 0, 0, 0) if n == "ptrace" else (0xFFFFFFFF, 0, 0, 0, 0, 0) if n == "personality" else (0, 0, 0, 0, 0, 0)  # ATTACH pid1 (never TRACEME)
    r, e = call(n, *a); expect(f"deny {n}", r == -1 and e == EPERM, f"errno={e}")
r, e = call("clone3", 0, 0); expect("clone3 -> ENOSYS (glibc falls back to clone)", r == -1 and e == ENOSYS, f"errno={e}")
# clone with CLONE_NEWUSER via raw syscall must be refused
r, e = call("unshare", 0x10000000); expect("unshare(CLONE_NEWUSER) refused", r == -1 and e == EPERM, f"errno={e}")
CLONE = 56; ctypes.set_errno(0); r = libc.syscall(CLONE, ctypes.c_long(0x10000000|17), 0, 0, 0, 0); e = ctypes.get_errno()
if r == 0: os._exit(0)
expect("clone(CLONE_NEWUSER) refused", r == -1 and e == EPERM, f"errno={e}")
for fam, nm in [(17, "AF_PACKET"), (38, "AF_ALG"), (40, "AF_VSOCK"), (9, "AF_KEY")]:
    try: socket.socket(fam, socket.SOCK_RAW if fam == 17 else socket.SOCK_SEQPACKET if fam != 9 else socket.SOCK_RAW); expect(f"deny socket {nm}", False, "created!")
    except OSError as ex: expect(f"deny socket {nm}", ex.errno == EPERM or ex.errno == 93, f"errno={ex.errno}")
for fam, nm in [(socket.AF_UNIX, "AF_UNIX"), (socket.AF_INET, "AF_INET"), (socket.AF_INET6, "AF_INET6")]:
    try: socket.socket(fam, socket.SOCK_STREAM).close(); expect(f"allow socket {nm}", True)
    except OSError as ex: expect(f"allow socket {nm}", False, str(ex))
pid = os.fork()
if pid == 0: os._exit(0)
os.waitpid(pid, 0); expect("fork still works", True)
sys.exit(1 if fails else 0)
