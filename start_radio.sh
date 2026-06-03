#!/bin/bash
set -e

CD_DIR="/radio"
cd "$CD_DIR"

# --- Очистка старых процессов ---
pkill -9 -f "ffmpeg" || true
pkill -9 -f "http.server" || true

# --- Проверки ---
if ! ls *.mp3 >/dev/null 2>&1; then
  echo "Нет mp3-файлов в /radio"
  exit 1
fi

if [ ! -f bg.jpg ]; then
  echo "Нет bg.jpg в /radio"
  exit 1
fi

JPEG_SIG=$(head -c 3 bg.jpg | xxd -p)
if [ "$JPEG_SIG" != "ffd8ff" ]; then
  echo "ОШИБКА: bg.jpg не является JPEG (сигнатура: $JPEG_SIG)"
  exit 1
fi

echo "=== Файлы в порядке ==="

# --- HTTP-заглушка ---
PORT=${PORT:-10000}
python3 -m http.server "$PORT" >/dev/null 2>&1 &
HTTP_PID=$!
trap "kill $HTTP_PID 2>/dev/null" EXIT

# --- Функции ---

# Получить название трека
get_title() {
  local file="$1"
  title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
  if [ -z "$title" ]; then
    title=$(basename "$file" .mp3)
    title=${title//_/ }
  fi
  title=${title//\'/}
  echo "$title"
}

# Построить видеофильтр с названиями (start, end и title теперь передаются как аргументы)
# Аргументы: start1 end1 title1 start2 end2 title2 ...
build_video_filter() {
  local args=("$@")
  local n=$(($# / 3))
  
  local filter="[0:v]scale=1280:720[bg]"
  local prev="bg"
  for ((i=0; i<n; i++)); do
    local s="${args[$((i*3))]}"
    local e="${args[$((i*3+1))]}"
    local title="${args[$((i*3+2))]}"
    # Защита от пустых значений
    if [ -z "$s" ] || [ -z "$e" ]; then
      echo "ОШИБКА: пустое время для трека '$title'" >&2
      exit 1
    fi
    local enable_str="between(t,${s},${e})"
    local label="txt${i}"
    filter+="; [${prev}]drawtext=text='${title}':x=30:y=h-80:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10:enable='${enable_str}'[${label}]"
    prev="${label}"
  done
  filter+="; [${prev}]format=yuv420p[video_out]"
  echo "$filter"
}

# Кроссфейд
build_acrossfade_filter() {
  local n=$1
  if [ "$n" -eq 1 ]; then
    echo "[1:a]anull[afinal]"
    return
  fi
  local filter="[1:a][2:a]acrossfade=d=3:c1=tri:c2=tri[a1]"
  for ((i=3; i<=n; i++)); do
    local prev=$((i-2))
    filter+="; [a${prev}][${i}:a]acrossfade=d=3:c1=tri:c2=tri[a$((i-1))]"
  done
  filter+="; [a$((n-1))]anull[afinal]"
  echo "$filter"
}

# --- Главный цикл вещания ---
while true; do
  echo "--- Формирование нового плейлиста ---"

  mapfile -t ALL_MP3 < <(ls *.mp3 | shuf 2>/dev/null || ls *.mp3 | sort -R 2>/dev/null || ls *.mp3)
  if [ ${#ALL_MP3[@]} -eq 0 ]; then
    echo "Нет mp3 файлов!"
    sleep 10
    continue
  fi

  TARGET_SEC=$((4*3600))   # ~4 часа
  TOTAL_DUR=0
  PLAYLIST=()
  DURATIONS=()
  TITLES=()

  for f in "${ALL_MP3[@]}"; do
    DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
    DUR=${DUR%.*}   # целые секунды
    if [ "$DUR" -le 0 ]; then continue; fi
    PLAYLIST+=("$f")
    DURATIONS+=("$DUR")
    TITLES+=("$(get_title "$f")")
    TOTAL_DUR=$((TOTAL_DUR + DUR))
    if [ $TOTAL_DUR -ge $TARGET_SEC ]; then
      break
    fi
  done

  n=${#PLAYLIST[@]}
  echo "Выбрано треков: $n, общая длительность: ${TOTAL_DUR} сек."

  # Рассчитываем времена начала и конца для каждого названия
  STARTS=()
  ENDS=()
  local cum=${DURATIONS[0]}
  STARTS[0]=0
  ENDS[0]=$cum
  for ((i=1; i<n; i++)); do
    # Начало i-го названия: сумма предыдущих длительностей минус i*3 (перекрытие кроссфейдов)
    STARTS[$i]=$(( cum - i * 3 ))
    ENDS[$((i-1))]=${STARTS[$i]}
    cum=$(( cum + DURATIONS[i] ))
  done
  # Общая длительность склеенного аудио
  TOTAL_TIME=$(( cum - (n-1) * 3 ))
  ENDS[$((n-1))]=$TOTAL_TIME

  # Проверка, что все времена не пусты и монотонны
  for ((i=0; i<n; i++)); do
    if [ -z "${STARTS[$i]}" ] || [ -z "${ENDS[$i]}" ]; then
      echo "ОШИБКА: пустое время для трека $i" >&2
      exit 1
    fi
    if [ "${STARTS[$i]}" -ge "${ENDS[$i]}" ]; then
      echo "ОШИБКА: start >= end для трека $i (${TITLES[$i]})" >&2
      exit 1
    fi
  done

  # Собираем аргументы для видеофильтра: start1 end1 title1 start2 end2 title2 ...
  VIDEO_ARGS=()
  for ((i=0; i<n; i++)); do
    VIDEO_ARGS+=("${STARTS[$i]}" "${ENDS[$i]}" "${TITLES[$i]}")
  done

  # Входы
  INPUTS=("-loop" "1" "-r" "5" "-i" "bg.jpg")
  for f in "${PLAYLIST[@]}"; do
    INPUTS+=("-i" "$f")
  done

  AUDIO_FILTER=$(build_acrossfade_filter $n)
  VIDEO_FILTER=$(build_video_filter "${VIDEO_ARGS[@]}")

  FULL_FILTER="${AUDIO_FILTER}; ${VIDEO_FILTER}"

  YT_KEY="${YT_KEY:-4ux7-0ay8-816w-cxrb-1j24}"   # замени на свой ключ!
  RTMP_URL="rtmp://a.rtmp.youtube.com/live2/${YT_KEY}"

  echo "Запуск ffmpeg..."
  ffmpeg -v error -nostdin -y \
    "${INPUTS[@]}" \
    -filter_complex "$FULL_FILTER" \
    -map "[video_out]" -map "[afinal]" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 20 -b:v 1500k -maxrate 2000k -bufsize 4000k \
    -pix_fmt yuv420p -g 10 \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "$RTMP_URL"

  echo "FFmpeg завершил работу. Перезапуск через 5 секунд..."
  sleep 5
done
