FROM golang:1.8-alpine

RUN apk --update add git less openssh && \
    rm -rf /var/lib/apt/lists/* && \
    rm /var/cache/apk/*

WORKDIR /

RUN go get -v -u github.com/influxdata/influx-stress/cmd/...

CMD ["influx-stress"]
