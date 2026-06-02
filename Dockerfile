FROM ubuntu:22.04

# Устанавливаем необходимые утилиты
RUN apt-get update && apt-get install -y \
    ffmpeg \
    python3 \
    bash \
    && rm -rf /var/lib/apt/lists/*

# Создаем рабочую директорию
WORKDIR /radio

# Копируем все файлы (музыку, картинку и скрипт)
COPY . .

# Принудительно делаем скрипт исполняемым прямо при сборке образа
RUN chmod +x start_radio.sh

# Открываем обязательный порт для Render
EXPOSE 10000

# Главная команда запуска — она заменяет собой Start Command на Render
CMD ["./start_radio.sh"]
