#!/bin/bash
set -e

# Полное отключение интерактивного ввода внутри самого ffmpeg
export FFMPEG_FORCE_TEXT_STATUS=1

CD_DIR="/radio"
cd "$CD_DIR"

# Очищаем память от старых зависших процессов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
rm -f playlist.txt

# Фоновое веб-окно для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

echo "Создаем плейлист треков..."
# Находим все mp3, перемешиваем и форматируем для ffmpeg
find . -maxdepth 1 -name "*.mp3" | shuf | sed "s|^\./|file '/radio/|; s|$|'|" > playlist.txt

while true; do
  echo "Запуск стабильной трансляции на YouTube..."
  
  # ОДИН ПРОЦЕСС FFMPEG: Стрим в качестве 480p с фиксированной надписью.
  # Это гарантирует, что музыка не будет тормозить на бесплатном сервере.
  ffmpeg -v error -nostdin -y \
    -loop 1 -r 5 -i bg.jpg \
    -f concat -safe 0 -stream_loop -1 -i playlist.txt \
    -vf "scale=854:480,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='RADIO LIVE':x=(w-tw)/2:y=h-50:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 32 -b:v 400k -maxrate 400k -bufsize 800k \
    -pix_fmt yuv420p -g 15 -c:a aac -b:a 128k -ar 44100 -ac 2 \
     -f flv "rtmp://a.rtmp.youtube.com/live2/4ux7-0ay8-816w-cxrb-1j24" < /dev/null

  echo "Переподключение потока через 3 секунды..."
  sleep 3
done
