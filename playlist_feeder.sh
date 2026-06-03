  # --- Запускаем фоновый планировщик обновления текста (новая логика) ---
  (
    for ((i=0; i<n; i++)); do
      title="${block_titles[$i]}"
      start="${block_starts[$i]}"
      end="${block_ends[$i]}"

      # Новое: исчезает за 5 сек до конца трека
      hide_time=$(echo "$BLOCK_START + $end - 5" | bc -l)
      # Новое: появляется через 5 сек после начала трека
      show_time=$(echo "$BLOCK_START + $start + 5" | bc -l)

      # Сначала ждём до show_time (появление названия)
      now=$(date +%s.%N)
      wait_show=$(echo "$show_time - $now" | bc -l)
      if (( $(echo "$wait_show > 0" | bc -l) )); then
        sleep "$wait_show"
      fi
      # Показываем название (если ещё не показано)
      echo "$title" > "$TITLE_FILE"

      # Ждём до hide_time (скрытие названия)
      now=$(date +%s.%N)
      wait_hide=$(echo "$hide_time - $now" | bc -l)
      if (( $(echo "$wait_hide > 0" | bc -l) )); then
        sleep "$wait_hide"
      fi
      # Очищаем текст
      echo "" > "$TITLE_FILE"
    done
  ) &
  TEXT_PID=$!
