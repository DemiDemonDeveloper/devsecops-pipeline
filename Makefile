IMAGE ?= devsecops-api:dev

.PHONY: test run build secrets hooks

test:
	go vet ./...
	go test -race ./...

run:
	go run ./cmd/api

build:
	docker build -t $(IMAGE) .

# Scan the full git history for leaked secrets
secrets:
	gitleaks git --redact --verbose --config .gitleaks.toml

# Install git pre-commit hooks (run once per clone)
hooks:
	pre-commit install
