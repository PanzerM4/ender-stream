#!/bin/bash
set -e

export FFMPEG_FORCE_TEXT_STATUS=1
CD_DIR="/radio"
cd "$CD_DIR"

# Полная очистка старых процессов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
rm -f concat_list.txt metadata.txt

# Фоновая заглушка для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

# ФУНКЦИЯ: Генерация бесшовного аудио плейлиста
generate_audio_playlist() {
  while true; do
    # Перемешиваем mp3-файлы и форматируем под стандарт concat
    find . -maxdepth 1 -name "*.mp3" | shuf | sed "s|^\./|file '/radio/|; s|$|'|" > concat_list.txt.tmp
    mv concat_list.txt.tmp concat_list.txt
    sleep 10
  done
}
generate_audio_playlist </dev/null >/dev/null 2>&1 &

# Даем 2 секунды на создание файла списка
sleep 2

echo "Запуск HD-трансляции на YouTube..."
# ЕДИНЫЙ ПРОЦЕСС FFMPEG: Склеивает треки фильтром acrossfade на лету.
# Поток звука больше физически не может оборваться на стыке.
# d=3 задает длительность плавного перехода между песнями (3 секунды).
while true; do
  ffmpeg -v error -nostdin -y \
    -loop 1 -r 2 -i bg.jpg \
    -f concat -safe 0 -stream_loop -1 -i concat_list.txt \
    -vf "scale=1280:720,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='RADIO LIVE':x=(w-tw)/2:y=h-80:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=12" \
    -af "acrossfade=d=3:c1=tri:c2=tri" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 28 -b:v 1000k -maxrate 1000k -bufsize 2000k \
    -pix_fmt yuv420p -g 10 -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://a.rtmp.youtube.com/live2/4ux7-0ay8-816w-cxrb-1j24" < /dev/null

  echo "Переподключение потока через 3 секунды..."
  sleep 3
done
