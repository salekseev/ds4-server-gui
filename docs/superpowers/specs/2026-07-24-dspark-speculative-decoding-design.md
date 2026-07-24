# DSpark Speculative Decoding Support — Design

Date: 2026-07-24
Status: Approved pending user review

## Goal

Let the menu bar app run its embedded ds4-server with DSpark speculative decoding, matching how the user launches the standalone binary today:

```
./ds4-server --port 18888 -m ./ds4flash.gguf \
  --mtp gguf/DeepSeek-V4-Flash-DSpark-support.gguf --dspark \
  --ctx 100000 --kv-disk-dir /tmp/ds4-kv --kv-disk-space-mb 8192 --tokens 1500
```

Two workstreams, delivered together in this project:

1. **Engine sync** — the vendored ds4 engine predates dspark (`--dspark`, `--dspark-confidence`, `--dspark-strict` are absent from its arg parser). Re-vendor from current upstream antirez/ds4 via **git subtree**, restructured so upstream files are never locally patched again.
2. **GUI** — settings, UI, and arg-builder support for dspark plus a default-max-output-tokens (`--tokens`) setting.

## Decisions made during brainstorming

- Engine sync + GUI in one project (feature must actually work when done).
- UI scope: dspark toggle, support-GGUF path, and `--dspark-confidence` field. No `--mtp-draft` / `--mtp-margin` / `--dspark-strict` exposure.
- Include a "default max output tokens" (`--tokens`) setting.
- Support GGUF acquisition: Browse-only (user downloads the ~5.6 GiB file themselves). No in-app downloader.
- Pinning mechanism: **git subtree** (chosen over submodule, sync script, and package managers — CocoaPods doesn't integrate with an SPM-only app and is in maintenance mode; an SPM remote dependency is blocked because remote packages may not use `unsafeFlags`, which the engine needs for `-O3 -ffast-math -mcpu=native`).

## Part 1 — Engine subtree + embed layer

### Layout

Replaces `DS4MacOS/ds4-engine/Sources/ds4engine/` entirely:

```
DS4MacOS/ds4-engine/
  upstream/                  # git subtree of antirez/ds4, squashed, pinned via merge commit
    ds4.c  ds4_server.c  ds4_metal.m  metal/  ...(full upstream tree)
  embed/
    ds4_server_embed.c       # ALL local glue (below)
    include/ds4engine.h      # existing shim header, moved verbatim
  README.md                  # sync procedure + current upstream ref
```

### Embed wrapper (`embed/ds4_server_embed.c`)

The vendored tree today carries exactly three local modifications; all move into one wrapper translation unit so upstream stays pristine:

```c
#define main ds4_server_main
#define DS4_SERVER_TEST_NO_MAIN
#include "ds4_server.c"      /* pristine upstream, found via header search path */

/* Same TU: reaches the file-static g_stop_requested / g_listen_fd */
void ds4_server_request_stop(void) {
    g_stop_requested = 1;
    if (g_listen_fd >= 0) {
        int fd = (int)g_listen_fd;
        g_listen_fd = -1;
        close(fd);
    }
}
```

### Package.swift target

- `path: "ds4-engine"`
- explicit `sources:` list: `embed/ds4_server_embed.c` + the upstream .c/.m files the server needs (`upstream/ds4.c`, `upstream/ds4_ssd.c`, `upstream/ds4_distributed.c`, `upstream/ds4_metal.m`, `upstream/ds4_help.c`, `upstream/ds4_kvstore.c`, `upstream/rax.c`, plus any new upstream dependencies such as `ds4_web.c` / `ds4_gpu_args.c` / `ds4_tp.c` — finalized against compiler/linker errors during implementation). `upstream/ds4_server.c` is **not** listed; it compiles only via the wrapper include. CUDA/ROCm sources stay uncompiled.
- `resources: [.copy("upstream/metal")]` (preserves the app's `metal/flash_attn.metal` shader-dir probe)
- `publicHeadersPath: "embed/include"`
- `cSettings`: keep existing defines/flags, add `.headerSearchPath("upstream")`

### Sync procedure (documented in ds4-engine/README.md)

1. `git subtree pull --prefix DS4MacOS/ds4-engine/upstream <upstream-url> <ref> --squash`
2. Rebuild; adjust the `sources:` list on linker errors.
3. Re-verify the two fragile couplings: (a) the static variable names used by `ds4_server_request_stop()`; (b) `metal/flash_attn.metal` still exists.

No CI changes: subtree repos clone normally.

### First-sync verification gates

- `--dspark` and `--dspark-confidence` present in the new server arg parser.
- App builds (SPM debug + release/CI configuration).
- Server starts, serves OpenAI/Anthropic requests, and runs with dspark active.

### Known upstream dspark constraints (inform UI copy, no enforcement beyond notes)

- Greedy-only: sampled requests (temperature > 0) don't use DSpark proposals.
- DeepSeek V4 PRO unsupported; support GGUF (~5.6 GiB) matches Flash q2/q2-q4/q4-imatrix quantizations.
- Incompatible with `--quality` (not exposed by the GUI) and with `--ssd-streaming` (exposed — see mutex below).

## Part 2 — GUI

### Settings model (Settings.swift)

Four new UserDefaults-backed properties, existing pattern:

| Property | Type | Default | Maps to |
|---|---|---|---|
| `enableDSpark` | Bool | false | `--dspark` (+ `--mtp`) |
| `dsparkModelPath` | String | "" | `--mtp <path>` |
| `dsparkConfidence` | Double | 0.9 (clamped 0…1) | `--dspark-confidence` |
| `defaultMaxTokens` | Int | 0 = engine default | `--tokens` |

No `migrateIfNeeded()` changes — keys never existed in the legacy suite.

### Arg builder (ServerManager.buildArgs)

Follows the existing omit-at-default style:

```swift
if settings.enableDSpark && !settings.enableSSDStreaming {
    args += ["--mtp", settings.dsparkModelPath, "--dspark"]
    if settings.dsparkConfidence != 0.9 {
        args += ["--dspark-confidence", String(settings.dsparkConfidence)]
    }
}
if settings.defaultMaxTokens > 0 { args += ["--tokens", String(settings.defaultMaxTokens)] }
```

If both dspark and SSD streaming are enabled (stale prefs only — UI prevents it), SSD streaming wins and a warning is logged that dspark was skipped. Rationale: dropping SSD streaming could make the model not fit in memory; dropping dspark only costs speed.

### Settings UI (SettingsWindowController, Performance tab)

New section **"Speculative decoding (DSpark)"**:

- Checkbox: "Enable DSpark speculative decoding"
- Support-GGUF path field + Browse button (same row pattern as main model; no file-type filter, consistent with existing pickers)
- Confidence field (width ~80, placeholder `0.9`). Display rule mirrors the existing `ssdCacheField` pattern: shown empty when the stored value equals the 0.9 default; on save, empty or unparsable input stores 0.9.
- Note: "Requires the DSpark support GGUF (~5.6 GB). Only speeds up greedy requests (temperature 0). Incompatible with SSD streaming."

Mutex behavior: checking DSpark unchecks SSD streaming and vice versa (checkbox actions), each hint mentioning the incompatibility.

Context section gains **"Default max output tokens"** numeric field (placeholder `393216`; empty/0 ⇒ omit flag).

Window height grows to fit the taller Performance tab (500 → roughly 600; final value set visually during implementation). All new strings added as `L()` keys in all four locales: en, ja, zh-Hans, zh-Hant.

### Error handling

- DSpark enabled but support file missing/too small (< 1 MiB, same heuristic as main model): `start()` fails with `.error` status + log line. This validation runs in `start()` alongside the existing main-model check, before `buildArgs` is called — so the arg builder can assume a valid path. Does **not** open the model-setup window (that flow stays main-model-only).
- Engine rejects args after a future sync: existing exit-during-startup → `.loadError` path surfaces it.

## Testing

- Extract arg construction from `ServerManager` into a small internal pure function and add the project's **first test target** covering: dspark on/off, missing path, confidence default-elision, SSD-streaming mutex backstop, `--tokens` elision.
- Build verification: `swift build` debug + the CI (macos-15/xcodebuild) configuration.
- Manual verification with the real support GGUF: args line in the log window, dspark active in server output, tok/s comparison on a code-heavy greedy prompt vs. dspark off.

## Out of scope

- In-app download of the support GGUF.
- Exposing `--mtp-draft`, `--mtp-margin`, `--dspark-strict`, `--quality`.
- Spawning an external ds4-server binary (in-process architecture unchanged).
