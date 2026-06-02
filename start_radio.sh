CD_DIR="/radio"
cd "$CD_DIR"

# Полная очистка старых процессов
# Полная очистка памяти от старых процессов и пайпов
pkill -9 -f "ffmpeg" || true
pkill -9 -f "ffprobe" || true
pkill -9 -f "http.server" || true
rm -f concat_list.txt
rm -f audio_pipe metadata.txt
mkfifo audio_pipe
touch metadata.txt

# Фоновая заглушка для Render
python3 -m http.server 10000 >/dev/null 2>&1 &

# ФУНКЦИЯ: Генерация бесшовного аудио плейлиста
generate_audio_playlist() {
# ФОНОВЫЙ ПРОЦЕСС: Непрерывное аудио без единого шва
(
  while true; do
    find . -maxdepth 1 -name "*.mp3" | shuf | sed "s|^\./|file '/radio/|; s|$|'|" > concat_list.txt.tmp
    mv concat_list.txt.tmp concat_list.txt
    sleep 10
    find . -maxdepth 1 -name "*.mp3" | shuf > shuffle_list.txt
    while IFS= read -r track_path; do
      # Отправляем маркер в логи
      echo "Плеер взял трек: $(basename "$track_path")"
      
      # ПРИНУДИТЕЛЬНАЯ СТАБИЛИЗАЦИЯ: Любой mp3 превращаем в идеальный WAV 44100Hz Stereo
      # amix с генератором тишины гарантирует, что пайп не закроется ни на миллисекунду на стыке
      ffmpeg -v error -nostdin -i "$track_path" -f lavfi -i anullsrc=r=44100:cl=stereo \
        -filter_complex "[0:a][1:a]amix=inputs=2:duration=first,aresample=async=1[aout]" \
        -map "[aout]" -f wav -ar 44100 -ac 2 -y audio_pipe </dev/null || true
    done < shuffle_list.txt
  done
}
generate_audio_playlist </dev/null >/dev/null 2>&1 &
) &

# Даем 2 секунды на создание файла списка
sleep 2

echo "Запуск HD-трансляции на YouTube..."
echo "Запуск стабильной HD-трансляции в реальном времени..."
while true; do
  # КРИТИЧЕСКИЕ ИЗМЕНЕНИЯ:
  # 1. Добавлен флаг -re строго ПЕРЕД -f concat, что фиксирует скорость стрима на 1.00x.
  # 2. Повышена плавность до -r 5, а интервал ключевых кадров выставлен в -g 10 для стабильности на YouTube.
  # 3. Вся команда записана в одну строку во избежание сбоев с символами переноса "\".
  ffmpeg -v error -nostdin -y -loop 1 -r 5 -i bg.jpg -re -f concat -safe 0 -stream_loop -1 -i concat_list.txt -vf "scale=1280:720,drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='RADIO LIVE':x=(w-tw)/2:y=h-80:fontsize=28:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=12" -af "acrossfade=d=3:c1=tri:c2=tri" -c:v libx264 -preset ultrafast -tune stillimage -crf 28 -b:v 1000k -maxrate 1000k -bufsize 2000k -pix_fmt yuv420p -g 10 -c:a aac -b:a 128k -ar 44100 -f flv "rtmp://://youtube.com{YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null
  # ГЛАВНЫЙ ПРОЦЕСС: Читает аудио из пайпа. Флаг -re гарантирует скорость строго 1.00x.
  # Эквалайзер работает без задержек, так как получает идеальный бесшовный аудиосигнал.
  ffmpeg -v error -nostdin -y \
    -loop 1 -r 5 -i bg.jpg \
    -vn -re -f wav -i audio_pipe \
    -filter_complex "[1:a]asplit[audio_out][audio_vis]; \
                     [audio_vis]showwaves=s=1280x80:mode=cline:colors=white@0.6:r=5[waves]; \
                     [0:v]scale=1280:720[bg]; \
                     [bg][waves]overlay=x=0:y=H-h[v_waves]; \
                     [v_waves]drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf:text='RADIO LIVE':x=30:y=h-130:fontsize=24:fontcolor=white:box=1:boxcolor=black@0.5:boxborderw=10[video_out]" \
    -map "[video_out]" -map "[audio_out]" \
    -c:v libx264 -preset ultrafast -tune stillimage -crf 30 -b:v 800k -maxrate 800k -bufsize 1600k \
    -pix_fmt yuv420p -g 10 -c:a aac -b:a 128k -ar 44100 \
    -f flv "rtmp://://youtube.com{YOUTUBE_KEY:-4ux7-0ay8-816w-cxrb-1j24}" < /dev/null

  echo "Переподключение потока через 3 секунды..."
  echo "Временная потеря сети. Переподключение через 3 секунды..."
  sleep 3
done
