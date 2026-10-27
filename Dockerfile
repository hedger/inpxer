# syntax=docker/dockerfile:1

# Version of the FB2 converter bundled in the runtime image.
# See https://github.com/rupor-github/fb2cng/releases.
ARG FB2CNG_VERSION=v1.9.4

## Build
FROM golang:1.23.1-bullseye AS build
ARG VERSION=dev
WORKDIR /go/src/app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w -X main.version=$VERSION" -o /go/bin/inpxer

## FB2 converter
# fb2cng publishes static Linux binaries, so download the pinned release for the
# target architecture instead of building it (the source tree needs generated
# fonts/dictionaries that are only present in release artifacts).
FROM --platform=$BUILDPLATFORM alpine:3.20 AS fbc-fetch
ARG FB2CNG_VERSION
ARG TARGETARCH
RUN apk add --no-cache ca-certificates unzip
RUN set -eux; \
	case "${TARGETARCH}" in \
		amd64) asset="fbc-linux-amd64.zip"; checksum="5e2c5e3645b8ffbe6c8b0ee447faf47bce84e850a03fcf2054f00d653d9a4506" ;; \
		arm64) asset="fbc-linux-arm64.zip"; checksum="ed7a3e1c3e040bf11806677c806d4c45c315eb224b649e90610bdca6b0d61525" ;; \
		*) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
	esac; \
	wget -q -O /tmp/fbc.zip "https://github.com/rupor-github/fb2cng/releases/download/${FB2CNG_VERSION}/${asset}"; \
	echo "${checksum}  /tmp/fbc.zip" > /tmp/fbc.sha256; \
	sha256sum -c /tmp/fbc.sha256; \
	mkdir -p /out; \
	unzip -q /tmp/fbc.zip -d /out; \
	chmod +x /out/fbc; \
	rm /tmp/fbc.zip
RUN wget -q -O /out/LICENSE "https://raw.githubusercontent.com/rupor-github/fb2cng/${FB2CNG_VERSION}/LICENSE" \
	&& printf 'fb2cng %s\nhttps://github.com/rupor-github/fb2cng/tree/%s\n' "${FB2CNG_VERSION}" "${FB2CNG_VERSION}" > /out/SOURCE

## Deploy
FROM alpine:3.20

# Install CA certificates (for HTTPS), timezone data, unzip (to read .inpx version), and su-exec for privilege drop
RUN apk add --no-cache ca-certificates tzdata unzip su-exec \
	&& addgroup -S app && adduser -S -G app app

COPY --from=build /go/bin/inpxer /bin/inpxer
COPY --from=fbc-fetch /out/fbc /usr/local/bin/fbc
COPY --from=fbc-fetch /out/LICENSE /usr/share/licenses/fb2cng/LICENSE
COPY --from=fbc-fetch /out/SOURCE /usr/share/licenses/fb2cng/SOURCE
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
	&& mkdir -p /data/index /home/app \
	&& chown -R app:app /home/app

# fbc writes its default log file to the current directory.
ENV HOME=/home/app
WORKDIR /home/app

EXPOSE 8080/tcp
VOLUME ["/data"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["serve"]
