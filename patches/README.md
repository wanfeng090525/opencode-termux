# patches/ — forked notes (not applied by our build)

We wrap the precompiled npm `opencode-linux-arm64` binary with bun-termux-loader,
so we do **not** compile opencode from source and these two patches are **not
applied** by this repo's build. They are preserved from the reference repo
(Hope2333/opencode-termux) for whoever later switches to a source build:

- `0001-android-support.patch`  — opencode package.json tweak for Android/Bun build.
- `0002-bun-termux-cwd-fix.patch`— fixes `run_command.zig` cwd handling on Termux/Bun.

If we ever move to building from source (like the reference's build-pure-android
workflow), apply them under `packages/opencode`. Our package also pins
`bun-termux-loader` to a fixed commit for reproducibility; bump it in
`scripts/produce.sh` if you intentionally want a newer loader.
