#!/bin/bash
set -e

CD_DIR="/radio"
cd "$CD_DIR"

STREAM_KEY="${YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}"
FONT_PATH="/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"

# 1. Веб-обманка для Render
pkill -f "http.server" || true
python3 -m http.server 10000 &

# 2. Функция генерации бесконечного плейлиста для ffmpeg
generate_playlist() {
  while true; do
    # Перемешиваем файлы и форматируем их строго под синтаксис ffmpeg concat
    find . -maxdepth 1 -name "*.mp3" | shuf | sed "s|^\./|file '/radio/|; s|$|'|" > playlist.txt.tmp
    mv playlist.txt.tmp playlist.txt
    sleep 5
  done
}

# Запускаем генератор плейлиста строго в фоне с изоляцией ввода
generate_playlist </dev/null >/dev/null 2>&1 &

# Даем 2 секунды на создание файла playlist.txt
sleep 2

# 3. ЕДИНЫЙ ПРОЦЕСС FFMPEG (Без фоновых пайпов аудио)
# -f concat -safe 0 -stream_loop -1 читает плейлист по кругу без швов и падений
# -r 10 и scale=854:480 снижают нагрузку на слабый CPU Render, поднимая speed до 1.0x+
ffmpeg -v error -nostdin \
  -loop 1 -r 10 -i bg.jpg \
  -f concat -safe 0 -stream_loop -1 -i playlist.txt \
  -vf "scale=854:480,drawtext=fontfile=${FONT_PATH}:text='В эфире радио':x=(w-tw)/2:y=h-50:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=10" \
  -c:v libx264 -preset ultrafast -tune stillimage -crf 32 -b:v 400k -maxrate 400k -bufsize 800k \
  -pix_fmt yuv420p -g 30 -c:a aac -b:a 128k -ar 44100 \
  -f flv "rtmp://://youtube.com" </dev/null
