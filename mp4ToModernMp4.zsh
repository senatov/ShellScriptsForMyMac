#!/bin/zsh

set -o errexit
set -o nounset
set -o pipefail

readonly SCRIPT_NAME="${0:t}"

function print_usage {
	print -u2 -- "Usage: ${SCRIPT_NAME} INPUT.mp4"
}

function fail {
	print -u2 -- "❌ $1"
	exit "${2:-1}"
}

if (( $# != 1 )); then
	print_usage
	exit 64
fi

readonly input="$1"
[[ -f "$input" ]] || fail "File not found: $input" 66

command -v ffmpeg >/dev/null || fail "ffmpeg is not installed. Install it with: brew install ffmpeg" 69
command -v ffprobe >/dev/null || fail "ffprobe is not installed. Install it with: brew install ffmpeg" 69

readonly input_dir="${input:h}"
readonly input_stem="${input:t:r}"
readonly output="${input_dir}/${input_stem}_modern.mp4"
readonly temporary_output="${output}.part"

[[ "$input" != "$output" ]] || fail "Input and output paths are identical." 73
[[ ! -e "$output" ]] || fail "Output file already exists: $output" 73
[[ ! -e "$temporary_output" ]] || fail "Temporary file already exists: $temporary_output" 73

function clean_up {
	[[ -e "$temporary_output" ]] && rm -f -- "$temporary_output"
}

trap clean_up EXIT INT TERM HUP

print -- "🔧 Converting: $input"
print -- "📦 Output:     $output"

ffmpeg \
	-hide_banner \
	-nostdin \
	-i "$input" \
	-map 0:v:0 \
	-map '0:a?' \
	-map_metadata 0 \
	-map_chapters 0 \
	-c:v libx264 \
	-preset slow \
	-crf 23 \
	-pix_fmt yuv420p \
	-c:a aac \
	-b:a 192k \
	-movflags +faststart \
	-f mp4 \
	"$temporary_output"

readonly output_video_codec="$(
	ffprobe \
		-v error \
		-select_streams v:0 \
		-show_entries stream=codec_name \
		-of default=nokey=1:noprint_wrappers=1 \
		"$temporary_output"
)"

[[ "$output_video_codec" == "h264" ]] || fail "Output validation failed: expected H.264 video."
[[ -s "$temporary_output" ]] || fail "Output validation failed: the converted file is empty."

mv -- "$temporary_output" "$output"
trap - EXIT INT TERM HUP

print -- "✅ Conversion completed successfully."

if command -v trash >/dev/null; then
	trash -- "$input"
elif [[ "$OSTYPE" == darwin* ]] && command -v osascript >/dev/null; then
	osascript - "$input" <<'APPLESCRIPT'
on run arguments
	tell application "Finder" to delete POSIX file (item 1 of arguments)
end run
APPLESCRIPT
else
	print -u2 -- "⚠️ Original file was not removed because no supported Trash command was found:"
	print -u2 -- "   $input"
	exit 70
fi

print -- "🗑️ Original moved to Trash."
