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
  echo "Файл bg.jpg не найден, создаю чёрный фон 1280x720..."
  ffmpeg -y -f lavfi -i color=c=black:s=1280x720:r=1 -frames:v 1 bg.jpg 2>/dev/null
fi

PORT=${PORT:-10000}
python3 -m http.server "$PORT" >/dev/null 2>&1 &
HTTP_PID=$!
sleep 2
trap "kill $HTTP_PID 2>/dev/null" EXIT

echo "=== Радио (Без нагрузки) ==="

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

while true; do
  echo "--- Формирую плейлист (~4 часа) ---"
  TARGET_SEC=$((4*3600))

  mapfile -t ALL_MP3 < <(ls *.mp3 | shuf 2>/dev/null || ls *.mp3 | sort -R 2>/dev/null || ls *.mp3)
  PLAYLIST=()
  TOTAL_DUR=0

  for f in "${ALL_MP3[@]}"; do
    DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
    DUR=${DUR%.*}
    [ "$DUR" -le 0 ] && continue
    PLAYLIST+=("$f")
    TOTAL_DUR=$((TOTAL_DUR + DUR))
    [ $TOTAL_DUR -ge $TARGET_SEC ] && break
  done

  echo "Треков: ${#PLAYLIST[@]}, длительность: ${TOTAL_DUR} сек."

  PLAYLIST_FILE="playlist_$$.txt"
  for f in "${PLAYLIST[@]}"; do
    echo "file '$(pwd)/$f'" >> "$PLAYLIST_FILE"
  done

  if [ -z "${YT_KEY}" ]; then
    echo "ОШИБКА: переменная YT_KEY не задана"
    exit 1
  fi
  RTMP_URL="rtmp://a.rtmp.youtube.com/live2/${YT_KEY}"

  # Запускаем ffmpeg в фоне, чтобы параллельно выводить названия
  echo "Запуск ffmpeg..."
  ffmpeg -v error -nostdin -y \
    -re -f image2 -loop 1 -framerate 1 -i bg.jpg \
    -re -f concat -safe 0 -i "$PLAYLIST_FILE" \
    -map 0:v -map 1:a \
    -c:v libx264 -preset ultrafast -tune stillimage -b:v 500k -maxrate 500k -bufsize 1000k \
    -pix_fmt yuv420p -g 2 \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$RTMP_URL" &
  FFMPEG_PID=$!

  # Пока работает ffmpeg, выводим названия треков (в будущем можно отправлять в API YouTube)
  for f in "${PLAYLIST[@]}"; do
    if ! kill -0 $FFMPEG_PID 2>/dev/null; then
      break
    fi
    TITLE=$(get_title "$f")
    echo "Сейчас играет: $TITLE"
    DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
    sleep ${DUR%.*}
  done

  wait $FFMPEG_PID 2>/dev/null
  rm -f "$PLAYLIST_FILE"
  echo "FFmpeg остановлен. Перезапуск через 5 секунд..."
  sleep 5
done
