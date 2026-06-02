FROM ubuntu:22.04
RUN apt-get update && apt-get install -y ffmpeg findutils fonts-liberation python3
WORKDIR /radio
COPY . .
RUN chmod +x start.sh
EXPOSE 10000
CMD ["./start.sh"]
