#!/bin/bash
# playlist_feeder.sh – непрерывный источник звука и названий треков
# Запускать: ./playlist_feeder.sh > audio.fifo

CD_DIR="/radio"
cd "$CD_DIR"

TITLE_FILE="current_title.txt"
DURATION_TARGET=$((4 * 3600))  # 4 часа в секундах

# Функция получения названия (как у вас)
get_title() {
  local file="$1"
  artist=$(ffprobe -v error -show_entries format_tags=artist -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
  title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
  if [ -n "$artist" ] && [ -n "$title" ]; then
    echo "${artist} - ${title}"
  elif [ -n "$title" ]; then
    echo "$title"
  elif [ -n "$artist" ]; then
    echo "$artist"
  else
    basename "$file" .mp3 | tr '_' ' '
  fi | sed "s/'//g"
}

# Собираем все mp3 с длительностями
declare -A DURATIONS
FILES=()
while IFS= read -r -d '' f; do
  dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo 0)
  # Пропускаем файлы с нулевой длительностью
  if (( $(echo "$dur <= 0" | bc -l) )); then
    continue
  fi
  DURATIONS["$f"]=$dur
  FILES+=("$f")
done < <(find . -maxdepth 1 -name "*.mp3" -print0)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "Нет mp3-файлов" >&2
  exit 1
fi

# Бесконечный цикл: генерируем блоки
while true; do
  # Перемешиваем файлы
  mapfile -t SHUFFLED < <(printf '%s\n' "${FILES[@]}" | shuf)

  total=0
  block=()
  for f in "${SHUFFLED[@]}"; do
    dur="${DURATIONS[$f]}"
    total=$(echo "$total + $dur" | bc -l)
    block+=("$f")
    if (( $(echo "$total >= $DURATION_TARGET" | bc -l) )); then
      break
    fi
  done

  echo "Новый блок: ${#block[@]} треков, длительность $(printf "%.0f" "$total") сек." >&2

  # Проигрываем блок (пишем PCM в stdout)
  for f in "${block[@]}"; do
    # Записываем название трека в файл (текст сразу появится на экране)
    get_title "$f" > "$TITLE_FILE"

    # Декодируем mp3 в сырой PCM (s16le, 44100, stereo) и выводим в stdout
    ffmpeg -v error -i "$f" -f s16le -acodec pcm_s16le -ar 44100 -ac 2 - 2>/dev/null

    # Когда трек закончился, цикл переходит к следующему – без пауз
  done
  # Блок завершён, сразу начинаем генерировать следующий (без разрыва в FIFO)
done
