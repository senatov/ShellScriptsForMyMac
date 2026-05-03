#!/bin/zsh

unsetopt APPEND_HISTORY
unsetopt INC_APPEND_HISTORY
unsetopt SHARE_HISTORY
setopt HIST_IGNORE_SPACE
HISTFILE=/dev/null
HISTSIZE=0
SAVEHIST=0
fc -p /dev/null

# 🧰 Зависимости: yt-dlp, ffmpeg, curl, python3

# === Проверка аргументов ===
if [ -z "$1" ]; then
    echo "❌ Использование: $0 <URL> [--crop]"
    echo "   Поддерживается: Twitter/X, YouTube, LiveJournal (livejournal.com)"
    exit 1
fi

INPUT_URL="$1"
CROP_ENABLED="no"
[[ "$2" == "--crop" ]] && CROP_ENABLED="yes"

# === Проверка утилит ===
for tool in yt-dlp ffmpeg curl python3; do
    if ! command -v $tool >/dev/null 2>&1; then
        echo "❌ $tool не установлен. Установите: brew install $tool"
        exit 2
    fi
done

# === Имена файлов ===
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
TEMP_FILE="temp_${TIMESTAMP}.mp4"
OUTPUT_FILE="${TIMESTAMP}.mp4"

echo "🌐 Скачивание видео: $INPUT_URL"

# ============================================================
# === LiveJournal: отдельный путь ===
# EaglePlatform (vc.videos.livejournal.com) не поддерживается
# yt-dlp из Европы — качаем напрямую через Python + HLS.
# ============================================================
if [[ "$INPUT_URL" == *"livejournal.com"* ]]; then
    echo "📺 Определён LiveJournal — используем прямой парсинг..."

    TEMP_PY=$(mktemp /tmp/lj_dl_XXXXXX.py)
    cat > "$TEMP_PY" <<'PYEOF'
import sys, re, ssl, urllib.request, json, os, subprocess

url = sys.argv[1]
out_file = sys.argv[2]

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def fetch(u, referer=None, post_data=None):
    req = urllib.request.Request(u, headers={"User-Agent": UA})
    if referer:
        req.add_header("Referer", referer)
    if post_data:
        req.data = post_data.encode()
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
    return urllib.request.urlopen(req, context=ctx).read().decode("utf-8", errors="replace")

# 1. Download LJ post page
print(f"[LJ] Fetching page: {url}", flush=True)
html = fetch(url)

# 2. Extract record_id
m = re.search(r'data-rambler-player-id="(\d+)"', html)
if not m:
    m = re.search(r'record_id=(\d+)', html)
if not m:
    print("[LJ] ❌ record_id не найден на странице", flush=True)
    sys.exit(1)
record_id = m.group(1)
print(f"[LJ] record_id: {record_id}", flush=True)

# 3. Extract auth token
m_token = re.search(r'data-auth-token="([^"]+)"', html)
auth_token = m_token.group(1) if m_token else ""

# 4. Get player page to find EaglePlatform host and playlist URL
player_url = f"https://vc.videos.livejournal.com/index/player?player=new&record_id={record_id}"
print(f"[LJ] Fetching player: {player_url}", flush=True)
player_html = fetch(player_url, referer=url)

# 5. Try to find HLS/MP4 in player page JSON data
hls_url = None

# Pattern: eagleplatform API attributes
m_api = re.search(r'https?://([a-z0-9._-]+\.eagleplatform\.com)/records/(\d+)/attributes', player_html)
if m_api:
    ep_host = m_api.group(1)
    ep_id = m_api.group(2)
    api_url = f"https://{ep_host}/records/{ep_id}/attributes.json"
    if auth_token:
        api_url += f"?auth_token={auth_token}"
    print(f"[LJ] Trying EaglePlatform API: {api_url}", flush=True)
    try:
        data_raw = fetch(api_url, referer="https://vc.videos.livejournal.com/")
        data = json.loads(data_raw)
        # Navigate to HLS or MP4 URL
        sources = data.get("playlist", {}).get("viewports", [{}])[0].get("medialist", [])
        for src in sources:
            if src.get("type") in ("hls", "m3u8", "video/mp4"):
                hls_url = src.get("url") or src.get("src")
                break
        if not hls_url:
            # Try flat structure
            flat = json.dumps(data)
            m_hls = re.search(r'https?://[^\s"\']+\.(?:m3u8|mp4)[^\s"\']*', flat)
            if m_hls:
                hls_url = m_hls.group(0)
    except Exception as e:
        print(f"[LJ] EaglePlatform API failed: {e}", flush=True)

# 6. Fallback: scan player HTML for direct video URLs (images excluded)
if not hls_url:
    for pattern in [
        r'https?://[^\s"\'<>]+\.m3u8[^\s"\'<>]*',
        r'https?://[^\s"\'<>]+\.mp4[^\s"\'<>]*',
    ]:
        m_url = re.search(pattern, player_html)
        if m_url:
            hls_url = m_url.group(0)
            break

# 7. Last resort: try vc.videos.livejournal.com store endpoint
if not hls_url:
    for ep in [
        f"https://vc.videos.livejournal.com/records/{record_id}/attributes.json",
        f"https://vc.videos.livejournal.com/api/v2/records/{record_id}",
    ]:
        try:
            raw = fetch(ep, referer="https://vc.videos.livejournal.com/")
            data = json.loads(raw)
            flat = json.dumps(data)
            m_hls = re.search(r'https?://[^\s"\']+\.(?:m3u8|mp4)[^\s"\']*', flat)
            if m_hls:
                hls_url = m_hls.group(0)
                break
        except Exception:
            pass

if not hls_url:
    print("[LJ] ❌ Не удалось найти прямую ссылку на видео.", flush=True)
    print("[LJ]    Возможно, vc.videos.livejournal.com заблокирован из вашей страны (Россия).", flush=True)
    print(f"[LJ]    Попробуйте вручную: {player_url}", flush=True)
    sys.exit(1)

print(f"[LJ] ✅ Найден URL: {hls_url}", flush=True)

# 8. Download via ffmpeg (handles HLS and MP4 equally)
cmd = [
    "ffmpeg", "-hide_banner", "-loglevel", "warning", "-y",
    "-user_agent", UA,
    "-referer", "https://vc.videos.livejournal.com/",
    "-i", hls_url,
    "-c", "copy",
    out_file
]
print(f"[LJ] Скачиваем через ffmpeg...", flush=True)
result = subprocess.run(cmd)
sys.exit(result.returncode)
PYEOF

    python3 "$TEMP_PY" "$INPUT_URL" "$TEMP_FILE"
    PY_EXIT=$?
    rm -f "$TEMP_PY"

    if [[ $PY_EXIT -ne 0 ]] || [[ ! -f "$TEMP_FILE" ]]; then
        echo "❌ Ошибка: Видео не скачано (LiveJournal)."
        exit 4
    fi
    echo "✅ Видео скачано: ${TEMP_FILE}"

else
    # ============================================================
    # === Стандартный путь: Twitter/X, YouTube, и всё остальное ===
    # ============================================================
    yt-dlp \
        --output "${TEMP_FILE}" \
        --no-mtime \
        --restrict-filenames \
        --merge-output-format mp4 \
        --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
        "$INPUT_URL"

    if [[ ! -f "${TEMP_FILE}" ]]; then
        echo "❌ Ошибка: Видео не скачано."
        exit 4
    fi
    echo "✅ Видео скачано: ${TEMP_FILE}"
fi

# ============================================================
# === Перекодирование / обрезка ===
# ============================================================
if [[ "$CROP_ENABLED" == "yes" ]]; then
    echo "✂️  Определение обрезки..."
    CROP_FILTER=$(ffmpeg -i "${TEMP_FILE}" -vf "cropdetect" -frames:v 100 -f null - 2>&1 | \
                  grep -o "crop=[^ ]*" | sort | uniq -c | sort -nr | head -n 1 | cut -d' ' -f2)
    echo "🔧 Применение crop: $CROP_FILTER"
    ffmpeg -hide_banner -loglevel error -y \
        -i "${TEMP_FILE}" \
        -vf "${CROP_FILTER}" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k \
        "${OUTPUT_FILE}"
else
    ffmpeg -hide_banner -loglevel error -y \
        -i "${TEMP_FILE}" \
        -c:v libx264 -preset fast -crf 23 \
        -c:a aac -b:a 128k \
        "${OUTPUT_FILE}"
fi

if [[ $? -ne 0 ]]; then
    echo "❌ Ошибка при обработке видео."
    rm -f "${TEMP_FILE}"
    exit 5
fi

rm -f "${TEMP_FILE}"
echo "✅ Готово: ${OUTPUT_FILE}"
