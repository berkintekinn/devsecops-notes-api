# devsecops-notes-api

Küçük bir FastAPI not servisi. Asıl konu API değil, etrafındaki CI/CD hattı: kod main'e girmeden ve imaj deploy edilmeden önce geçmesi gereken güvenlik kapıları.

## Pipeline

```
push / PR
  ├─ test        pytest
  ├─ gitleaks    tüm git geçmişinde secret taraması
  ├─ semgrep     SAST (p/python, p/owasp-top-ten, p/dockerfile + kendi kurallarım)
  └─ trivy-fs    bağımlılık CVE'leri + Dockerfile misconfig
        │
        ▼  (dördü de geçerse)
     image       build → trivy image scan → ghcr'a push (sadece main)
        │
        ▼
     deploy      scan edilen digest'i Artifact Registry'ye kopyala → Cloud Run → /health smoke test
```

Kapılar HIGH/CRITICAL ve düzeltmesi olan açıklarda pipeline'ı kırıyor. Tüm bulgular SARIF olarak repo'nun Security > Code scanning sekmesine düşüyor.

## Bazı kararlar

- **Action'lar commit SHA ile sabitlendi.** Tag'ler taşınabiliyor (tj-actions/changed-files olayı), SHA taşınamaz. Güncellemeleri Dependabot açıyor.
- **Dependabot'ta 7 günlük cooldown var.** Yeni yayınlanan bir paket ele geçirilmişse genelde birkaç gün içinde fark ediliyor. Bunu kendi Semgrep taramam yakaladı.
- **gitleaks binary'si checksum ile doğrulanıyor**, gitleaks-action yerine doğrudan release kullanılıyor.
- **GCP'ye anahtarsız giriş.** Repo'da service account JSON yok; Workload Identity Federation ile GitHub OIDC token'ı kullanılıyor ve provider sadece bu repo + main branch'ten gelen token'ları kabul ediyor.
- **Scan edilen imaj = deploy edilen imaj.** Deploy job'u yeniden build etmiyor, image job'unun push ettiği digest'i taşıyor.
- **Container root değil** (uid 10001), multi-stage build, slim base.
- `ignore-unfixed: true`: düzeltmesi olmayan base image CVE'leri için pipeline'ı kırmak bir şey kazandırmıyor, sadece gürültü. Bunlar yine de Security sekmesinde görünüyor.

## Kendi Semgrep kuralları

`semgrep/rules.yml`: `eval`/`exec`, `shell=True`, `verify=False`, production'da `reload=True`.

## Yerelde çalıştırma

```bash
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
pytest
uvicorn app.main:app --reload
```

```bash
docker build -t notes-api .
docker run -p 8080:8080 notes-api
```

## Deploy kurulumu (tek seferlik)

```bash
./deploy/setup-gcp.sh <gcp-project-id> <owner/repo> europe-west1
```

Script Artifact Registry'yi, deployer service account'u ve WIF pool/provider'ı oluşturuyor, gereken değerleri repo variable olarak yazıyor. `GCP_PROJECT_ID` tanımlı değilse deploy job'u atlanıyor, geri kalan pipeline yine çalışıyor.

## API

| method | path | |
|---|---|---|
| GET | /health | |
| GET | /notes | |
| POST | /notes | `{"title": "...", "body": "..."}` |
| GET | /notes/{id} | |
| DELETE | /notes/{id} | |

Veriler bellekte tutuluyor, restart'ta gidiyor. Bilerek.
