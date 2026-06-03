#!/bin/bash
set -euo pipefail

CD_DIR="/radio"
cd "$CD_DIR"

# Проверка ключа YouTube
if [ -z "${YT_KEY:-}" ]; then
  echo "❌ Переменная окружения YT_KEY не задана!"
  exit 1
fi

# Остановка старых процессов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "SimpleHTTPServerPing" || true # Убиваем старый пинг-сервер

# Проверка mp3
if ! ls *.mp3 >/dev/null 2>&1; then
  echo "Нет mp3-файлов в /radio"
  exit 1
fi

# --- НАЧАЛО: Запуск минимального HTTP-сервера для пинга ---
PORT=${PORT:-10000}

# Создаем простой скрипт для HTTP-сервера
cat << 'EOF' > /tmp/simple_ping_server.py
import http.server
import socketserver
from http import HTTPStatus

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(HTTPStatus.OK)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'OK\n')

    # Обработка других методов (POST, HEAD и т.д.) также возвращает 200 OK
    def do_HEAD(self):
        self.send_response(HTTPStatus.OK)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()

    def do_POST(self):
        self.do_GET() # Для пинга POST можно обрабатывать как GET

    def log_message(self, format, *args):
        # Отключаем логирование запросов для чистоты stdout
        pass

with socketserver.TCPServer(("", int(__import__('os').environ.get('PORT', 10000))), Handler) as httpd:
    print(f"Ping server running on port {__import__('os').environ.get('PORT', 10000)}")
    httpd.serve_forever()
EOF

# Запускаем сервер в фоне
python3 /tmp/simple_ping_server.py &
HTTP_PID=$!
echo "mPid HTTP-сервера (для пинга): $HTTP_PID"
# --- КОНЕЦ: Запуск минимального HTTP-сервера для пинга ---

trap "kill $HTTP_PID 2>/dev/null || true; rm -f audio.fifo current_title.txt; rm -f /tmp/simple_ping_server.py" EXIT

# FIFO и файл текста
rm -f audio.fifo
mkfifo audio.fifo
echo "" > current_title.txt

echo "=== Запуск НЕПРЕРЫВНОГО радио ==="

# Запуск фидера
./playlist_feeder.sh > audio.fifo 2>"/tmp/feeder_$$.log" &
FEEDER_PID=$!

sleep 2
if ! kill -0 $FEEDER_PID 2>/dev/null; then
  echo "❌ Фидер не запустился, смотрите /tmp/feeder_$$.log"
  exit 1
fi

# FFmpeg: Баланс качества картинки и трафика
ffmpeg -v warning -nostdin -y \
  -re -f image2 -loop 1 -framerate 1 -i bg.jpg \
  -f s16le -ar 44100 -ac 2 -i audio.fifo \
  -filter_complex \
    "[0:v]scale=1280:720,drawtext=textfile=current_title.txt:reload=1:expansion=none:x=30:y=h-80:fontsize=32:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10:font='DejaVu Sans',format=yuv420p[video_out]" \
  -map "[video_out]" -map 1:a \
  -c:v libx264 -preset ultrafast -tune stillimage -b:v 280k -maxrate 320k -bufsize 640k \ # <-- Новые параметры битрейта
  -pix_fmt yuv420p -g 2 \
  -c:a aac -b:a 64k -ar 44100 \
  -f flv "rtmp://a.rtmp.youtube.com/live2/${YT_KEY}" 2>"/tmp/ffmpeg_main_$$.log"

echo "❌ FFmpeg остановлен (код $?), логи в /tmp/ffmpeg_main_$$.log" >&2
kill $FEEDER_PID 2>/dev/null || true

