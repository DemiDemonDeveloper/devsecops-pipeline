# devsecops-pipeline

A Go microservice wrapped in an end-to-end DevSecOps pipeline.

| Stage | Tooling | Status |
|---|---|---|
| 1. Secret prevention | gitleaks (pre-commit + CI) | ✅ |
| 2. SAST + SCA / SBOM | Semgrep (+ custom rules), govulncheck, Trivy, Syft | ✅ |
| 3. IaC security | Terraform (AWS VPC/EKS/S3/IAM/KMS), Checkov, Trivy config (tfsec rules) | ✅ scanned, not applied |
| 4. Container security + signing | Multi-stage distroless image, Trivy, Cosign | 🟡 image done |
| 5. Admission control | Kyverno | ⏳ |
| 6. DAST + runtime | OWASP ZAP, Falco | ⏳ |

## Quick start

```bash
make hooks   # install pre-commit hooks (gitleaks)
make test    # go vet + race tests
make run     # http://localhost:8080/healthz
make build   # docker image (distroless, non-root)
make secrets # scan full git history for leaks
make scan-all # every local scan: secrets, SAST, vulns, deps, SBOM, image
```

## API

- `GET /healthz`
- `GET /api/v1/items`
- `POST /api/v1/items` — `{"name": "..."}` (1–100 chars)
- `GET /api/v1/items/{id}`
