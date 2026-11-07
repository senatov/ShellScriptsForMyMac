#!/usr/bin/env -S zsh -f
# Download an X/Twitter video or convert a local video to a size-limited GIF.
set -o errexit
set -o nounset
set -o pipefail

function usage {
  print -u2 -- "Usage: ${0:t} <URL|video-file> [--crop] [--start TIME] [--duration SECONDS] [--cookies-from-browser BROWSER] [--max-size MB]"
  print -u2 -- "Uses gifski when installed, otherwise FFmpeg's palette encoder."
}
function fail { print -u2 -- "❌ $1"; exit "${2:-1}"; }
function file_size { stat -f%z "$1" 2>/dev/null || wc -c < "$1"; }

input=''
crop=false
start=''
duration=''
cookies=()
max_bytes=$((19 * 1024 * 1024 + 512 * 1024))
while (( $# )); do
  case "$1" in
    --crop) crop=true; shift ;;
    --start|--duration|--cookies-from-browser|--max-size)
      (( $# >= 2 )) || fail "Missing value after $1" 64
      option="$1"; value="$2"; shift 2
      case "$option" in
        --start) start="$value" ;;
        --duration) duration="$value" ;;
        --cookies-from-browser) cookies=(--cookies-from-browser "$value") ;;
        --max-size) [[ "$value" == <-> ]] || fail "--max-size must be a positive number of MB." 64; (( value > 0 )) || fail "--max-size must be positive." 64; max_bytes=$(( value * 1024 * 1024 )) ;;
      esac ;;
    -h|--help) usage; exit 0 ;;
    -*) fail "Unknown option: $1" 64 ;;
    *) [[ -z "$input" ]] || fail "Provide exactly one input." 64; input="$1"; shift ;;
  esac
done
[[ -n "$input" ]] || { usage; exit 64; }
command -v ffmpeg >/dev/null || fail "ffmpeg is not installed." 69
command -v ffprobe >/dev/null || fail "ffprobe is not installed." 69
is_url=false
[[ "$input" == (http|https)://* || "$input" == x.com/* || "$input" == twitter.com/* ]] && is_url=true
if $is_url; then
  command -v yt-dlp >/dev/null || fail "yt-dlp is required for URL downloads." 69
elif [[ ! -f "$input" ]]; then fail "File not found: $input" 66
fi

stamp="$(date '+%Y%m%d-%H%M%S')"
output="${PWD}/${stamp}.gif"
[[ ! -e "$output" ]] || fail "Output already exists: $output" 73
tmp="$(mktemp -d "${TMPDIR:-/tmp}/twt2gif.XXXXXX")" || fail "Could not create temporary directory." 73
function cleanup { [[ -d "$tmp" ]] && rm -rf -- "$tmp"; }
trap cleanup EXIT INT TERM HUP
source="$input"
if $is_url; then
  print -- "📥 Downloading video..."
  yt-dlp --no-playlist --no-mtime --merge-output-format mp4 "${cookies[@]}" -o "$tmp/source.%(ext)s" "$input"
  files=("$tmp"/source.*(N))
  (( ${#files} == 1 )) || fail "Expected one downloaded video, found ${#files}." 65
  source="${files[1]}"
fi
[[ -s "$source" ]] || fail "Input video is empty or unavailable." 65

work="$source"
filters=()
if [[ -n "$start" || -n "$duration" || "$crop" == true ]]; then
  args=()
  [[ -n "$start" ]] && args+=(-ss "$start")
  args+=(-i "$source")
  [[ -n "$duration" ]] && args+=(-t "$duration")
  if $crop; then
    crop_log="$tmp/crop.log"
    ffmpeg -hide_banner -nostdin -i "$source" -vf 'cropdetect=limit=24/255:round=2:reset=0' -frames:v 300 -an -f null - 2>"$crop_log" || true
    crop_filter="$(grep -Eo 'crop=[0-9]+:[0-9]+:[0-9]+:[0-9]+' "$crop_log" | sort | uniq -c | sort -nr | awk 'NR==1 {print $2}')"
    [[ -n "$crop_filter" ]] && filters+=("$crop_filter")
  fi
  encode_filters=()
  (( ${#filters} )) && encode_filters=(-vf "${(j:,:)filters}")
  ffmpeg -hide_banner -nostdin -y "${args[@]}" "${encode_filters[@]}" -an -c:v libx264 -preset veryfast -crf 18 "$tmp/prepared.mp4"
  work="$tmp/prepared.mp4"
fi

# Start with dimensions and frame rate suited to the clip duration.
seconds="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$work" | awk '{printf "%d", $1}')"
width=640; fps=18; quality=90
(( seconds > 12 )) && width=400
(( seconds > 8 && seconds <= 12 )) && width=480
(( seconds > 0 && seconds <= 5 )) && width=720
out="$tmp/result.gif"
while true; do
  rm -f "$out"
  if command -v gifski >/dev/null 2>&1; then
    print -- "🎨 Encoding GIF with gifski (width=$width, fps=$fps, quality=$quality)..."
    gifski --quiet --output "$out" --width "$width" --fps "$fps" --quality "$quality" "$work"
  else
    print -- "🎨 Encoding GIF with FFmpeg (width=$width, fps=$fps)..."
    ffmpeg -hide_banner -loglevel error -nostdin -y -i "$work" -filter_complex "[0:v]fps=$fps,scale=$width:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=sierra2_4a" -loop 0 "$out"
  fi
  [[ -s "$out" ]] || fail "GIF encoding failed." 5
  bytes="$(file_size "$out")"
  print -- "📦 GIF size: $bytes bytes (limit: $max_bytes)"
  (( bytes <= max_bytes )) && break
  if (( width > 240 )); then width=$(( width * 9 / 10 )); (( width < 240 )) && width=240
  elif (( fps > 8 )); then fps=$(( fps - 2 ))
  elif command -v gifski >/dev/null 2>&1 && (( quality > 50 )); then quality=$(( quality - 10 ))
  else print -u2 -- "⚠️ Could not reach the size limit without severe quality loss; keeping the best result."; break
  fi
done
mv -- "$out" "$output"
print -- "✅ Done: $output"
