# T08 isolated resource measurements

Measured 2026-11-07 against current health source following `4b3ee2b`, OpenWrt 25.12.2 x86_64, Docker image `140e4ebaee4c061bca73db3828103dab1c74a5b20b04aa4b05d2541cd0d8cd21` (fixture snapshot, not a release image).

Original structured output: `local://nbh-t08-performance.json`. This is a synthetic, isolated workload, not a real NetBird/LAN or minimum-router-hardware benchmark.

## Workload and observed results

- Dedicated container: network `none`, all capabilities dropped, 128 MiB memory, 0.5 CPU, 64 PID limit and init reaper. Notification owner `none`; only documentation-address targets.
- Accepted configuration: 64 enabled paths, 16 enabled exact TCP endpoints, 39,383-byte compact approved configuration; no CIDR scanning.
- Actual cycle: **1,904 ms** internal monotonic duration; **3,142.71 ms** SSH-inclusive wall duration. Published **401 checks** (64 × 6 path checks + 16 endpoint checks + one collection check) and all 16 probe rows. All 401 checks remained `UNKNOWN`; unavailable real engine/LAN/generation evidence was not converted into health or dropped from the denominator.
- Concurrent invocation: one cycle exited `0`; competing invocation exited `3` in 680.65 ms including SSH. It did not create a second publication or queue another worker.
- Published result: 208,686 bytes. Health runtime directory: 632 KiB, including latest/history/first-failure copies. Directory mode `0700`, publication mode `0600`, checked through native `fs.stat` (the image lacks a `stat` command).
- Cgroup memory before/after: 2,658,304 / 3,371,008 bytes. Lifetime peak before/after: 7,761,920 / **11,161,600 bytes (10.645 MiB)**. Peaks include package staging/install and are not attributed solely to one cycle.
- Cgroup CPU usage increased by **1,377,473 µs** between the recorded samples. No fabricated CPU percentage or forwarding-throughput claim.
- Fixed trusted `dd` output workload returned `OUTPUT_LIMIT`, exactly 65,536 captured bytes, in 145 ms; output was not treated as complete evidence.
- A 300 ms runner budget returned `TIMEOUT` after 227 ms. Its delayed descendant could not write a marker after 2.4 seconds.
- A 30-second trusted sleep under the maximum 20-second runner budget returned `TIMEOUT` at **19,902 ms** (20,509.92 ms including SSH). Process listing afterward contained only the container init, baseline sleep and the listing process: no command/guard descendants remained.
- Actual IPv4 rule/route snapshots, `/proc/net/route` hash and approved UCI configuration hash were byte-equal before/after the maximum-load cycle. The experiment did not change network policy or configuration.
- The dedicated workload container was removed after evidence capture; no throwaway harness remains in the repository.

## Boundaries

`PASS` applies to the exercised isolated limits and cleanup only. No actual LAN observer, real NetBird engine, production throughput, physical reboot or minimum supported router hardware was exercised (`NOT_RUN`). The fast no-network failure workload is not a worst-case 64-path/16-endpoint latency benchmark. The measured 20-second limit is a command-runner limit; supervisor cancellation and worker recovery evidence are separately recorded in [baseline.md](baseline.md). Real minimum-hardware sizing must precede an expanded supported-capacity claim.
