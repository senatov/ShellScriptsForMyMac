#!/bin/zsh

set -o errexit
set -o nounset
set -o pipefail

readonly SCRIPT_NAME="${0:t}"
readonly USER_AGENT='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36'

function print_usage {
	print -- "Usage: ${SCRIPT_NAME} [--crop] URL"
	print -- "Downloads one video from X/Twitter, YouTube, LiveJournal, or another yt-dlp-supported site."
}

function fail {
	print -u2 -- "❌ $1"
	exit "${2:-1}"
}

typeset input_url=''
typeset crop_enabled=false

for argument in "$@"; do
	case "$argument" in
		--crop)
			crop_enabled=true
			;;
		-h | --help)
			print_usage
			exit 0
			;;
		-*)
			fail "Unknown option: $argument" 64
			;;
		*)
			[[ -z "$input_url" ]] || fail "Only one URL can be processed at a time." 64
			input_url="$argument"
			;;
	esac
done

if [[ -z "$input_url" ]]; then
	print_usage
	exit 64
fi

for tool in ffmpeg ffprobe python3 yt-dlp; do
	command -v "$tool" >/dev/null || fail "$tool is not installed." 69
done

readonly timestamp="$(date '+%Y%m%d-%H%M%S')"
readonly output_file="${PWD}/${timestamp}.mp4"
readonly temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/twt2mp4.XXXXXX")"
readonly temporary_output="${temporary_dir}/output.mp4"

[[ ! -e "$output_file" ]] || fail "Output file already exists: $output_file" 73

function clean_up {
	[[ -d "$temporary_dir" ]] && rm -rf -- "$temporary_dir"
}

trap clean_up EXIT INT TERM HUP

function download_livejournal {
	local destination="$1"

	print -- "📺 LiveJournal detected; looking for its direct video stream..."

	python3 - "$input_url" "$destination" "$USER_AGENT" <<'PYTHON'
import html
import json
import re
import subprocess
import sys
import urllib.parse
import urllib.request

page_url, destination, user_agent = sys.argv[1:]


def fetch(url: str, referer: str | None = None) -> str:
    headers = {"User-Agent": user_agent}
    if referer:
        headers["Referer"] = referer
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace")


def normalize_url(value: str) -> str:
    return html.unescape(value.replace(r"\/", "/"))


def find_media_url(text: str) -> str | None:
    normalized = normalize_url(text)
    match = re.search(
        r"""https?://[^\s"'<>\\]+?\.(?:m3u8|mp4)(?:\?[^\s"'<>\\]*)?""",
        normalized,
        flags=re.IGNORECASE,
    )
    return match.group(0) if match else None


print(f"[LiveJournal] Fetching post: {page_url}", flush=True)
post_html = fetch(page_url)

record_match = re.search(r'data-rambler-player-id=["\'](\d+)', post_html)
if not record_match:
    record_match = re.search(r'\brecord_id=(\d+)', post_html)
if not record_match:
    raise SystemExit("[LiveJournal] record_id was not found.")

record_id = record_match.group(1)
token_match = re.search(r'data-auth-token=["\']([^"\']+)', post_html)
auth_token = html.unescape(token_match.group(1)) if token_match else ""
player_url = (
    "https://vc.videos.livejournal.com/index/player"
    f"?player=new&record_id={urllib.parse.quote(record_id)}"
)

print(f"[LiveJournal] Fetching player for record {record_id}.", flush=True)
player_html = fetch(player_url, referer=page_url)
media_url = find_media_url(player_html)

if not media_url:
    api_match = re.search(
        r"https?://([a-z0-9._-]+\.eagleplatform\.com)/records/(\d+)/attributes",
        player_html,
        flags=re.IGNORECASE,
    )
    api_urls: list[str] = []
    if api_match:
        query = urllib.parse.urlencode({"auth_token": auth_token}) if auth_token else ""
        suffix = f"?{query}" if query else ""
        api_urls.append(
            f"https://{api_match.group(1)}/records/{api_match.group(2)}/attributes.json{suffix}"
        )
    api_urls.extend(
        [
            f"https://vc.videos.livejournal.com/records/{record_id}/attributes.json",
            f"https://vc.videos.livejournal.com/api/v2/records/{record_id}",
        ]
    )

    for api_url in api_urls:
        try:
            api_response = fetch(api_url, referer="https://vc.videos.livejournal.com/")
            json.loads(api_response)
            media_url = find_media_url(api_response)
            if media_url:
                break
        except (OSError, ValueError):
            continue

if not media_url:
    raise SystemExit("[LiveJournal] No direct HLS or MP4 URL was found.")

print("[LiveJournal] Downloading the discovered stream.", flush=True)
command = [
    "ffmpeg",
    "-hide_banner",
    "-nostdin",
    "-user_agent",
    user_agent,
    "-referer",
    "https://vc.videos.livejournal.com/",
    "-i",
    media_url,
    "-map",
    "0:v:0",
    "-map",
    "0:a?",
    "-c",
    "copy",
    "-f",
    "matroska",
    destination,
]
subprocess.run(command, check=True)
PYTHON
}

function download_with_ytdlp {
	print -- "🌐 Downloading with yt-dlp: $input_url"

	yt-dlp \
		--no-playlist \
		--no-mtime \
		--merge-output-format mkv \
		--remux-video mkv \
		--user-agent "$USER_AGENT" \
		--output "${temporary_dir}/source.%(ext)s" \
		"$input_url"
}

if [[ "$input_url" == *livejournal.com* ]]; then
	readonly source_file="${temporary_dir}/source.mkv"
	download_livejournal "$source_file"
else
	download_with_ytdlp
	downloaded_files=("${temporary_dir}"/source.*(N))
	(( ${#downloaded_files} == 1 )) ||
		fail "Expected one downloaded file, found ${#downloaded_files}." 65
	readonly source_file="${downloaded_files[1]}"
fi

[[ -s "$source_file" ]] || fail "The video was not downloaded." 65

typeset -a video_filters
video_filters=()

if $crop_enabled; then
	print -- "✂️ Detecting persistent black borders..."
	readonly crop_log="${temporary_dir}/cropdetect.log"

	ffmpeg \
		-hide_banner \
		-nostdin \
		-i "$source_file" \
		-vf 'cropdetect=limit=24/255:round=2:reset=0' \
		-frames:v 300 \
		-an \
		-f null \
		- 2>"$crop_log"

	crop_filter="$(
		grep -Eo 'crop=[0-9]+:[0-9]+:[0-9]+:[0-9]+' "$crop_log" |
			sort |
			uniq -c |
			sort -nr |
			awk 'NR == 1 { print $2 }' || true
	)"

	if [[ -n "$crop_filter" ]]; then
		print -- "✂️ Applying: $crop_filter"
		video_filters=(-vf "$crop_filter")
	else
		print -u2 -- "⚠️ No reliable crop was detected; encoding without cropping."
	fi
fi

print -- "🎞️ Encoding a compatible MP4..."

ffmpeg \
	-hide_banner \
	-nostdin \
	-i "$source_file" \
	-map 0:v:0 \
	-map '0:a?' \
	-map_metadata 0 \
	-map_chapters 0 \
	"${video_filters[@]}" \
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

[[ "$output_video_codec" == h264 ]] || fail "Output validation failed: expected H.264 video."
[[ -s "$temporary_output" ]] || fail "Output validation failed: the MP4 is empty."

mv -- "$temporary_output" "$output_file"
print -- "✅ Done: $output_file"
