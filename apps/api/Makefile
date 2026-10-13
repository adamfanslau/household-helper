# hh-api. Run from apps/api: `make test`, `make dev`, `make build`. Nothing here touches the VPS.
# Local settings come from .env (copy .env.example); the dev stack is scripts/dev/stack.sh.

GO      ?= go
BIN     := bin/hh-api
VERSION ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)
LDFLAGS := -s -w -X main.version=$(VERSION)
DEV     := ../../scripts/dev/stack.sh

.PHONY: run test test-v build build-linux lint tidy clean dev dev-reset dev-down golden

## run: start the API in the foreground with the variables from .env (no emulator)
run:
	@test -f .env || { echo "copy .env.example to .env first"; exit 1; }
	set -a; . ./.env; set +a; $(GO) run -ldflags "-X main.version=$(VERSION)" ./cmd/hh-api

## dev: Auth emulator + API on 127.0.0.1:8091 in the background (logs in .dev/logs)
dev:
	$(DEV) up

## dev-reset: stop, delete hh-dev.db*, start again (fresh seed)
dev-reset:
	$(DEV) reset

dev-down:
	$(DEV) down

## test: go vet + go test -race
test:
	$(GO) vet ./...
	$(GO) test -race ./...

test-v:
	$(GO) test -race -v ./...

## golden: rewrite the JSON contract fixtures (api step C)
golden:
	$(GO) test ./internal/httpapi -run TestGolden -update

## build: static binary for this machine
build:
	mkdir -p bin
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags "$(LDFLAGS)" -o $(BIN) ./cmd/hh-api

## build-linux: what the deploy workflow ships to the VPS
build-linux:
	mkdir -p bin
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build -trimpath -ldflags "$(LDFLAGS)" -o bin/hh-api-linux-amd64 ./cmd/hh-api

## lint: vet + gofmt check
lint:
	$(GO) vet ./...
	@out=$$(gofmt -l ./cmd ./internal); if [ -n "$$out" ]; then echo "gofmt needed:"; echo "$$out"; exit 1; fi

tidy:
	$(GO) mod tidy

clean:
	rm -rf bin
