# EmulatR

**A full-system emulator of the DEC Alpha AXP architecture.**

EmulatR models the Alpha **21264 / 21264A (EV6 / EV67)** processor and the **21272 "Tsunami / Typhoon"** core-logic chipset, targeting AlphaServer **DS10 / ES40 / ES45**-class machines. Its goal is faithful, cycle-aware emulation -- complete enough to load and execute original, unmodified DEC **SRM console firmware** and reach the interactive `>>>` prompt.

Copyright (C) 2025, 2026 Timothy Peer / eNVy Systems, Inc. -- https://envysys.com

---

## Status

The SRM console firmware cold-boots all the way to the interactive `>>>` prompt and is fully usable over a serial terminal. `show config`, `show memory`, `show pal`, and `show version` return correct output; firmware is a real SRM 7.3 image carried in emulated flash, and the LFU `update srm` path works.

The current frontier is booting a guest operating system. Two gaps remain between the prompt and an OS boot: no bootable disk is enumerated yet, and the on-board PCI devices (Ethernet, SCSI) are not yet walked. See the documentation's *Current Development Status* for the live picture.

| Subsystem | Status |
|-----------|--------|
| CPU pipeline (EV6) + TLB (128 ITB / 128 DTB) | Working |
| SRM firmware boot to `>>>` | Working |
| TCP console server (RAW TCP, PuTTY auto-launch) | Working |
| Snapshot save / restore (`.axpsnap`) | Working |
| SuperIO (FDC / COM / LPT) | Working |
| IDE / ATAPI virtual CD-ROM | In progress |
| OS boot / PCI device enumeration | Planned |

---

## The modeled machine (DS10)

- **CPU:** Alpha 21264A (EV6 / EV67), 268 MHz (a calibrated figure), with OpenVMS and Tru64 UNIX PALcode.
- **Core logic:** 21272 Tsunami / Typhoon -- Cchip (21272-CA), Dchip (21272-DA), Pchip (21272-EA).
- **Southbridge:** Cypress CY82C693 -- PCI-to-ISA bridge, IDE/ATAPI, and SuperIO (FDC, COM1/COM2, LPT1).
- **Memory:** 1024 MB default array (configurable via the ini or `--mem`).
- **Firmware:** a real SRM image, for example DS10 SRM V7.3 (`ds10_v7_3.exe`).
- **Console:** a RAW TCP server, reached with any terminal client (PuTTY, plink, and similar).

ES40 and ES45 platform manifests are scaffolded but not yet validated.

---

## Architecture highlights

- **Six-stage in-flight pipeline** (IF / DE / GR / EX / MEM / WB). One run-loop iteration corresponds to one EV6 clock; architectural state commits only at Writeback, the single well-defined commit point that makes exceptions precise and replay deterministic.
- **Flat, table-driven dispatch.** Each instruction resolves to a single *grain leaf*. The dispatch tables are generated from `grainFactoryLib/GrainMasterV4.tsv` by `genGrains.py` -- there is no JIT or runtime trace cache.
- **Functional Boxes:** IBox (control flow), EBox (integer), FBox (floating point), MBox (loads/stores, LL/SC), CBox (cache/coherency), PalBox (the privileged boundary), with one-way dependency flow.
- **Memory:** `GuestMemory` pages the guest physical space on demand (64 KiB pages, VirtualAlloc / mmap backed). The `TsunamiChipset` arbiter routes device/MMIO traffic and raises range faults before raw RAM is touched.
- **Translation:** `Ev6Translator` implements PAL-mode bypass, the canonical VA window, and kseg/superpage mapping; the ITB/DTB are modeled by the SPAM cache (`SPAMShardManager`, 128 entries each) with epoch-based lazy invalidation.
- **Floating point:** reached through an `IFpBackend` abstraction; the reference backend is **Berkeley SoftFloat Release 3** (deterministic, bit-identical across hosts), with an optional native host fast-path.

---

## Building

EmulatR builds with **CMake** and a **C++20 MSVC** compiler. The reference kit is **Qt 6.10.2 / MSVC 2022 (64-bit)** through Qt Creator; the emulator core is deliberately Qt-free (Qt is used only by the console / UI front end).

### Linux build with Docker Compose

Install Docker Engine with Docker Compose, then run from the checkout:

```bash
bash scripts/build_container.sh
```

The Debian 13 (`trixie-slim`) build image provides GCC, CMake, Ninja,
[Qt 6.8](https://packages.debian.org/trixie/qt6-base-dev), spdlog, fmt, and
Python 3. SoftFloat and doctest are already vendored in this repository.
The image contains the toolchain and build driver; the checkout is bind-mounted
read-only at `/workspace`. Only `out/` is mounted writable. The wrapper creates
that directory and runs the container with your UID/GID, so generated files
belong to you. No host Qt or compiler installation is needed.

The command builds the `Emulatr` and `Emulatr_tests` targets in
`out/build/container-release/`. Subsequent invocations reuse that build tree.
To select another configuration, change parallelism, or pass CMake options:

```bash
CMAKE_BUILD_TYPE=Debug CMAKE_BUILD_PARALLEL_LEVEL=2 \
  bash scripts/build_container.sh -DEMULATR_TRACE_HOOKS=ON
```

Debug artifacts are in `out/build/container-debug/`; RelWithDebInfo and
MinSizeRel are also supported. Extra CMake options persist in the selected
build tree's cache until explicitly changed or that build directory is removed.

The equivalent direct Compose build is:

```bash
mkdir -p out
LOCAL_UID="$(id -u)" LOCAL_GID="$(id -g)" docker compose run --build --rm builder
```

After a successful build, run the existing doctest suite inside the same
environment, with its working directory set to the build tree:

```bash
LOCAL_UID="$(id -u)" LOCAL_GID="$(id -g)" docker compose run --rm \
  --workdir /workspace/out/build/container-release builder ./Emulatr_tests
```

For an interactive build shell:

```bash
LOCAL_UID="$(id -u)" LOCAL_GID="$(id -g)" docker compose run --rm builder bash
```

Build artifacts link to the container's system libraries; run them in this
environment or on a compatible Linux host. Firmware is not required to compile;
booting a guest requires a separately supplied firmware image.

The build image has been verified on Linux x86_64 with GCC 14.2.0, CMake
3.31.6, and Qt 6.8.2. A complete source build currently also requires fixes for
stale CMake file references, optional firmware staging, case-sensitive includes,
and `uint64_t`/`quint64` type mismatches. The container makes these failures
reproducible without installing the toolchain on the host.

### CMake options

Selected build-time CMake options:

| Option | Effect |
|--------|--------|
| `EMULATR_DEBUG_STEP` | -O0 build of the per-instruction step for single-stepping (off by default). |
| `EMULATR_FP_SOFTFLOAT` | Select the Berkeley SoftFloat backend for bit-exact, host-independent FP. |
| `EMULATR_USE_OS_PAGES` | OS-page (VirtualAlloc / mmap) backing for guest memory. |
| `EMULATR_TRACE_HOOKS`, `EMULATR_MEMDIAG`, ... | Diagnostic / trace instrumentation (off in shipping builds). |

---

## Running

The standard execution shell is **bash** (on Windows, Git Bash / MSYS). Run from the build's run directory, which holds `Emulatr.exe`, `firmware/`, `tools/`, the ini, the flash ROM, and `snapshots/`:

```bash
cd <run-dir>
./Emulatr.exe --firmware firmware/ds10_v7_3.exe
```

Then connect a terminal client to the RAW TCP console port (default 10023). Common switches: `--mem <bytes>`, `--no-autoload` (force a cold boot), `--max-cycles <N>`, `--trace dec,machine`, and the `--log-*` channel filters. See the documentation's *Running EmulatR from the Shell* page for the full set.

---

## Tools

- **host_decompressor** (`tools/host_decompressor/`) -- a native build of the DEC SRM inflate decompressor (Mark Adler c10p1), used as a trusted byte-for-byte **oracle** for the compressed firmware image.
- **Ghidra** -- reverse-engineering the decompressed SRM firmware (`tools/decompile_ds10.sh` drives the headless decompile).
- **Software Verify Performance Validator** -- profiling the hot path.
- **Help & Manual** -- the operator + developer documentation project under `HMDocs/`.

---

## Repository layout

| Path | Contents |
|------|----------|
| `coreLib/`, `pteLib/`, `mmuLib/`, `pipelineLib/` | CPU state, TLB, translation, pipeline. |
| `*BoxLib/`, `grainFactoryLib/` | Instruction execution and the grain codegen. |
| `chipsetLib/`, `deviceLib/`, `memoryLib/` | Tsunami chipset, devices, guest memory. |
| `systemLib/` | Machine orchestration, firmware load, snapshots, CLI. |
| `fpBoxLib/`, `berkeley-softfloat-3-master/` | FP backends and the SoftFloat library. |
| `tools/` | host_decompressor, Ghidra scripts, bash launch/trace helpers. |
| `HMDocs/` | The Help & Manual documentation project. |
| `tests/` | Unit tests per library. |
| `journals/` | Engineering journals and dated checkpoints. |

---

## License

EmulatR is released under the **GNU General Public License v3.0**. See [LICENSE.md](LICENSE.md).

A separate **commercial license** is available for proprietary or closed-source use. Contact Timothy Peer, eNVy Systems, Inc. -- peert (at) envysys.com -- https://envysys.com.

---

## Credits

- **Digital Equipment Corporation (DEC) / Compaq / HP** -- the Alpha AXP architecture, the 21264 / 21272 hardware, the SRM console, and the PALcode. The Alpha Architecture Reference Manual and the DEC firmware sources are the authoritative references EmulatR is measured against.
- **Mark Adler** -- the inflate decompression engine (version c10p1).
- **Berkeley SoftFloat** (John Hauser, UC Berkeley) -- the IEEE / VAX floating-point reference implementation.
- **spdlog**, **Qt** -- logging and the console / UI framework.

System Architect: Timothy Peer / eNVy Systems, Inc. AI collaboration: Claude (Anthropic).
