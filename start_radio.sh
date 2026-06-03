#!/bin/bash
set -e

CD_DIR="/radio"
cd "$CD_DIR"

# Остановка старых процессов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "http.server" || true

# Проверки
if ! ls *.mp3 >/dev/null 2>&1; then
  echo "Нет mp3-файлов в /radio"
  exit 1
fi
if [ ! -f bg.jpg ]; then
  echo "Нет bg.jpg в /radio"
  exit 1
fi

# HTTP-заглушка для Render
PORT=${PORT:-10000}
python3 -m http.server "$PORT" >/dev/null 2>&1 &
HTTP_PID=$!
trap "kill $HTTP_PID 2>/dev/null" EXIT

echo "=== Радио с плавными переходами и названиями ==="

# Функция получения названия трека (тег title или имя файла)
get_title() {
  local file="$1"
  title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
  if [ -z "$title" ]; then
    title=$(basename "$file" .mp3)
    title=${title//_/ }
  fi
  title=${title//\'/}   # убираем одиночные кавычки, чтобы не сломать drawtext
  echo "$title"
}

# Построение видеофильтра с названиями треков
build_video_filter() {
  local -a durations=("${@:1:$#/2}")
  local -a titles=("${@:$#/2+1}")
  local n=${#durations[@]}

  # Расчет временных меток с учетом кроссфейда d=3
  local starts=()
  local ends=()
  local cumulative=${durations[0]}
  starts[0]=0
  ends[0]=$cumulative
  for ((i=1; i<n; i++)); do
    starts[$i]=$(awk "BEGIN {print $cumulative - $i * 3}")
    if [ $i -lt $((n-1)) ]; then
      ends[$((i-1))]=${starts[$i]}
    fi
    cumulative=$(awk "BEGIN {print $cumulative + ${durations[$i]}}")
  done
  local total=$(awk "BEGIN {print $cumulative - ($n-1) * 3}")
  ends[$((n-1))]=$total

  # Цепочка drawtext
  local filter="[0:v]scale=1280:720[bg]"
  local prev="bg"
  for ((i=0; i<n; i++)); do
    local s="${starts[$i]}"
    local e="${ends[$i]}"
    local title="${titles[$i]}"
    local enable_str="between(t,${s},${e})"
    local label="txt${i}"
    filter+="; [${prev}]drawtext=text='${title}':x=30:y=h-80:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10:enable='${enable_str}'[${label}]"
    prev="${label}"
  done
  filter+="; [${prev}]format=yuv420p[video_out]"
  echo "$filter"
}

# Построение аудиофильтра acrossfade
build_acrossfade_filter() {
  local n=$1
  if [ "$n" -eq 1 ]; then
    echo "[1:a]anull[afinal]"
    return
  fi
  local filter="[1:a][2:a]acrossfade=d=3:c1=tri:c2=tri[a1]"
  local i
  for ((i=3; i<=n; i++)); do
    local prev=$((i-2))
    filter+="; [a${prev}][${i}:a]acrossfade=d=3:c1=tri:c2=tri[a$((i-1))]"
  done
  filter+="; [a$((n-1))]anull[afinal]"
  echo "$filter"
}

# Главный бесконечный цикл
while true; do
  echo "--- Формирую новый плейлист ---"

  mapfile -t ALL_MP3 < <(ls *.mp3 | shuf)
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
    if [ "$DUR" -le 0 ]; then continue; fi
    PLAYLIST+=("$f")
    DURATIONS+=("$DUR")
    TITLES+=("$(get_title "$f")")
    TOTAL_DUR=$((TOTAL_DUR + DUR))
    if [ $TOTAL_DUR -ge $TARGET_SEC ]; then
      break
    fi
  done

  echo "Выбрано ${#PLAYLIST[@]} треков, общая длительность ~${TOTAL_DUR} сек."

  # Входы: картинка + аудиофайлы
  INPUTS=("-loop" "1" "-r" "5" "-i" "bg.jpg")
  for f in "${PLAYLIST[@]}"; do
    INPUTS+=("-i" "$f")
  done

  N_AUDIO=${#PLAYLIST[@]}

  AUDIO_FILTER=$(build_acrossfade_filter $N_AUDIO)
  VIDEO_FILTER=$(build_video_filter "${DURATIONS[@]}" "${TITLES[@]}")

  FULL_FILTER="${AUDIO_FILTER}; ${VIDEO_FILTER}"

  echo "Запуск ffmpeg..."
  ffmpeg -v error -nostdin -y \
    "${INPUTS[@]}" \
    -filter_complex "$FULL_FILTER" \
    -map "[video_out]" -map "[afinal]" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 20 -b:v 1500k -maxrate 2000k -bufsize 4000k \
    -pix_fmt yuv420p -g 10 \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://a.rtmp.youtube.com/live2/4ux7-0ay8-816w-cxrb-1j24"

  echo "FFmpeg остановлен. Перезапуск через 5 секунд..."
  sleep 5
done
