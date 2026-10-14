IMAGE ?= devsecops-api:dev
SEMGREP_CONFIGS = --config p/golang --config p/owasp-top-ten --config p/secrets --config .semgrep/rules.yml
# Syft/Trivy need the daemon socket; Colima doesn't use /var/run/docker.sock
export DOCKER_HOST ?= $(shell docker context inspect -f '{{.Endpoints.docker.Host}}' 2>/dev/null)

.PHONY: test run build secrets hooks sast sast-test vulns deps sbom scan-image scan-all iac plan

test:
	go vet ./...
	go test -race ./...

run:
	go run ./cmd/api

build:
	docker build -t $(IMAGE) .

# --- Step 1: secrets ---
secrets:
	gitleaks git --redact --verbose --config .gitleaks.toml

hooks:
	pre-commit install

# --- Step 2: SAST + SCA + SBOM ---
sast-test:
	semgrep --metrics=off --test --config .semgrep/rules.yml .semgrep/rules.go

sast: sast-test
	semgrep scan --metrics=off --error $(SEMGREP_CONFIGS) .

vulns:
	go run golang.org/x/vuln/cmd/govulncheck@v1.9.0 ./...

deps:
	trivy fs --quiet --scanners vuln,secret,misconfig --severity HIGH,CRITICAL --skip-dirs terraform/tests --exit-code 1 .

sbom: build
	syft docker:$(IMAGE) -q -o cyclonedx-json=sbom.cdx.json -o spdx-json=sbom.spdx.json
	trivy sbom --quiet --severity HIGH,CRITICAL --exit-code 1 sbom.cdx.json

scan-image: build
	trivy image --quiet --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE)

# --- Step 3: IaC ---
iac:
	cd terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate
	checkov -d terraform --framework terraform --skip-path tests --compact --quiet
	trivy config --quiet --severity HIGH,CRITICAL --skip-dirs terraform/tests --exit-code 1 terraform

# Plan only; applying is a deliberate manual step (costs money).
plan:
	cd terraform && terraform init -input=false && terraform plan -out=tfplan

scan-all: secrets sast test vulns deps iac sbom scan-image
