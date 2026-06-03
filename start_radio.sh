#!/bin/bash
set -euo pipefail

CD_DIR="/radio"
cd "$CD_DIR"

# Остановка старых процессов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "http.server" || true

# Проверка mp3
if ! ls *.mp3 >/dev/null 2>&1; then
  echo "Нет mp3-файлов в /radio"
  exit 1
fi

# Фон-заглушка для Render
PORT=${PORT:-10000}
python3 -m http.server "$PORT" >/dev/null 2>&1 &
HTTP_PID=$!
trap "kill $HTTP_PID 2>/dev/null || true; rm -f audio.fifo current_title.txt" EXIT

# FIFO и файл текста
rm -f audio.fifo
mkfifo audio.fifo
echo "" > current_title.txt

echo "=== Запуск НЕПРЕРЫВНОГО радио (логирование включено) ==="

# Запуск фидера с логированием в файл
./playlist_feeder.sh > audio.fifo 2>"/tmp/feeder_$$.log" &
FEEDER_PID=$!

# Ждём появления данных в FIFO (если фидер не стартует — выход)
sleep 2
if ! kill -0 $FEEDER_PID 2>/dev/null; then
  echo "❌ Фидер не запустился, смотрите /tmp/feeder_$$.log"
  exit 1
fi

# FFmpeg с чуть более подробным выводом
ffmpeg -v warning -nostdin -y \
  -re -f image2 -loop 1 -framerate 1 -i bg.jpg \
  -f s16le -ar 44100 -ac 2 -i audio.fifo \
  -filter_complex \
    "[0:v]scale=1280:720,drawtext=textfile=current_title.txt:reload=1:x=30:y=h-80:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10:font='DejaVu Sans',format=yuv420p[video_out]" \
  -map "[video_out]" -map 1:a \
  -c:v libx264 -preset ultrafast -tune stillimage -b:v 1500k -maxrate 1500k -bufsize 3000k \
  -pix_fmt yuv420p -g 2 \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmp://a.rtmp.youtube.com/live2/${YT_KEY}" 2>"/tmp/ffmpeg_main_$$.log"

echo "❌ FFmpeg остановлен (код $?), логи в /tmp/ffmpeg_main_$$.log и /tmp/feeder_$$.log" >&2
kill $FEEDER_PID 2>/dev/null || true
