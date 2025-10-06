# syntax=docker/dockerfile:1

## Build
FROM golang:1.23.1-bullseye AS build
ARG VERSION=dev
WORKDIR /go/src/app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w -X main.version=$VERSION" -o /go/bin/inpxer

## Deploy
FROM alpine:3.20

# Install CA certificates (for HTTPS), timezone data, unzip (to read .inpx version), and su-exec for privilege drop
RUN apk add --no-cache ca-certificates tzdata unzip su-exec \
	&& addgroup -S app && adduser -S -G app app

COPY --from=build /go/bin/inpxer /bin/inpxer
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
	&& mkdir -p /data/index

EXPOSE 8080/tcp
VOLUME ["/data"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["serve"]
