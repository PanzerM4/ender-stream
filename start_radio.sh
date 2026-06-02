#!/bin/bash
set -e

export FFMPEG_FORCE_TEXT_STATUS=1
CD_DIR="/radio"
cd "$CD_DIR"

# Полная очистка памяти от старых процессов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
rm -f playlist.txt

# Веб-заглушка для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

echo "Сборка музыкальной базы..."
find . -maxdepth 1 -name "*.mp3" | shuf > raw_list.txt

# Генерируем плейлист для concat без лишней нагрузки
while IFS= read -r track_path; do
  echo "file '$CD_DIR/$(basename "$track_path")'" >> playlist.txt
done < raw_list.txt
rm -f raw_list.txt

echo "Запуск ультра-эффективного стрима..."
while true; do
  # ФОКУС: -loop 1 и -r 1 выдают ровно 1 кадр в секунду.
  # -tune stillimage приказывает ffmpeg скопировать картинку один раз и «заморозить» её.
  ffmpeg -v error -nostdin -y \
    -loop 1 -r 1 -i bg.jpg \
    -f concat -safe 0 -stream_loop -1 -i playlist.txt \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 38 -b:v 50k -maxrate 50k -bufsize 1000k \
    -pix_fmt yuv420p -g 2 -c:a aac -b:a 128k -ar 44100 -ac 2 \
    -f flv "rtmp://://youtube.com${YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null

  echo "Переподключение потока через 3 секунды..."
  sleep 3
done

