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
