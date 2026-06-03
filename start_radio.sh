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

# Проверка и авто-создание фона (оставляем, хуже не будет)
if [ -f bg.jpg ]; then
  SIG=$(head -c 3 bg.jpg | xxd -p)
  if [ "$SIG" != "ffd8ff" ]; then
    echo "ВНИМАНИЕ: bg.jpg не JPEG (сигнатура $SIG), создаю чёрный фон"
    rm -f bg.jpg
  fi
fi
if [ ! -f bg.jpg ]; then
  ffmpeg -y -f lavfi -i color=c=black:s=1920x1080:r=1 -frames:v 1 bg.jpg 2>/dev/null
fi

PORT=${PORT:-10000}
python3 -m http.server "$PORT" >/dev/null 2>&1 &
HTTP_PID=$!
trap "kill $HTTP_PID 2>/dev/null" EXIT

echo "=== Радио с плавными переходами и названиями треков ==="

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

build_acrossfade_filter() {
  local n=$1
  if [ "$n" -eq 1 ]; then
    echo "[1:a]anull[afinal]"
    return
  fi
  local filter="[1:a][2:a]acrossfade=d=3:c1=tri:c2=tri[a1]"
  for ((i=3; i<=n; i++)); do
    filter+="; [a$((i-2))][${i}:a]acrossfade=d=3:c1=tri:c2=tri[a$((i-1))]"
  done
  filter+="; [a$((n-1))]anull[afinal]"
  echo "$filter"
}

build_video_filter() {
  local args=("$@")
  local n=$(($# / 3))
  local filter="[0:v]scale=1280:720[bg]"
  local prev="bg"
  for ((i=0; i<n; i++)); do
    local s="${args[$((i*3))]}"
    local e="${args[$((i*3+1))]}"
    local title="${args[$((i*3+2))]}"
    filter+="; [${prev}]drawtext=text='${title}':x=30:y=h-80:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10:enable='between(t,${s},${e})'[txt${i}]"
    prev="txt${i}"
  done
  filter+="; [${prev}]format=yuv420p[video_out]"
  echo "$filter"
}

while true; do
  echo "--- Формирую новый плейлист ---"
  mapfile -t ALL_MP3 < <(ls *.mp3 | shuf 2>/dev/null || ls *.mp3 | sort -R 2>/dev/null || ls *.mp3)
  if [ ${#ALL_MP3[@]} -eq 0 ]; then
    echo "Нет mp3 файлов!"
    sleep 10
    continue
  fi

  TARGET_SEC=$((4*3600))
  TOTAL_DUR=0
  PLAYLIST=()
  DURATIONS=()
  TITLES=()

  for f in "${ALL_MP3[@]}"; do
    DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
    DUR=${DUR%.*}
    [ "$DUR" -le 0 ] && continue
    PLAYLIST+=("$f")
    DURATIONS+=("$DUR")
    TITLES+=("$(get_title "$f")")
    TOTAL_DUR=$((TOTAL_DUR + DUR))
    [ $TOTAL_DUR -ge $TARGET_SEC ] && break
  done

  n=${#PLAYLIST[@]}
  echo "Выбрано треков: $n, общая длительность: ${TOTAL_DUR} сек."

  STARTS=()
  ENDS=()
  cum=${DURATIONS[0]}
  STARTS[0]=0
  ENDS[0]=$cum
  for ((i=1; i<n; i++)); do
    STARTS[$i]=$(( cum - i * 3 ))
    ENDS[$((i-1))]=${STARTS[$i]}
    cum=$(( cum + DURATIONS[i] ))
  done
  TOTAL_TIME=$(( cum - (n-1) * 3 ))
  ENDS[$((n-1))]=$TOTAL_TIME

  VIDEO_ARGS=()
  for ((i=0; i<n; i++)); do
    VIDEO_ARGS+=("${STARTS[$i]}" "${ENDS[$i]}" "${TITLES[$i]}")
  done

  # Явно указываем формат image2 для bg.jpg
  INPUTS=("-f" "image2" "-loop" "1" "-r" "5" "-i" "bg.jpg")
  for f in "${PLAYLIST[@]}"; do
    INPUTS+=("-i" "$f")
  done

  AUDIO_FILTER=$(build_acrossfade_filter $n)
  VIDEO_FILTER=$(build_video_filter "${VIDEO_ARGS[@]}")
  FULL_FILTER="${AUDIO_FILTER}; ${VIDEO_FILTER}"

  if [ -z "${YT_KEY}" ]; then
    echo "ОШИБКА: переменная YT_KEY не задана"
    exit 1
  fi

  RTMP_URL="rtmp://a.rtmp.youtube.com/live2/${YT_KEY}"
  echo "Запуск ffmpeg на ${RTMP_URL} ..."

  ffmpeg -v error -nostdin -y \
    "${INPUTS[@]}" \
    -filter_complex "$FULL_FILTER" \
    -map "[video_out]" -map "[afinal]" \
    -r 30 \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 20 -b:v 1500k -maxrate 2000k -bufsize 4000k \
    -pix_fmt yuv420p -g 60 \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$RTMP_URL"

  echo "FFmpeg остановлен. Перезапуск через 5 секунд..."
  sleep 5
done
