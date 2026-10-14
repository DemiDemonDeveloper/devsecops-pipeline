# syntax=docker/dockerfile:1
# --- build stage: full Go toolchain, never shipped ---
FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
# Static, stripped, reproducible binary (no cgo -> runs on distroless/static)
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w -buildid=" -o /out/api ./cmd/api

# --- runtime stage: no shell, no package manager, non-root ---
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/api /api
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/api"]
