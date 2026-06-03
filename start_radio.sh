#!/bin/bash
set -e

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

# Фон-заглушка для Render (Render требует порт)
PORT=${PORT:-10000}
python3 -m http.server "$PORT" >/dev/null 2>&1 &
HTTP_PID=$!
trap "kill $HTTP_PID 2>/dev/null; rm -f audio.fifo current_title.txt" EXIT

# Создаём FIFO для звука
rm -f audio.fifo
mkfifo audio.fifo

# Файл с названием трека (сначала пустой)
echo "" > current_title.txt

echo "=== Запуск НЕПРЕРЫВНОГО радио (плейлист обновляется каждые ~4 часа) ==="

# Запускаем фидер (он будет писать в FIFO)
./playlist_feeder.sh > audio.fifo &
FEEDER_PID=$!

# FFmpeg: видео из статичной картинки с обновляемым текстом, аудио из FIFO
ffmpeg -v error -nostdin -y \
  -re -f image2 -loop 1 -framerate 1 -i bg.jpg \
  -f s16le -ar 44100 -ac 2 -i audio.fifo \
  -filter_complex \
    "[0:v]scale=1280:720,drawtext=textfile=current_title.txt:reload=1:x=30:y=h-80:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10:font='DejaVu Sans',format=yuv420p[video_out]" \
  -map "[video_out]" -map 1:a \
  -c:v libx264 -preset ultrafast -tune stillimage -b:v 1500k -maxrate 1500k -bufsize 3000k \
  -pix_fmt yuv420p -g 2 \
  -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmp://a.rtmp.youtube.com/live2/${YT_KEY}"

# Сюда попадаем только если FFmpeg упал (ошибка)
kill $FEEDER_PID 2>/dev/null
echo "FFmpeg остановлен – проверьте логи и перезапустите."
