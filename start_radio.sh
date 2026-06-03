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

# HTTP-заглушка для Render (порт из переменной окружения)
PORT=${PORT:-10000}
python3 -m http.server "$PORT" >/dev/null 2>&1 &
HTTP_PID=$!
trap "kill $HTTP_PID 2>/dev/null" EXIT

echo "=== Радио с плавными переходами ==="

# Функция: построить filter_complex для N аудиофайлов
# Параметр: количество аудиовходов (не включая видео)
build_acrossfade_filter() {
  local n=$1
  if [ "$n" -eq 1 ]; then
    # Один трек — кроссфейд не нужен
    echo "[1:a]anull[afinal]"
    return
  fi

  # Первый переход: [1:a][2:a]acrossfade=d=3:c1=tri:c2=tri[a1]
  local filter="[1:a][2:a]acrossfade=d=3:c1=tri:c2=tri[a1]"
  local i
  for ((i=3; i<=n; i++)); do
    local prev=$((i-2))
    filter+="; [a${prev}][${i}:a]acrossfade=d=3:c1=tri:c2=tri[a$((i-1))]"
  done
  # Последний выход назовём afinal
  filter+="; [a$((n-1))]anull[afinal]"
  echo "$filter"
}

# Главный бесконечный цикл
while true; do
  echo "--- Формирую новый плейлист ---"

  # Собираем список всех mp3, перемешиваем
  mapfile -t ALL_MP3 < <(ls *.mp3 | shuf)
  if [ ${#ALL_MP3[@]} -eq 0 ]; then
    echo "Нет mp3 файлов!"
    sleep 10
    continue
  fi

  # Определяем, сколько треков взять для ~4 часов вещания
  TARGET_SEC=$((4*3600))   # 4 часа в секундах
  TOTAL_DUR=0
  PLAYLIST=()
  for f in "${ALL_MP3[@]}"; do
    # Длительность трека через ffprobe
    DUR=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
    DUR=${DUR%.*}   # отбросить дробную часть (секунды целые)
    TOTAL_DUR=$((TOTAL_DUR + DUR))
    PLAYLIST+=("$f")
    if [ $TOTAL_DUR -ge $TARGET_SEC ]; then
      break
    fi
  done

  echo "Выбрано ${#PLAYLIST[@]} треков, общая длительность ~${TOTAL_DUR} сек."

  # Строим список входов для ffmpeg: видео + аудиофайлы
  INPUTS=("-loop" "1" "-r" "5" "-i" "bg.jpg")
  for f in "${PLAYLIST[@]}"; do
    INPUTS+=("-i" "$f")
  done

  # Число аудио входов = длина плейлиста
  N_AUDIO=${#PLAYLIST[@]}

  # Генерируем видео-часть фильтра (волны + текст)
  VIDEO_FILTER="[0:v]scale=1280:720[bg]; \
                [afinal]asplit[audio_out][audio_vis]; \
                [audio_vis]showwaves=s=1280x80:mode=cline:colors=white@0.6:r=5[waves]; \
                [bg][waves]overlay=x=0:y=H-h[v_waves]; \
                [v_waves]drawtext=text='RADIO LIVE':x=30:y=h-130:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10[video_out]"

  # Аудио-кроссфейд
  ACROSSFADE_FILTER=$(build_acrossfade_filter $N_AUDIO)

  FULL_FILTER="${ACROSSFADE_FILTER}; ${VIDEO_FILTER}"

  echo "Запуск ffmpeg..."
  ffmpeg -v error -nostdin -y \
    "${INPUTS[@]}" \
    -filter_complex "$FULL_FILTER" \
    -map "[video_out]" -map "[audio_out]" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 30 -b:v 800k -maxrate 800k -bufsize 1600k \
    -pix_fmt yuv420p -g 10 \
    -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://a.rtmp.youtube.com/live2/4ux7-0ay8-816w-cxrb-1j24"

  echo "FFmpeg остановлен. Пересоздание плейлиста через 5 секунд..."
  sleep 5
done
