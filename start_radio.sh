#!/bin/bash
set -e

export FFMPEG_FORCE_TEXT_STATUS=1
CD_DIR="/radio"
cd "$CD_DIR"

# Очищаем память от всех старых тяжелых процессов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
rm -f playlist.txt

# Фоновое веб-окно для Render (почти не ест ресурсы)
python3 -m http.server 10000 >/dev/null 2>&1 &

echo "Создаем оптимизированный плейлист..."
# Генерируем один список треков. Ютуб увидит его как непрерывное аудио.
# Файлы автоматически приводятся к единому стандарту аудио внутри плейлиста.
find . -maxdepth 1 -name "*.mp3" | shuf | sed "s|^\./|file '/radio/|; s|$|'|" > playlist.txt

echo "Запуск трансляции на YouTube..."
# ОДИН ПРОЦЕСС FFMPEG на всю систему: нагрузка на процессор упадет до минимума.
# -stream_loop -1 заставит список песен крутиться бесконечно без переключений скрипта.
ffmpeg -v error -nostdin -y \
  -loop 1 -r 2 -i bg.jpg \
  -f concat -safe 0 -stream_loop -1 -i playlist.txt \
  -vf "scale=640:360,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='RADIO LIVE':x=(w-tw)/2:y=h-40:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=8" \
  -c:v libx264 -preset ultrafast -tune stillimage -crf 35 -b:v 120k -maxrate 120k -bufsize 2000k \
  -pix_fmt yuv420p -g 4 -c:a aac -b:a 128k -ar 44100 -ac 2 \
  -f flv "rtmp://://youtube.com${YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null



