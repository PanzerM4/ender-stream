#!/bin/bash
set -euo pipefail

CD_DIR="/radio"
cd "$CD_DIR"

PORT=${PORT:-10000}

# ------------------------------------------------------------
# Функция принудительного освобождения порта
# ------------------------------------------------------------
free_port() {
  echo "🔧 Освобождаю порт $PORT..."
  if command -v fuser &>/dev/null; then
    fuser -k ${PORT}/tcp 2>/dev/null || true
  elif command -v lsof &>/dev/null; then
    lsof -ti:${PORT} | xargs -r kill -9
  fi
  pkill -9 -f "ffmpeg" || true
  pkill -9 -f "python3" || true
  pkill -9 -f "http.server" || true
  pkill -9 -f "playlist_feeder" || true
  sleep 2
  # Ждём, пока порт реально освободится
  while command -v lsof &>/dev/null && lsof -i:${PORT} 2>/dev/null | grep -q LISTEN; do
    echo "⏳ Порт ещё занят, жду..."
    sleep 2
  done
}

# ------------------------------------------------------------
# 1. Освобождаем порт
# ------------------------------------------------------------
free_port

# ------------------------------------------------------------
# 2. Проверки
# ------------------------------------------------------------
if ! ls *.mp3 >/dev/null 2>&1; then
  echo "❌ Нет mp3-файлов в /radio"
  exit 1
fi

if [ ! -f bg.jpg ]; then
  echo "🎨 Создаю чёрный фон..."
  ffmpeg -y -f lavfi -i color=c=black:s=1280x720:r=1 -frames:v 1 bg.jpg
fi

if [ ! -f playlist_feeder.sh ]; then
  echo "❌ Нет playlist_feeder.sh"
  exit 1
fi
chmod +x playlist_feeder.sh

# ------------------------------------------------------------
# 3. HTTP‑сервер для health check (всегда отвечает 200)
# ------------------------------------------------------------
echo "🌐 Запускаю health-check сервер на порту $PORT..."
python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
import os
port = int(os.environ.get('PORT', 10000))
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'OK')
HTTPServer(('', port), H).serve_forever()
" &
HTTP_PID=$!
trap "kill $HTTP_PID 2>/dev/null; rm -f audio.fifo current_title.txt; kill 0" EXIT

echo "✅ Health-check server PID: $HTTP_PID"

# ------------------------------------------------------------
# 4. FIFO и текстовый файл для названий
# ------------------------------------------------------------
rm -f audio.fifo
mkfifo audio.fifo
echo "" > current_title.txt

# ------------------------------------------------------------
# 5. Функция запуска фидера
# ------------------------------------------------------------
start_feeder() {
  ./playlist_feeder.sh > audio.fifo 2>&1 &
  echo $!
}

# ------------------------------------------------------------
# 6. Основной цикл с авто-восстановлением
# ------------------------------------------------------------
echo "=== 🎵 Запуск НЕПРЕРЫВНОГО радио ==="
while true; do
  # Запускаем фидер
  echo "▶️ Запускаю фидер плейлиста..."
  FEEDER_PID=$(start_feeder)
  sleep 2
  if ! kill -0 $FEEDER_PID 2>/dev/null; then
    echo "❌ Фидер упал сразу! Лог:"
    cat /tmp/feeder_*.log 2>/dev/null || echo "Логов нет"
    sleep 5
    continue
  fi
  echo "✅ Фидер работает (PID $FEEDER_PID)"

  # Запускаем ffmpeg (БИТРЕЙТ AAC УВЕЛИЧЕН ДО 256k)
  echo "🎬 Запускаю ffmpeg..."
  ffmpeg -v warning -nostdin -y \
    -re -f image2 -loop 1 -framerate 1 -i bg.jpg \
    -f s16le -ar 44100 -ac 2 -i audio.fifo \
    -filter_complex \
      "[0:v]scale=1280:720,drawtext=textfile=current_title.txt:reload=1:x=30:y=h-80:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10:font='DejaVu Sans',format=yuv420p[video_out]" \
    -map "[video_out]" -map 1:a \
    -c:v libx264 -preset ultrafast -tune stillimage -b:v 1500k -maxrate 1500k -bufsize 3000k \
    -pix_fmt yuv420p -g 2 \
    -c:a aac -b:a 256k -ar 44100 \
    -f flv "rtmp://a.rtmp.youtube.com/live2/${YT_KEY}" 2>&1 | ts '[%Y-%m-%d %H:%M:%S]' &
  FFMPEG_PID=$!
  echo "✅ FFmpeg PID: $FFMPEG_PID"

  # Ждём, когда что-то упадёт
  wait -n $FFMPEG_PID $FEEDER_PID || true

  # Убиваем всё и перезапускаем
  kill $FFMPEG_PID 2>/dev/null || true
  kill $FEEDER_PID 2>/dev/null || true
  wait $FFMPEG_PID 2>/dev/null || true
  wait $FEEDER_PID 2>/dev/null || true
  echo "⚠️ Процесс завершился, перезапуск через 5 секунд..."
  sleep 5
done
