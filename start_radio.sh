#!/bin/bash
set -e

CD_DIR="/radio"
cd "$CD_DIR"

pkill -9 -f "ffmpeg" || true
pkill -9 -f "http.server" || true

if ! ls *.mp3 >/dev/null 2>&1; then
  echo "Нет mp3-файлов в /radio"
  exit 1
fi

if [ ! -f bg.jpg ]; then
  echo "Файл bg.jpg не найден, создаю чёрный фон 1920x1080..."
  ffmpeg -y -f lavfi -i color=c=black:s=1920x1080:r=1 -frames:v 1 bg.jpg 2>/dev/null
fi

PORT=${PORT:-10000}
python3 -m http.server "$PORT" >/dev/null 2>&1 &
HTTP_PID=$!
trap "kill $HTTP_PID 2>/dev/null" EXIT

echo "=== Радио с названиями треков (Стабильный поток) ==="

get_title() {
  local file="$1"
  artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
  title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
  if [ -n "$artist" ] && [ -n "$title" ]; then
    echo "${artist} - ${title}"
  elif [ -n "$title" ]; then
    echo "$title"
  elif [ -n "$artist" ]; then
    echo "$artist"
  else
    basename "$file" .mp3 | tr '_' ' '
  fi | sed "s/'//g"
}

generate_playlist_and_timings() {
  local target_sec=$1
  local total_dur=0
  PLAYLIST=()
  STARTS=()
  ENDS=()
  TITLES=()

  mapfile -t ALL_MP3 < <(ls *.mp3 | shuf 2>/dev/null || ls *.mp3 | sort -R 2>/dev/null || ls *.mp3)

  for f in "${ALL_MP3[@]}"; do
    DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
    DUR=${DUR%.*}
    [ "$DUR" -le 0 ] && continue
    PLAYLIST+=("$f")
    TITLES+=("$(get_title "$f")")
    STARTS+=("$total_dur")
    total_dur=$((total_dur + DUR))
    ENDS+=("$total_dur")
    [ $total_dur -ge $target_sec ] && break
  done
  TOTAL_TIME=$total_dur
}

while true; do
  echo "--- Формирую новый плейлист (~4 часа) ---"
  TARGET_SEC=$((4*3600))
  generate_playlist_and_timings $TARGET_SEC

  n=${#PLAYLIST[@]}
  if [ $n -eq 0 ]; then
    echo "Нет mp3 файлов!"
    sleep 10
    continue
  fi
  echo "Выбрано треков: $n, общая длительность: ${TOTAL_TIME} сек."

  VIDEO_FILTER="[0:v]scale=1280:720[bg]"
  prev="bg"
  for ((i=0; i<n; i++)); do
    s="${STARTS[$i]}"
    e="${ENDS[$i]}"
    title="${TITLES[$i]}"
    VIDEO_FILTER+="; [${prev}]drawtext=text='${title}':x=30:y=h-80:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10:enable='between(t,${s},${e})'[txt${i}]"
    prev="txt${i}"
  done
  VIDEO_FILTER+="; [${prev}]format=yuv420p,noise=alls=2:allf=t[video_out]"

  PLAYLIST_FILE="playlist_$$.txt"
  for f in "${PLAYLIST[@]}"; do
    echo "file '$(pwd)/$f'" >> "$PLAYLIST_FILE"
  done

  if [ -z "${YT_KEY}" ]; then
    echo "ОШИБКА: переменная YT_KEY не задана"
    exit 1
  fi
  RTMP_URL="rtmp://a.rtmp.youtube.com/live2/${YT_KEY}"

  echo "Запуск ffmpeg на ${RTMP_URL} ..."
  ffmpeg -v error -nostdin -y \
    -re -f image2 -loop 1 -framerate 30 -i bg.jpg \
    -re -f concat -safe 0 -i "$PLAYLIST_FILE" \
    -filter_complex "$VIDEO_FILTER" \
    -map "[video_out]" -map 1:a \
    -r 30 \
    -c:v libx264 -preset ultrafast \
    -b:v 3000k -minrate 3000k -maxrate 3000k -bufsize 6000k \
    -pix_fmt yuv420p -g 60 \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$RTMP_URL"

  rm -f "$PLAYLIST_FILE"
  echo "FFmpeg остановлен. Перезапуск через 5 секунд..."
  sleep 5
done
