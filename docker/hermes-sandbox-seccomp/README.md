# hermes-sandbox-seccomp

Measured default-deny seccomp profile for the Hermes Docker sandbox. Full write-up: the
"measured, default-deny seccomp allowlist" addendum in the top-level README.

| Path | What |
|---|---|
| `seccomp-hermes.json` | the profile (235 allowed names, `SCMP_ACT_ERRNO`, x86_64 only) |
| `workload/run_suite.sh` | 40-step workload, one `docker exec bash -c` per step |
| `workload/negative_tests.py` | run inside the sandbox; proves dangerous syscalls are refused |
| `tools/launch_test_container.sh` | throwaway container mirroring the live sandbox flags |
| `tools/extract_syscalls.py` | `perf trace` text -> per-syscall counts (drops runc-init) |
| `tools/build_profile.py` | observed + labelled margin -> profile |
| `evidence/` | aggregated syscall counts, profile report, suite and negative-test results |

## Reproduce
```bash
tools/launch_test_container.sh trace unconfined                 # fresh container, seccomp off
ID=$(docker inspect -f '{{.Id}}' trace)
sudo perf trace -a -G system.slice/docker-$ID.scope -o trace.txt &   # SIGINT it when done
workload/run_suite.sh trace results.tsv
python3 tools/extract_syscalls.py trace.txt > counts.json
python3 tools/build_profile.py counts.json -o seccomp-hermes.json --report report.json
tools/launch_test_container.sh check seccomp-hermes.json && workload/run_suite.sh check out.tsv
docker exec -i check python3 - < workload/negative_tests.py
```
The cgroup path assumes Docker's systemd cgroup driver. Raw traces are not published (they contain
file paths); `evidence/observed_syscalls.json` has the aggregate.
