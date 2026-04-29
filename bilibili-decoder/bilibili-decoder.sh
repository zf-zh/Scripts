#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

usage() {
    echo "Usage: $0 -i <source_dir> -o <output_dir>" >&2
    exit 1
}

from=""
to=""

while getopts ":i:o:" opt; do
    case $opt in
        i) from="$OPTARG" ;;
        o) to="$OPTARG" ;;
        :) echo "Error: option -$OPTARG requires an argument" >&2; usage ;;
        \?) echo "Error: unknown option -$OPTARG" >&2; usage ;;
    esac
done

[[ -z "$from" || -z "$to" ]] && { echo "Error: -i and -o are required" >&2; usage; }
[[ ! -d "$from" ]] && { echo "Error: source directory '$from' does not exist" >&2; exit 1; }
mkdir -p "$to" || { echo "Error: cannot create output directory '$to'" >&2; exit 1; }

for dir in "$from"/*/; do
    dir="${dir%/}"

    name=$(jq -r '.title' "$dir/videoInfo.json" | sed 's/[<>:"/\\|?*]//g')

    find "$dir" -maxdepth 1 \( \
        -name 'dm*' -o -name '*.jpg' -o -name '*.png' -o -name '*.json' \
        -o -name 'view' -o -name '.playurl' -o -name '.videoInfo' \
    \) -delete

    count=0
    for file in "$dir"/*; do
        [[ -f "$file" ]] || continue
        (( ++count ))
        tail -c +10 "$file" > "$dir/${count}.m4s"
        rm "$file"
    done

    echo "Merging: $name"
    ffmpeg -loglevel warning -i "$dir/1.m4s" -i "$dir/2.m4s" \
        -c copy "$to/${name}.mp4"
done
