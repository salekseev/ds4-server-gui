# DSpark Speculative Decoding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the embedded ds4-server with DSpark speculative decoding (`--mtp` + `--dspark` + `--dspark-confidence`) plus a default-max-output-tokens (`--tokens`) setting, with the engine pinned to upstream antirez/ds4 via a git submodule instead of a patched vendored copy.

**Architecture:** `DS4MacOS/ds4-engine/upstream/` becomes a git submodule (pristine antirez/ds4 at a pinned commit); all local glue lives in `DS4MacOS/ds4-engine/embed/` (a wrapper TU that renames `main` and adds `ds4_server_request_stop`). Arg construction is extracted from `ServerManager` into a pure, testable function. Settings/UI follow the existing UserDefaults + AppKit patterns.

**Tech Stack:** Swift 5.9 SPM package + `DS4.xcodeproj` (both build paths must keep working), AppKit, XCTest, C engine compiled in-process.

**Spec:** `docs/superpowers/specs/2026-07-24-dspark-speculative-decoding-design.md`

**Pinned upstream commit:** `0a7ad776b9068348e6cb09df8cafa9cadd285298` (antirez/ds4, 2026-07-23, "Fix batched server session recovery race")

---

## Reference: current state (read before starting)

- Engine vendored at `DS4MacOS/ds4-engine/Sources/ds4engine/` with 3 local modifications: lines 1–2 of `ds4_server.c` (`#define main ds4_server_main`, `#define DS4_SERVER_TEST_NO_MAIN`), the `ds4_server_request_stop()` function (~line 48 of `ds4_server.c`), and the shim header `include/ds4engine.h`.
- SPM: `DS4MacOS/Package.swift`, engine target path `ds4-engine/Sources/ds4engine`.
- Xcode: `DS4MacOS/DS4.xcodeproj/project.pbxproj` — one app target compiling the same C files directly; bridging header `Sources/DS4-Bridging-Header.h` includes `ds4engine.h` via `HEADER_SEARCH_PATHS`; metal shaders copied by a "Copy Metal Shaders" PBXCopyFilesBuildPhase (19 individual file refs, `dstPath = metal`, `dstSubfolderSpec = 7`).
- CI: `.github/workflows/*.yml` builds `DS4.xcodeproj` on macos-15; checkout does NOT fetch submodules yet.
- App args built in `ServerManager.buildArgs` (`DS4MacOS/Sources/ServerManager.swift:151`).
- ja.lproj localization is stale (49 keys, missing the newer `settings.*` keys); en/zh-Hans/zh-Hant are current. Missing ja keys fall back at runtime — only ADD new keys to ja, don't retrofit old ones.

---

### Task 1: Embed layer + engine submodule

**Files:**
- Create: `DS4MacOS/ds4-engine/embed/ds4_server_embed.c`
- Create: `DS4MacOS/ds4-engine/embed/include/ds4engine.h` (moved)
- Create: `DS4MacOS/ds4-engine/README.md`
- Delete: `DS4MacOS/ds4-engine/Sources/` (entire vendored tree)
- Create: `.gitmodules` + submodule at `DS4MacOS/ds4-engine/upstream`

- [ ] **Step 1: Create the embed directory with the shim header (moved verbatim)**

```bash
cd /Users/salekseev/src/github.com/salekseev/ds4-server-gui
mkdir -p DS4MacOS/ds4-engine/embed/include
git mv DS4MacOS/ds4-engine/Sources/ds4engine/include/ds4engine.h DS4MacOS/ds4-engine/embed/include/ds4engine.h
```

- [ ] **Step 2: Create the wrapper TU**

Create `DS4MacOS/ds4-engine/embed/ds4_server_embed.c` with exactly:

```c
/* Embed wrapper: compiles pristine upstream ds4_server.c into the app.
 *
 * - Renames the server's main() so the GUI can call it in-process.
 * - DS4_SERVER_TEST_NO_MAIN drops the unit-test main() at the bottom of
 *   ds4_server.c.
 * - ds4_server_request_stop() lives in this translation unit so it can reach
 *   the file-static g_stop_requested / g_listen_fd. */
#define main ds4_server_main
#ifndef DS4_SERVER_TEST_NO_MAIN /* both build systems also define it globally as =1 */
#define DS4_SERVER_TEST_NO_MAIN 1
#endif
#include "ds4_server.c"
#undef main

void ds4_server_request_stop(void) {
    g_stop_requested = 1;
    if (g_listen_fd >= 0) {
        int fd = (int)g_listen_fd;
        g_listen_fd = -1;
        close(fd);
    }
}
```

- [ ] **Step 3: Remove the vendored tree and add the submodule at the pin**

```bash
git rm -r DS4MacOS/ds4-engine/Sources
git submodule add https://github.com/antirez/ds4 DS4MacOS/ds4-engine/upstream
git -C DS4MacOS/ds4-engine/upstream checkout 0a7ad776b9068348e6cb09df8cafa9cadd285298
git add .gitmodules DS4MacOS/ds4-engine/upstream
```

- [ ] **Step 4: Verify the four fragile couplings against the pinned upstream**

```bash
grep -n '"--dspark"' DS4MacOS/ds4-engine/upstream/ds4_server.c | head -3
grep -n '"--dspark-confidence"' DS4MacOS/ds4-engine/upstream/ds4_server.c | head -3
grep -n "g_stop_requested\b" DS4MacOS/ds4-engine/upstream/ds4_server.c | head -3
grep -n "g_listen_fd\b" DS4MacOS/ds4-engine/upstream/ds4_server.c | head -3
ls DS4MacOS/ds4-engine/upstream/metal/flash_attn.metal
```

Expected: each grep returns at least one hit; the `ls` succeeds. **If `--dspark` is absent or the statics were renamed, STOP and report** — the pin or wrapper needs revisiting, and that decision goes back to the user.

- [ ] **Step 5: Write `DS4MacOS/ds4-engine/README.md`**

```markdown
# ds4 engine (embedded)

- `upstream/` — git submodule of https://github.com/antirez/ds4, pinned to an
  exact commit. NEVER edit files under upstream/.
- `embed/` — local glue compiled into the app:
  - `ds4_server_embed.c` wraps upstream `ds4_server.c` (renames `main` to
    `ds4_server_main`, adds `ds4_server_request_stop()`).
  - `include/ds4engine.h` is the header the Swift side imports.

## Fresh clone

    git clone --recursive <this-repo>
    # or, after a plain clone:
    git submodule update --init

## Bumping the engine

1. `git -C DS4MacOS/ds4-engine/upstream fetch origin`
2. `git -C DS4MacOS/ds4-engine/upstream checkout <new-commit>`
3. Rebuild BOTH ways (`swift build` in DS4MacOS/, and the DS4.xcodeproj scheme).
   Add any new upstream .c files the linker demands to Package.swift AND
   project.pbxproj.
4. Re-verify the fragile couplings:
   - `ds4_server_request_stop()` in `embed/ds4_server_embed.c` touches the
     file-statics `g_stop_requested` / `g_listen_fd` — confirm they still exist
     in upstream `ds4_server.c`.
   - `metal/flash_attn.metal` still exists (the app probes for it at runtime).
5. `git add DS4MacOS/ds4-engine/upstream` and commit with the upstream range
   in the message.
```

- [ ] **Step 6: Commit**

```bash
git add DS4MacOS/ds4-engine .gitmodules
git commit -m "feat: replace vendored ds4 engine with pinned upstream submodule + embed layer"
```

---

### Task 2: SPM build against the submodule

**Files:**
- Modify: `DS4MacOS/Package.swift`

- [ ] **Step 1: Rewrite the ds4engine target**

Replace the entire `.target(name: "ds4engine", ...)` block in `DS4MacOS/Package.swift` with:

```swift
        // C/ObjC engine: pristine upstream (submodule) + local embed wrapper
        .target(
            name: "ds4engine",
            path: "ds4-engine",
            sources: [
                "embed/ds4_server_embed.c",
                "upstream/ds4.c",
                "upstream/ds4_ssd.c",
                "upstream/ds4_distributed.c",
                "upstream/ds4_metal.m",
                "upstream/ds4_help.c",
                "upstream/ds4_kvstore.c",
                "upstream/rax.c",
            ],
            resources: [
                .copy("upstream/metal"),
            ],
            publicHeadersPath: "embed/include",
            cSettings: [
                .define("DS4_SERVER_TEST_NO_MAIN"),
                .headerSearchPath("upstream"),
                .unsafeFlags([
                    "-O3", "-ffast-math", "-mcpu=native",
                    "-Wall", "-Wextra", "-std=c99",
                    "-Wno-unused-parameter", "-Wno-unused-variable",
                    "-Wno-sign-compare",
                ]),
            ],
            swiftSettings: [],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedLibrary("m"),
                .linkedLibrary("pthread"),
            ]
        ),
```

Note: `upstream/ds4_server.c` is intentionally NOT in `sources` — it compiles only via the wrapper include. Do not add it (duplicate symbols).

- [ ] **Step 2: Build and iterate the sources list**

```bash
cd DS4MacOS && swift build 2>&1 | tail -30
```

Expected: may fail with undefined symbols — upstream has grown since the original vendoring. For each undefined symbol, locate its defining file (`grep -l "symbol_name" DS4MacOS/ds4-engine/upstream/*.c`) and add `"upstream/<file>.c"` to `sources:`. Likely candidates: `ds4_web.c`, `ds4_gpu_args.c`, `ds4_tp.c`, `ds4_layer_pack.c`. Never add `ds4_cli.c`, `ds4_eval.c`, `ds4_agent.c`, `linenoise.c`, or any `.cu` file. Repeat until `swift build` succeeds. Record the final added-file list — Task 3 needs it for the Xcode project.

- [ ] **Step 3: Verify the resource bundle**

```bash
ls DS4MacOS/.build/debug/DS4MacOS_ds4engine.bundle/metal/flash_attn.metal
```

Expected: exists (the app's `metalShadersDir()` probe requires this exact path).

- [ ] **Step 4: Commit**

```bash
git add DS4MacOS/Package.swift
git commit -m "build: compile engine from upstream submodule in SPM"
```

---

### Task 3: Xcode project, CI, and README

**Files:**
- Modify: `DS4MacOS/DS4.xcodeproj/project.pbxproj`
- Modify: `.github/workflows/*.yml` (the checkout step)
- Modify: `README.md` (clone instructions)

- [ ] **Step 1: Rewrite engine paths in project.pbxproj**

```bash
sed -i '' 's|ds4-engine/Sources/ds4engine/|ds4-engine/upstream/|g' DS4MacOS/DS4.xcodeproj/project.pbxproj
```

Then fix the two references that must NOT point into upstream:

1. The `ds4engine.h` PBXFileReference: change its path from `"ds4-engine/upstream/include/ds4engine.h"` to `"ds4-engine/embed/include/ds4engine.h"`.
2. The `ds4_server.c` PBXFileReference: change `name = ds4_server.c; path = "ds4-engine/upstream/ds4_server.c"` to `name = ds4_server_embed.c; path = "ds4-engine/embed/ds4_server_embed.c"` (keep the same object ID — its PBXBuildFile entry then compiles the wrapper; update the `/* ds4_server.c */` comments on both lines to `/* ds4_server_embed.c */`).

3. Update `HEADER_SEARCH_PATHS` in BOTH build configurations (Debug and Release) to:

```
				HEADER_SEARCH_PATHS = (
					"$(SRCROOT)/ds4-engine/embed/include",
					"$(SRCROOT)/ds4-engine/upstream",
				);
```

- [ ] **Step 2: Replace the 19 individual metal file refs with one folder reference**

Upstream adds new `.metal` files over time; individual refs go stale silently, so switch the copy phase to a folder reference:

1. Delete the 19 `.metal` PBXBuildFile lines (`/* xxx.metal in Copy Metal Shaders */`), their 19 PBXFileReference lines, their entries in the group `children` list, and their entries in the "Copy Metal Shaders" phase `files` list.
2. Add one PBXFileReference (top of the PBXFileReference section):

```
		D5AA0000000000000000AA01 /* metal */ = {isa = PBXFileReference; lastKnownFileType = folder; name = metal; path = "ds4-engine/upstream/metal"; sourceTree = SOURCE_ROOT; };
```

3. Add one PBXBuildFile:

```
		D5AA0000000000000000AA02 /* metal in Copy Metal Shaders */ = {isa = PBXBuildFile; fileRef = D5AA0000000000000000AA01 /* metal */; };
```

4. In the "Copy Metal Shaders" PBXCopyFilesBuildPhase: set `dstPath = "";` (a folder reference copies the whole `metal` directory, so keeping `dstPath = metal` would produce `Resources/metal/metal/`), and make `files = (D5AA0000000000000000AA02 /* metal in Copy Metal Shaders */,);`.
5. Add `D5AA0000000000000000AA01 /* metal */,` to the same group `children` list the old metal refs were in.

- [ ] **Step 3: Add any Task-2-discovered upstream .c files to the Xcode target**

For each file Task 2 Step 2 added to Package.swift, add a PBXFileReference + PBXBuildFile pair mimicking the existing `ds4_ssd.c` entries (new IDs `D5AA0000000000000000AA10`, `AA11`, … for refs; `AA20`, `AA21`, … for build files), add the ref to the engine group `children`, and the build file to the `PBXSourcesBuildPhase` list.

- [ ] **Step 4: Build with xcodebuild**

```bash
cd DS4MacOS && xcodebuild -project DS4.xcodeproj -scheme DS4 -configuration Release -derivedDataPath ./build build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`. Then verify shaders landed:

```bash
ls DS4MacOS/build/Build/Products/Release/ds4-server-gui.app/Contents/Resources/metal/flash_attn.metal
```

- [ ] **Step 5: CI submodule checkout + README clone instructions**

In the workflow file under `.github/workflows/`, change the checkout step to:

```yaml
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: true
```

In the top-level `README.md`, update the build/clone section to use `git clone --recursive` and mention `git submodule update --init` for existing clones.

- [ ] **Step 6: Commit**

```bash
git add DS4MacOS/DS4.xcodeproj .github README.md
git commit -m "build: point Xcode project at engine submodule; fetch submodules in CI"
```

---

### Task 4: Settings model

**Files:**
- Modify: `DS4MacOS/Sources/Settings.swift`

- [ ] **Step 1: Add keys and properties**

In the `Key` enum, after `prefillChunk`:

```swift
        static let enableDSpark        = "enableDSpark"
        static let dsparkModelPath     = "dsparkModelPath"
        static let dsparkConfidence    = "dsparkConfidence"
        static let defaultMaxTokens    = "defaultMaxTokens"
```

At the end of the class, after `prefillChunk`:

```swift
    // MARK: - DSpark speculative decoding

    /// Enable --dspark (requires dsparkModelPath; incompatible with SSD streaming).
    var enableDSpark: Bool {
        get { defaults.bool(forKey: Key.enableDSpark) }
        set { defaults.set(newValue, forKey: Key.enableDSpark) }
    }

    /// DSpark support GGUF passed via --mtp.
    var dsparkModelPath: String {
        get { defaults.string(forKey: Key.dsparkModelPath) ?? "" }
        set { defaults.set(newValue, forKey: Key.dsparkModelPath) }
    }

    /// --dspark-confidence threshold, clamped to 0...1. Unset reads as the
    /// engine default 0.9; an explicit 0 is preserved (engine diagnostics mode).
    var dsparkConfidence: Double {
        get {
            guard let v = defaults.object(forKey: Key.dsparkConfidence) as? Double else { return 0.9 }
            return min(1.0, max(0.0, v))
        }
        set { defaults.set(min(1.0, max(0.0, newValue)), forKey: Key.dsparkConfidence) }
    }

    /// --tokens: default max output tokens when clients omit a limit. 0 = engine default.
    var defaultMaxTokens: Int {
        get { max(0, defaults.integer(forKey: Key.defaultMaxTokens)) }
        set { defaults.set(max(0, newValue), forKey: Key.defaultMaxTokens) }
    }
```

Do NOT touch `migrateIfNeeded()` — these keys never existed in the legacy suite. (No unit tests for Settings: it's a UserDefaults-backed singleton; behavior is covered via the arg-builder tests plus build.)

- [ ] **Step 2: Build and commit**

```bash
cd DS4MacOS && swift build && cd .. && git add DS4MacOS/Sources/Settings.swift && git commit -m "feat: add DSpark and default-max-tokens settings"
```

---

### Task 5: Pure arg builder with tests (TDD)

**Files:**
- Modify: `DS4MacOS/Package.swift` (add test target)
- Create: `DS4MacOS/Tests/DS4MacOSTests/ServerArgumentsTests.swift`
- Create: `DS4MacOS/Sources/ServerArguments.swift`
- Modify: `DS4MacOS/DS4.xcodeproj/project.pbxproj` (register the new Swift file)

- [ ] **Step 1: Add the test target to Package.swift**

After the executable target:

```swift
        .testTarget(
            name: "DS4MacOSTests",
            dependencies: ["DS4MacOS"],
            path: "Tests"
        )
```

(Test targets may depend on executable targets since Swift 5.5. If `swift test` fails with "unable to import executable module", convert `Sources/main.swift`: move its top-level statements into `@main struct DS4App { static func main() { <statements> } }`, rename the file to `App.swift`, and re-run.)

- [ ] **Step 2: Write the failing tests**

Create `DS4MacOS/Tests/DS4MacOSTests/ServerArgumentsTests.swift`:

```swift
import XCTest
@testable import DS4MacOS

final class ServerArgumentsTests: XCTestCase {

    /// Baseline config ≈ the user's manual launch command.
    private func makeConfig() -> ServerArgsConfig {
        ServerArgsConfig(
            modelPath: "/m/ds4flash.gguf",
            ctxSize: 100000,
            port: 18888,
            host: "127.0.0.1",
            enableDiskKV: true,
            kvDiskDir: "/tmp/ds4-kv",
            kvDiskSpaceMB: 8192,
            enableCORS: false,
            powerPercent: 100,
            enableSSDStreaming: false,
            ssdStreamingCacheGB: 0,
            threads: 0,
            prefillChunk: 0,
            enableDSpark: false,
            dsparkModelPath: "",
            dsparkConfidence: 0.9,
            defaultMaxTokens: 0
        )
    }

    func testBaselineMatchesLegacyBuilder() {
        let (args, warnings) = buildServerArgs(config: makeConfig(), metalParentDir: "/METAL")
        XCTAssertEqual(args, [
            "ds4-server", "--chdir", "/METAL",
            "-m", "/m/ds4flash.gguf",
            "--ctx", "100000", "--port", "18888",
            "--kv-disk-dir", "/tmp/ds4-kv", "--kv-disk-space-mb", "8192",
        ])
        XCTAssertTrue(warnings.isEmpty)
    }

    func testDSparkEnabledAddsMtpAndDspark() {
        var c = makeConfig()
        c.enableDSpark = true
        c.dsparkModelPath = "/m/dspark-support.gguf"
        let (args, warnings) = buildServerArgs(config: c, metalParentDir: "/METAL")
        XCTAssertTrue(args.contains("--dspark"))
        guard let i = args.firstIndex(of: "--mtp") else { return XCTFail("--mtp missing") }
        XCTAssertEqual(args[i + 1], "/m/dspark-support.gguf")
        XCTAssertFalse(args.contains("--dspark-confidence"), "default confidence must be elided")
        XCTAssertTrue(warnings.isEmpty)
    }

    func testDSparkCustomConfidenceIncluded() {
        var c = makeConfig()
        c.enableDSpark = true
        c.dsparkModelPath = "/m/dspark-support.gguf"
        c.dsparkConfidence = 0.7
        let (args, _) = buildServerArgs(config: c, metalParentDir: "/METAL")
        guard let i = args.firstIndex(of: "--dspark-confidence") else {
            return XCTFail("--dspark-confidence missing")
        }
        XCTAssertEqual(args[i + 1], "0.7")
    }

    func testDSparkDroppedWhenSSDStreamingEnabled() {
        var c = makeConfig()
        c.enableDSpark = true
        c.dsparkModelPath = "/m/dspark-support.gguf"
        c.enableSSDStreaming = true
        let (args, warnings) = buildServerArgs(config: c, metalParentDir: "/METAL")
        XCTAssertFalse(args.contains("--dspark"))
        XCTAssertFalse(args.contains("--mtp"))
        XCTAssertTrue(args.contains("--ssd-streaming"))
        XCTAssertEqual(warnings.count, 1)
    }

    func testTokensIncludedWhenSet() {
        var c = makeConfig()
        c.defaultMaxTokens = 1500
        let (args, _) = buildServerArgs(config: c, metalParentDir: "/METAL")
        guard let i = args.firstIndex(of: "--tokens") else { return XCTFail("--tokens missing") }
        XCTAssertEqual(args[i + 1], "1500")
    }

    func testKVDirDefaultResolution() {
        XCTAssertEqual(resolvedKVDiskDir("/tmp/x"), "/tmp/x")
        XCTAssertTrue(resolvedKVDiskDir("").hasSuffix("/.ds4/kvcache"))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd DS4MacOS && swift test 2>&1 | tail -10
```

Expected: FAIL to compile — `ServerArgsConfig` / `buildServerArgs` not defined.

- [ ] **Step 4: Write the implementation**

Create `DS4MacOS/Sources/ServerArguments.swift`:

```swift
import Foundation

// MARK: - Pure ds4-server argument construction (unit-tested; no side effects)

/// Snapshot of everything that influences the ds4-server command line.
struct ServerArgsConfig {
    var modelPath: String
    var ctxSize: Int
    var port: Int
    var host: String
    var enableDiskKV: Bool
    var kvDiskDir: String
    var kvDiskSpaceMB: Int
    var enableCORS: Bool
    var powerPercent: Int
    var enableSSDStreaming: Bool
    var ssdStreamingCacheGB: Int
    var threads: Int
    var prefillChunk: Int
    var enableDSpark: Bool
    var dsparkModelPath: String
    var dsparkConfidence: Double
    var defaultMaxTokens: Int
}

extension ServerArgsConfig {
    init(settings: Settings) {
        self.init(
            modelPath: settings.modelPath,
            ctxSize: settings.ctxSize,
            port: settings.port,
            host: settings.host,
            enableDiskKV: settings.enableDiskKV,
            kvDiskDir: settings.kvDiskDir,
            kvDiskSpaceMB: settings.kvDiskSpaceMB,
            enableCORS: settings.enableCORS,
            powerPercent: settings.powerPercent,
            enableSSDStreaming: settings.enableSSDStreaming,
            ssdStreamingCacheGB: settings.ssdStreamingCacheGB,
            threads: settings.threads,
            prefillChunk: settings.prefillChunk,
            enableDSpark: settings.enableDSpark,
            dsparkModelPath: settings.dsparkModelPath,
            dsparkConfidence: settings.dsparkConfidence,
            defaultMaxTokens: settings.defaultMaxTokens
        )
    }
}

/// KV cache dir with the documented default when unset.
func resolvedKVDiskDir(_ stored: String) -> String {
    stored.isEmpty
        ? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ds4/kvcache").path
        : stored
}

func buildServerArgs(config c: ServerArgsConfig,
                     metalParentDir: String) -> (args: [String], warnings: [String]) {
    var args = ["ds4-server"]
    var warnings: [String] = []
    args += ["--chdir", metalParentDir]
    args += ["-m", c.modelPath]
    args += ["--ctx", String(c.ctxSize)]
    args += ["--port", String(c.port)]
    if c.host != "127.0.0.1" && !c.host.isEmpty {
        args += ["--host", c.host]
    }
    if c.enableDiskKV {
        args += ["--kv-disk-dir", resolvedKVDiskDir(c.kvDiskDir)]
        args += ["--kv-disk-space-mb", String(c.kvDiskSpaceMB)]
    }
    if c.enableCORS { args += ["--cors"] }
    if c.powerPercent < 100 { args += ["--power", String(c.powerPercent)] }
    if c.enableSSDStreaming {
        args += ["--ssd-streaming"]
        if c.ssdStreamingCacheGB > 0 {
            args += ["--ssd-streaming-cache-experts", "\(c.ssdStreamingCacheGB)GB"]
        }
    }
    if c.threads > 0 { args += ["--threads", String(c.threads)] }
    if c.prefillChunk > 0 { args += ["--prefill-chunk", String(c.prefillChunk)] }
    if c.enableDSpark {
        if c.enableSSDStreaming {
            // Engine refuses --ssd-streaming with --mtp; SSD streaming wins because
            // dropping it could make the model not fit in memory.
            warnings.append("DSpark is incompatible with SSD streaming — starting without DSpark.")
        } else {
            args += ["--mtp", c.dsparkModelPath, "--dspark"]
            if c.dsparkConfidence != 0.9 {
                args += ["--dspark-confidence", String(c.dsparkConfidence)]
            }
        }
    }
    if c.defaultMaxTokens > 0 { args += ["--tokens", String(c.defaultMaxTokens)] }
    return (args, warnings)
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd DS4MacOS && swift test 2>&1 | tail -5
```

Expected: `Test Suite 'All tests' passed`, 6 tests.

- [ ] **Step 6: Register ServerArguments.swift in the Xcode project**

In `project.pbxproj`, find the PBXFileReference and PBXBuildFile lines for `ServerManager.swift` and add parallel entries:

```
		D5AA0000000000000000AA03 /* ServerArguments.swift */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; name = ServerArguments.swift; path = Sources/ServerArguments.swift; sourceTree = SOURCE_ROOT; };
```

(Match the `path`/`sourceTree` style of the existing `ServerManager.swift` entry exactly — if it uses `path = ServerArguments.swift` inside a `Sources` group, do that instead.)

```
		D5AA0000000000000000AA04 /* ServerArguments.swift in Sources */ = {isa = PBXBuildFile; fileRef = D5AA0000000000000000AA03 /* ServerArguments.swift */; };
```

Add `AA03` to the same group `children` as `ServerManager.swift` and `AA04` to the `PBXSourcesBuildPhase` files list. Verify: `xcodebuild -project DS4.xcodeproj -scheme DS4 -configuration Release build` succeeds.

- [ ] **Step 7: Commit**

```bash
git add DS4MacOS/Package.swift DS4MacOS/Tests DS4MacOS/Sources/ServerArguments.swift DS4MacOS/DS4.xcodeproj
git commit -m "feat: extract pure server-arg builder with DSpark/tokens support + first test target"
```

---

### Task 6: Wire ServerManager to the new builder

**Files:**
- Modify: `DS4MacOS/Sources/ServerManager.swift` (start() validation + buildArgs replacement)
- Modify: all four `DS4MacOS/Sources/Resources/*.lproj/Localizable.strings` (one new error key)

- [ ] **Step 1: Add the dspark error string to all four locales**

Append to the `/* ServerManager - error status (UI-facing) */` section (create the section at end of file for ja):

en: `"server.error.dspark_invalid" = "DSpark support model file invalid or not found: %@";`
ja: `"server.error.dspark_invalid" = "DSpark サポートモデルファイルが無効または見つかりません：%@";`
zh-Hans: `"server.error.dspark_invalid" = "DSpark 支持模型文件无效或不存在：%@";`
zh-Hant: `"server.error.dspark_invalid" = "DSpark 支援模型檔案無效或不存在：%@";`

- [ ] **Step 2: Add dspark validation to start()**

In `ServerManager.start()`, directly after the existing metal-shaders guard (`guard let metalDir = metalShadersDir() else { ... }`), insert:

```swift
        // DSpark support file must be valid when it will actually be used
        // (SSD streaming disables DSpark — see buildServerArgs).
        if settings.enableDSpark && !settings.enableSSDStreaming {
            let dsparkPath = settings.dsparkModelPath
            let dsparkSize = (try? FileManager.default
                .attributesOfItem(atPath: dsparkPath)[.size] as? Int64 ?? 0) ?? 0
            if dsparkPath.isEmpty || dsparkSize <= 1_048_576 {
                let msg = L("server.error.dspark_invalid", dsparkPath)
                status = .error(msg)
                LogWindowController.shared.append("[ERROR] \(msg)\n")
                return
            }
        }
```

- [ ] **Step 3: Replace buildArgs with the pure builder**

Delete the whole `private func buildArgs(settings:metalParentDir:)` method. Replace its call site (`let args = buildArgs(settings: settings, metalParentDir: metalDir)`) with:

```swift
        let config = ServerArgsConfig(settings: settings)
        if config.enableDiskKV {
            try? FileManager.default.createDirectory(
                atPath: resolvedKVDiskDir(config.kvDiskDir),
                withIntermediateDirectories: true)
        }
        let (args, warnings) = buildServerArgs(config: config, metalParentDir: metalDir)
        for w in warnings { LogWindowController.shared.append("[WARN] \(w)\n") }
```

- [ ] **Step 4: Build, test, commit**

```bash
cd DS4MacOS && swift build && swift test 2>&1 | tail -3
cd .. && git add DS4MacOS/Sources/ServerManager.swift DS4MacOS/Sources/Resources
git commit -m "feat: DSpark validation and arg wiring in ServerManager"
```

---

### Task 7: Settings UI + localization

**Files:**
- Modify: `DS4MacOS/Sources/SettingsWindowController.swift`
- Modify: all four `DS4MacOS/Sources/Resources/*.lproj/Localizable.strings`

- [ ] **Step 1: Add the new strings to all four locales**

en.lproj (in the matching sections; create missing sections at end of file for ja):

```
"settings.group.dspark" = "Speculative Decoding (DSpark)";
"settings.checkbox.dspark" = "Enable DSpark speculative decoding";
"settings.desc.dspark" = "Uses a small draft model to propose tokens the main model verifies — often much faster for code. Requires the DSpark support GGUF (~5.6 GB). Only affects greedy requests (temperature 0). Incompatible with Low-memory mode.";
"settings.label.dspark_model" = "Support Model";
"settings.placeholder.dspark_model" = "No DSpark support file — click Browse…";
"settings.label.dspark_confidence" = "Confidence";
"settings.hint.dspark_confidence" = "0–1. Blank = default (0.9)";
"settings.panel.dspark_model" = "Select DSpark Support File (.gguf)";
"settings.label.max_tokens" = "Default Max Output Tokens";
"settings.hint.max_tokens" = "Used when clients omit a limit. Blank = engine default";
```

Also update `settings.desc.ssd` (en) to:

```
"settings.desc.ssd" = "Loads model weights from SSD on demand. Uses far less RAM, but may be slower. Incompatible with DSpark speculative decoding.";
```

ja.lproj (append at end of file; ja is stale so only NEW keys are added — do not retrofit others):

```
"settings.group.dspark" = "投機的デコード（DSpark）";
"settings.checkbox.dspark" = "DSpark 投機的デコードを有効にする";
"settings.desc.dspark" = "小さなドラフトモデルがトークンを提案し、メインモデルが検証します。コードでは大幅に高速になることがあります。DSpark サポート用 GGUF（約 5.6 GB）が必要です。貪欲法リクエスト（temperature 0）のみに適用され、低メモリモードとは併用できません。";
"settings.label.dspark_model" = "サポートモデル";
"settings.placeholder.dspark_model" = "DSpark サポートファイル未選択 — 「参照…」をクリック";
"settings.label.dspark_confidence" = "信頼度しきい値";
"settings.hint.dspark_confidence" = "0–1。空欄でデフォルト (0.9)";
"settings.panel.dspark_model" = "DSpark サポートファイルを選択 (.gguf)";
"settings.label.max_tokens" = "デフォルト最大出力トークン数";
"settings.hint.max_tokens" = "クライアントが上限を指定しない場合に適用。空欄でエンジンのデフォルト";
```

zh-Hans.lproj:

```
"settings.group.dspark" = "推测解码（DSpark）";
"settings.checkbox.dspark" = "启用 DSpark 推测解码";
"settings.desc.dspark" = "使用小型草稿模型提议 token，由主模型验证——代码场景通常显著提速。需要 DSpark 支持模型文件（约 5.6 GB）。仅对贪婪解码请求（temperature 0）生效。与省内存模式不兼容。";
"settings.label.dspark_model" = "支持模型";
"settings.placeholder.dspark_model" = "未选择 DSpark 支持文件 — 点击浏览…";
"settings.label.dspark_confidence" = "置信度";
"settings.hint.dspark_confidence" = "0–1，留空使用默认值 (0.9)";
"settings.panel.dspark_model" = "选择 DSpark 支持文件 (.gguf)";
"settings.label.max_tokens" = "默认最大输出 Token 数";
"settings.hint.max_tokens" = "客户端未指定上限时生效，留空使用引擎默认值";
```

zh-Hans `settings.desc.ssd` update:

```
"settings.desc.ssd" = "按需从 SSD 加载模型权重，大幅降低内存占用，但速度可能略慢。与 DSpark 推测解码不兼容。";
```

zh-Hant.lproj:

```
"settings.group.dspark" = "推測解碼（DSpark）";
"settings.checkbox.dspark" = "啟用 DSpark 推測解碼";
"settings.desc.dspark" = "使用小型草稿模型提議 token，由主模型驗證——程式碼場景通常顯著提速。需要 DSpark 支援模型檔案（約 5.6 GB）。僅對貪婪解碼請求（temperature 0）生效。與省記憶體模式不相容。";
"settings.label.dspark_model" = "支援模型";
"settings.placeholder.dspark_model" = "未選擇 DSpark 支援檔案 — 點擊瀏覽…";
"settings.label.dspark_confidence" = "置信度";
"settings.hint.dspark_confidence" = "0–1，留空使用預設值 (0.9)";
"settings.panel.dspark_model" = "選擇 DSpark 支援檔案 (.gguf)";
"settings.label.max_tokens" = "預設最大輸出 Token 數";
"settings.hint.max_tokens" = "用戶端未指定上限時生效，留空使用引擎預設值";
```

zh-Hant `settings.desc.ssd` update:

```
"settings.desc.ssd" = "按需从 SSD 載入模型权重，大幅降低記憶體佔用，但速度可能略慢。與 DSpark 推測解碼不相容。";
```

- [ ] **Step 2: Add fields, section, and mutex to SettingsWindowController**

1. New properties after `prefillChunkField`:

```swift
    private var dsparkCheck: NSButton!
    private var dsparkPathField: NSTextField!
    private var dsparkConfidenceField: NSTextField!
    private var maxTokensField: NSTextField!
```

2. In `buildPerformanceTab()`, add the tokens row inside the Context group — change the ctx stack line to:

```swift
        maxTokensField = makeField(placeholder: "393216")
        maxTokensField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([maxTokensField.widthAnchor.constraint(equalToConstant: 100)])
        let tokensRow = formRow(label: L("settings.label.max_tokens"),
                                control: maxTokensField,
                                hint: L("settings.hint.max_tokens"))
        let ctxStack = vstack([ctxRow, ctxNote, tokensRow, noThinkCheck], spacing: 8)
```

3. Give the SSD checkbox a mutex action — change its creation line to:

```swift
        ssdStreamingCheck = makeCheckbox(L("settings.checkbox.ssd_short"))
        ssdStreamingCheck.target = self
        ssdStreamingCheck.action = #selector(ssdToggled)
```

4. Still in `buildPerformanceTab()`, after the SSD group and before the `outer` line, add the DSpark group; include it in `outer`:

```swift
        // DSpark speculative decoding group
        let dsparkBox = makeSection(title: L("settings.group.dspark"))
        dsparkCheck = makeCheckbox(L("settings.checkbox.dspark"))
        dsparkCheck.target = self
        dsparkCheck.action = #selector(dsparkToggled)
        let dsparkNote = makeNote(L("settings.desc.dspark"))

        dsparkPathField = makeField(placeholder: L("settings.placeholder.dspark_model"))
        let dsparkBrowseBtn = NSButton(title: L("settings.button.browse"),
                                       target: self, action: #selector(browseDSparkClicked))
        dsparkBrowseBtn.bezelStyle = .rounded
        dsparkBrowseBtn.translatesAutoresizingMaskIntoConstraints = false
        dsparkBrowseBtn.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        dsparkPathField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let dsparkPathRow = NSStackView(views: [dsparkPathField, dsparkBrowseBtn])
        dsparkPathRow.orientation = .horizontal
        dsparkPathRow.spacing = 8
        dsparkPathRow.translatesAutoresizingMaskIntoConstraints = false
        let dsparkModelRow = formRow(label: L("settings.label.dspark_model"),
                                     control: dsparkPathRow,
                                     hint: nil)

        dsparkConfidenceField = makeField(placeholder: "0.9")
        dsparkConfidenceField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([dsparkConfidenceField.widthAnchor.constraint(equalToConstant: 80)])
        let confidenceRow = formRow(label: L("settings.label.dspark_confidence"),
                                    control: dsparkConfidenceField,
                                    hint: L("settings.hint.dspark_confidence"))

        let dsparkStack = vstack([dsparkCheck, dsparkNote, dsparkModelRow, confidenceRow], spacing: 8)
        dsparkBox.contentView?.addSubview(dsparkStack)
        pin(dsparkStack, to: dsparkBox.contentView!, insets: NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12))

        let outer = vstack([ctxBox, gpuBox, ssdBox, dsparkBox], spacing: 12)
```

5. New actions next to `browseKVClicked`:

```swift
    @objc private func browseDSparkClicked() {
        let panel = NSOpenPanel()
        panel.title = L("settings.panel.dspark_model")
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        dsparkPathField.stringValue = url.path
    }

    // DSpark and SSD streaming are mutually exclusive (engine refuses --mtp + --ssd-streaming)
    @objc private func dsparkToggled() {
        if dsparkCheck.state == .on { ssdStreamingCheck.state = .off }
    }

    @objc private func ssdToggled() {
        if ssdStreamingCheck.state == .on { dsparkCheck.state = .off }
    }
```

6. `loadValues()` additions:

```swift
        dsparkCheck.state             = s.enableDSpark ? .on : .off
        dsparkPathField.stringValue   = s.dsparkModelPath
        dsparkConfidenceField.stringValue = s.dsparkConfidence == 0.9 ? "" : String(s.dsparkConfidence)
        maxTokensField.stringValue    = s.defaultMaxTokens > 0 ? String(s.defaultMaxTokens) : ""
```

7. `saveValues()` additions:

```swift
        s.enableDSpark        = dsparkCheck.state == .on
        s.dsparkModelPath     = dsparkPathField.stringValue.trimmingCharacters(in: .whitespaces)
        s.dsparkConfidence    = Double(dsparkConfidenceField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0.9
        s.defaultMaxTokens    = Int(maxTokensField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
```

8. Window height: change `NSRect(x: 0, y: 0, width: W, height: 500)` to `height: 640` (the Performance tab gains a section; adjust visually if clipped).

- [ ] **Step 3: Build both ways and eyeball the window**

```bash
cd DS4MacOS && swift build && swift test 2>&1 | tail -3
xcodebuild -project DS4.xcodeproj -scheme DS4 -configuration Release -derivedDataPath ./build build 2>&1 | tail -3
```

Run the app briefly (`swift run` or the built .app), open Settings → Performance: verify the DSpark section renders, checking DSpark unchecks Low-memory mode and vice versa, and nothing is clipped.

- [ ] **Step 4: Commit**

```bash
git add DS4MacOS/Sources/SettingsWindowController.swift DS4MacOS/Sources/Resources
git commit -m "feat: DSpark and max-output-tokens settings UI"
```

---

### Task 8: End-to-end verification (manual, needs real model files)

No code. Requires the main Flash GGUF and the DSpark support GGUF on disk (user has both).

- [ ] **Step 1:** Launch the app, Settings → Server: set the main model. Performance: enable DSpark, browse to the support GGUF, set Default Max Output Tokens = 1500. Storage: enable session cache. Apply.
- [ ] **Step 2:** In the log window, verify the args line contains `--mtp <path> --dspark --tokens 1500` and the server reaches "Running".
- [ ] **Step 3:** Send a greedy request (`temperature: 0`) with a code-continuation prompt via `curl` to the OpenAI endpoint; confirm a response and note tokens/sec from the server log.
- [ ] **Step 4:** Disable DSpark, Apply (server restarts), repeat the same request; compare tokens/sec. DSpark run should be faster on predictable code output (context-dependent — "no slower" is acceptable; a crash or refusal to start is a failure).
- [ ] **Step 5:** Negative test: enable DSpark with a bogus path; verify start fails with the localized "DSpark support model file invalid" error and no crash.
- [ ] **Step 6:** Mutex test: enable Low-memory mode (this unchecks DSpark), Apply; verify server starts with `--ssd-streaming` and no `--mtp`/`--dspark` in the args line.

---

## Self-review notes

- Spec coverage: submodule + embed (Tasks 1–2), xcodeproj + CI + READMEs (Task 3), settings (Task 4), pure builder + first tests (Task 5), validation/wiring/mutex backstop (Task 6), UI + 4-locale strings + mutex (Task 7), manual E2E incl. tok/s comparison (Task 8).
- Deliberate deviations from spec: none.
- Type names used consistently: `ServerArgsConfig`, `buildServerArgs(config:metalParentDir:)`, `resolvedKVDiskDir(_:)`.
