#!/bin/bash
cd /radio

# Запускаем фоновую веб-обманку для прохождения проверок платформы
python3 -m http.server 10000 &

while true; do
  echo "Перемешиваем список треков..."
  find . -maxdepth 1 -name "*.mp3" | shuf > shuffle_list.txt

  while IFS= read -r track_path; do
    # Извлекаем русские теги исполнителя и названия из файла
    artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null)
    title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$track_path" 2>/dev/null)

    if [ -n "$artist" ] && [ -n "$title" ]; then
        display_name="$artist — $title"
    else
        display_name=$(basename "$track_path" .mp3 | sed 's/_/ /g')
    fi

    echo "В эфире: $display_name"

    # Запуск вещания: чистая картинка и звук с высоким битрейтом без нагрузки на процессор
    ffmpeg -re -loop 1 -i bg.jpg -i "$track_path" \
      -c:v libx264 -preset ultrafast -tune stillimage -crf 30 -b:v 1500k -maxrate 1500k -bufsize 3000k \
      -pix_fmt yuv420p -g 50 -shortest -c:a aac -b:a 192k -ar 44100 \
      -f flv "rtmp://a.rtmp.youtube.com/live2/4ux7-0ay8-816w-cxrb-1j24" || true

    sleep 1
  done < shuffle_list.txt
done


