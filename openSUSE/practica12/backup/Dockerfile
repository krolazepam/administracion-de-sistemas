FROM alpine:3.19
RUN apk add --no-cache tar gzip
COPY backup.sh /usr/local/bin/backup.sh
COPY crontab /etc/crontabs/root
RUN chmod +x /usr/local/bin/backup.sh && chmod 600 /etc/crontabs/root
CMD ["crond", "-f", "-d", "8"]
