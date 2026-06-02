#!/bin/bash
set -e

export FFMPEG_FORCE_TEXT_STATUS=1
CD_DIR="/radio"
cd "$CD_DIR"

# Полная очистка старых процессов
pkill -9 -f "ffmpeg"  true
pkill -9 -f "ffprobe"  true
pkill -9 -f "http.server" || true
rm -f concat_list.txt metadata.txt

# Фоновая заглушка для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

# ФУНКЦИЯ: Генерация бесшовного аудио плейлиста
generate_audio_playlist() {
  while true; do
    find . -maxdepth 1 -name "*.mp3" | shuf | sed "s|^\./|file '/radio/|; s|$|'|" > concat_list.txt.tmp
    mv concat_list.txt.tmp concat_list.txt
    sleep 10
  done
}
generate_audio_playlist </dev/null >/dev/null 2>&1 &

sleep 2

echo "Запуск трансляции с эквалайзером на YouTube..."
while true; do
  # ИЗМЕНЕНИЯ:
  # 1. Добавлен флаг -re перед -f concat для синхронизации стрима с реальным временем (1.0x).
  # 2. Исправлен адрес отправки в конце строки на правильный RTMP-сервер YouTube.
  ffmpeg -v error -nostdin -y \
    -loop 1 -r 5 -i bg.jpg \
    -vn -re -f concat -safe 0 -stream_loop -1 -i concat_list.txt \
    -filter_complex "[1:a]acrossfade=d=3:c1=tri:c2=tri,asplit[audio_out][audio_vis]; \
                     [audio_vis]showwaves=s=1280x80:mode=cline:colors=white@0.6:r=5[waves]; \
                     [0:v]scale=1280:720[bg]; \
                     [bg][waves]overlay=x=0:y=H-h[v_waves]; \
                     [v_waves]drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='RADIO LIVE':x=30:y=h-130:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10[video_out]" \
    -map "[video_out]" -map "[audio_out]" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 30 -b:v 800k -maxrate 800k -bufsize 1600k \
    -pix_fmt yuv420p -g 10 -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://://youtube.com{YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null

  echo "Переподключение потока через 3 секунды..."
  sleep 3
done



