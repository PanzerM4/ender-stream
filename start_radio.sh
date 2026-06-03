#!/bin/bash
set -e

CD_DIR="/radio"
cd "$CD_DIR"

# --- 1. Очистка старых процессов ---
pkill -9 -f "ffmpeg" || true
pkill -9 -f "http.server" || true

# --- 2. Проверки файлов ---
if ! ls *.mp3 >/dev/null 2>&1; then
  echo "Нет mp3-файлов в /radio"
  exit 1
fi

if [ ! -f bg.jpg ]; then
  echo "Нет bg.jpg в /radio"
  exit 1
fi

# Проверка, что bg.jpg действительно JPEG (сигнатура FF D8 FF)
JPEG_SIG=$(head -c 3 bg.jpg | xxd -p)
if [ "$JPEG_SIG" != "ffd8ff" ]; then
  echo "ОШИБКА: bg.jpg не является JPEG-файлом (сигнатура: $JPEG_SIG)"
  echo "Первые 16 байт файла:"
  head -c 16 bg.jpg | xxd
  exit 1
fi

echo "=== Файлы в порядке ==="

# --- 3. HTTP-заглушка для Render (порт из переменной окружения) ---
PORT=${PORT:-10000}
python3 -m http.server "$PORT" >/dev/null 2>&1 &
HTTP_PID=$!
trap "kill $HTTP_PID 2>/dev/null" EXIT

# --- 4. Вспомогательные функции ---

# Получить название трека (тег title или имя файла)
get_title() {
  local file="$1"
  title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
  if [ -z "$title" ]; then
    title=$(basename "$file" .mp3)
    title=${title//_/ }
  fi
  # Убираем одиночные кавычки, чтобы не сломать drawtext
  title=${title//\'/}
  echo "$title"
}

# Построить видео фильтр с отображением названий треков
# Входные параметры: длительности треков (в секундах) и соответствующие названия
build_video_filter() {
  local -a durations=("${@:1:$#/2}")
  local -a titles=("${@:$#/2+1}")
  local n=${#durations[@]}

  # Расчет временных меток с учетом кроссфейда 3 сек
  local starts=()
  local ends=()
  local cumulative=${durations[0]}
  starts[0]=0
  ends[0]=$cumulative

  for ((i=1; i<n; i++)); do
    # Начало i-го названия: (сумма до этого) - i*3 (наложение кроссфейдов)
    starts[$i]=$(( cumulative - i * 3 ))
    # Конец предыдущего названия = начало текущего
    ends[$((i-1))]=${starts[$i]}
    cumulative=$(( cumulative + durations[i] ))
  done

  # Общая длительность склеенного аудио с учетом кроссфейдов
  local total=$(( cumulative - (n-1) * 3 ))
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

# Построить аудио фильтр acrossfade для N треков
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

# --- 5. Бесконечный цикл вещания ---
while true; do
  echo "--- Формирование нового плейлиста ---"

  # Перемешиваем все mp3
  mapfile -t ALL_MP3 < <(ls *.mp3 | shuf 2>/dev/null || ls *.mp3 | sort -R 2>/dev/null || ls *.mp3)
  if [ ${#ALL_MP3[@]} -eq 0 ]; then
    echo "Нет mp3 файлов!"
    sleep 10
    continue
  fi

  # Целевая длительность ~4 часа (14400 секунд)
  TARGET_SEC=$((4*3600))
  TOTAL_DUR=0
  PLAYLIST=()
  DURATIONS=()
  TITLES=()

  for f in "${ALL_MP3[@]}"; do
    DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
    DUR=${DUR%.*}   # целые секунды
    [ "$DUR" -le 0 ] && continue

    PLAYLIST+=("$f")
    DURATIONS+=("$DUR")
    TITLES+=("$(get_title "$f")")
    TOTAL_DUR=$((TOTAL_DUR + DUR))

    # Если набрали >= 4 часов, прекращаем добавлять треки
    if [ $TOTAL_DUR -ge $TARGET_SEC ]; then
      break
    fi
  done

  echo "Выбрано ${#PLAYLIST[@]} треков, общая длительность ~${TOTAL_DUR} секунд"

  # Входные файлы: сначала картинка, потом все mp3
  INPUTS=("-loop" "1" "-r" "5" "-i" "bg.jpg")
  for f in "${PLAYLIST[@]}"; do
    INPUTS+=("-i" "$f")
  done

  N_AUDIO=${#PLAYLIST[@]}

  # Генерация фильтров
  AUDIO_FILTER=$(build_acrossfade_filter $N_AUDIO)
  VIDEO_FILTER=$(build_video_filter "${DURATIONS[@]}" "${TITLES[@]}")

  FULL_FILTER="${AUDIO_FILTER}; ${VIDEO_FILTER}"

  # Стрим-ключ YouTube (лучше через переменную окружения)
  YT_KEY="${YT_KEY:-4ux7-0ay8-816w-cxrb-1j24}"   # <--- замени на свой ключ!
  RTMP_URL="rtmp://a.rtmp.youtube.com/live2/${YT_KEY}"

  echo "Запуск ffmpeg для RTMP: ${RTMP_URL}"
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
