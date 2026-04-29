# Scripts

This repsitory contains some useless scripts.

## fdu-connect-service-wrapper

A wrapper for [fdu-connect](https://github.com/AkiraSalvare/fdu-connect) to run it as a service. It is designed to be used with [systemd](https://systemd.io) on Linux or [launchd](https://developer.apple.com/documentation/xpc/launchd) on macOS.


## bilibili-decoder

Converts Bilibili offline downloads into regular, playable `.mp4` files that can be opened in any video player. Point it at the folder Bilibili downloaded into, pick an output folder, and it converts everything in one batch. It requires `ffmpeg` to be installed and available in the system `PATH`.

Two versions are available:
- **Bash** (`bilibili-decoder.sh`) — processes one video at a time, with `-i`/`-o` flags for input and output directories. It uses `jq` for JSON parsing, so make sure to have it installed before running the script.
- **Swift** (`bilibili-decoder.swift`) — faster batch processing in parallel, with per-video error reporting. Compile once with `swiftc -O bilibili-decoder.swift -o bilibili-decoder`, then run with the following options:
    - `-i <dir>` — source directory containing Bilibili download subfolders. Required.
    - `-o <dir>` — output directory for the merged `.mp4` files. Created automatically if missing. Required.
    - `-j <N>` — number of videos to process in parallel. Defaults to half the CPU cores (capped at 4).
    - `-k`, `--keep` — keep the original source files after a successful merge. Without it, source files are deleted once the `.mp4` is written.
    - `-h`, `--help` — print the usage summary and exit.

