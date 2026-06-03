#!/bin/bash
# Генератор непрерывного плейлиста: каждые ~4 часа подаёт новый случайный блок треков
# Запускается: ./playlist_feeder.sh > playlist.fifo

DURATION_TARGET=14400   # 4 часа в секундах

# Составляем массив всех mp3 с полными путями и длительностями
declare -a TRACKS
while IFS= read -r -d '' file; do
  dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo 0)
  # Записываем в массив: длительность:путь
  TRACKS+=("$dur:$file")
done < <(find . -maxdepth 1 -name "*.mp3" -print0)

if [ ${#TRACKS[@]} -eq 0 ]; then
  echo "Нет mp3-файлов" >&2
  exit 1
fi

while true; do
  # Перемешиваем массив (случайный порядок)
  mapfile -t SHUFFLED < <(printf '%s\n' "${TRACKS[@]}" | shuf)

  total=0
  block=()
  for entry in "${SHUFFLED[@]}"; do
    dur="${entry%%:*}"
    file="${entry#*:}"
    # Добавляем трек в блок
    block+=("$file")
    total=$(echo "$total + $dur" | bc -l)
    # Если набрали >= DURATION_TARGET, завершаем блок
    if (( $(echo "$total >= $DURATION_TARGET" | bc -l) )); then
      break
    fi
  done

  # Выводим блок в формате concat (в stdout -> в fifo)
  for f in "${block[@]}"; do
    echo "file '/radio/${f#./}'"
  done

  # Небольшая пауза перед генерацией следующего блока не нужна:
  # FIFO заблокирует запись, пока ffmpeg не прочитает предыдущий блок.
  # Мы просто сразу начинаем новый цикл — следующий блок будет ждать в буфере FIFO.
don
