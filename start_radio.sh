#!/bin/bash
set -e

# Отключаем интерактивный ввод внутри самого ffmpeg
export FFMPEG_FORCE_TEXT_STATUS=1

CD_DIR="/radio"
cd "$CD_DIR"

# Убиваем старые процессы, если они зависли
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true

# Запускаем фоновую веб-заглушку для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

# Создаем файл плейлиста перед запуском
echo "Генерируем плейлист..."
find . -maxdepth 1 -name "*.mp3" | shuf | sed "s|^\./|file '/radio/|; s|$|'|" > playlist.txt

# Бесконечный цикл трансляции
while true; do
  echo "Запуск трансляции на YouTube..."
  
  ffmpeg -v error -nostdin -y \
    -loop 1 -r 10 -i bg.jpg \
    -f concat -safe 0 -stream_loop -1 -i playlist.txt \
    -vf "scale=854:480,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='Radio Live':x=(w-tw)/2:y=h-50:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 32 -b:v 400k -maxrate 400k -bufsize 800k \
    -pix_fmt yuv420p -g 30 -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://://youtube.com{YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null

  echo "Стрим упал. Перезапуск через 3 секунды..."
  sleep 3
done
