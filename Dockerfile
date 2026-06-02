FROM ubuntu:22.04

# 1. Устанавливаем ffmpeg, python (для заглушки Render) и шрифты
RUN apt-get update && apt-get install -y \
    ffmpeg \
    python3 \
    fonts-liberation \
    bash \
    && rm -rf /var/lib/apt/lists/*

# 2. Создаем рабочую директорию
WORKDIR /radio

# 3. Копируем музыку, картинку и наш новый скрипт запуска
COPY . .

# 4. Делаем скрипт запуска исполняемым
RUN chmod +x start_radio.sh

# 5. Открываем порт 10000 для веб-обманки Render
EXPOSE 10000

# 6. Запускаем стрим через новый скрипт
CMD ["./start_radio.sh"]
