IMAGE ?= devsecops-api:dev
SEMGREP_CONFIGS = --config p/golang --config p/owasp-top-ten --config p/secrets --config .semgrep/rules.yml
# Syft/Trivy need the daemon socket; Colima doesn't use /var/run/docker.sock
export DOCKER_HOST ?= $(shell docker context inspect -f '{{.Endpoints.docker.Host}}' 2>/dev/null)

.PHONY: kyverno policies deploy admission-test test run build secrets hooks sast sast-test vulns deps sbom scan-image scan-all iac plan

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
# Same digest-pinned images as CI: the Homebrew checkov build was found to
# evaluate fewer checks than the container, so local results could drift.
CHECKOV_IMAGE = bridgecrew/checkov@sha256:6d20ebbcde58b2dce6e3151a6771fefa4d468281fe442475455623f5799b9f53
TRIVY_IMAGE   = aquasec/trivy@sha256:2416d1f74045b57274df1a340eee6b510cacd73c66a6ccb8da092b117eb7d222

iac:
	cd terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false >/dev/null && terraform validate
	docker run --rm -v "$(CURDIR)/terraform:/tf" $(CHECKOV_IMAGE) -d /tf --framework terraform --skip-path tests --compact --quiet
	docker run --rm -v "$(CURDIR)/terraform:/tf" $(TRIVY_IMAGE) config --quiet --severity HIGH,CRITICAL --skip-dirs /tf/tests --exit-code 1 /tf

# Plan only; applying is a deliberate manual step (costs money).
plan:
	cd terraform && terraform init -input=false && terraform plan -out=tfplan

scan-all: secrets sast test vulns deps iac sbom scan-image

# --- Step 5: admission control (needs kubectl context for the cluster) ---
kyverno:
	helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
	helm upgrade --install kyverno kyverno/kyverno --version 3.9.1 -n kyverno --create-namespace -f k8s/kyverno/values.yaml --wait

policies:
	kubectl apply -f k8s/kyverno/policies/

deploy:
	kubectl apply -f k8s/app/app.yaml
	kubectl -n staging rollout status deploy/api --timeout=120s

# Every manifest in k8s/tests must be DENIED by admission (server-side dry run)
admission-test:
	@python3 -c "import subprocess,sys; docs=open('k8s/tests/must-be-rejected.yaml').read().split('\n---\n'); bad=[d for d in docs if subprocess.run(['kubectl','apply','--dry-run=server','-f','-'],input=d,capture_output=True,text=True).returncode==0]; print(f'{len(docs)-len(bad)}/{len(docs)} non-compliant manifests denied'); sys.exit(1 if bad else 0)"
