#!/bin/bash
set -e

export FFMPEG_FORCE_TEXT_STATUS=1
CD_DIR="/radio"
cd "$CD_DIR"

# Мягкая остановка старых процессов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
pkill -9 -f "playlist_feeder" || true   # если был запущен

# Заглушка для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

# Проверка наличия mp3
if ! ls *.mp3 >/dev/null 2>&1; then
  echo "Нет mp3-файлов в /radio"
  exit 1
fi

# Создаём FIFO (если уже есть — удаляем и пересоздаём)
rm -f playlist.fifo
mkfifo playlist.fifo

# Запускаем генератор плейлистов в фоне
./playlist_feeder.sh > playlist.fifo &
FEEDER_PID=$!
trap "kill $FEEDER_PID 2>/dev/null; rm -f playlist.fifo" EXIT

echo "Запуск непрерывного радио со сменой плейлиста каждые ~4 часа..."

ffmpeg -v error -nostdin -y \
  -loop 1 -r 5 -i bg.jpg \
  -re -f concat -safe 0 -i playlist.fifo \
  -filter_complex \
    "[1:a]acrossfade=d=3:c1=tri:c2=tri,asplit[audio_out][audio_vis]; \
     [audio_vis]showwaves=s=1280x80:mode=cline:colors=white@0.6:r=5[waves]; \
     [0:v]scale=1280:720[bg]; \
     [bg][waves]overlay=x=0:y=H-h[v_waves]; \
     [v_waves]drawtext=text='RADIO LIVE':x=30:y=h-130:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10:fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf[video_out]" \
  -map "[video_out]" -map "[audio_out]" \
  -c:v libx264 -preset ultrafast -tune stillimage -crf 30 -b:v 800k -maxrate 800k -bufsize 1600k \
  -pix_fmt yuv420p -g 10 -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmp://a.rtmp.youtube.com/live2/${4ux7-0ay8-816w-cxrb-1j24}
