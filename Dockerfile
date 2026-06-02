FROM ubuntu:22.04
RUN apt-get update && apt-get install -y ffmpeg findutils fonts-liberation python3
WORKDIR /radio
COPY . .
RUN chmod +x play.sh
EXPOSE 10000
# Прописываем правильный адрес YouTube прямо в запуск контейнера
CMD ["/bin/bash", "-c", "sed -i 's/207.244.75.12/://youtube.com' play.sh && ./play.sh"]
