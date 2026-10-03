# devsecops-notes-api

A small FastAPI notes service. The API itself isn't the point; the CI/CD pipeline around it is. Code doesn't reach `main` and an image doesn't get deployed unless it passes a set of security gates.

## Pipeline

```
push / PR
  ├─ test        pytest
  ├─ gitleaks    secret scan over the full git history
  ├─ semgrep     SAST (p/python, p/owasp-top-ten, p/dockerfile + custom rules)
  └─ trivy-fs    dependency CVEs + Dockerfile misconfig
        │
        ▼  (all four must pass)
     image       build → trivy image scan → push to ghcr (main only)
        │
        ▼
     deploy      copy the scanned digest to Artifact Registry → Cloud Run → /health smoke test
```

Gates fail the build on HIGH/CRITICAL findings that have a fix available. Every scanner uploads SARIF, so all findings show up under Security > Code scanning.

## Design decisions

- **Actions are pinned to commit SHAs.** Tags can be moved (see the tj-actions/changed-files incident), SHAs can't. Dependabot keeps them up to date.
- **Dependabot has a 7-day cooldown.** Compromised packages usually get caught within a few days of release. My own Semgrep run flagged the missing cooldown.
- **The gitleaks binary is verified against the release checksums** instead of using a third-party action.
- **Keyless auth to GCP.** No service account JSON in the repo. Workload Identity Federation exchanges the GitHub OIDC token, and the provider only accepts tokens from this repo's `main` branch.
- **The scanned image is the deployed image.** The deploy job doesn't rebuild, it promotes the exact digest the image job pushed.
- **Runtime image is minimal.** Non-root (uid 10001), multi-stage build, Debian security updates applied, and pip/setuptools removed from the final stage since they vendor their own copies of urllib3 and friends.
- `ignore-unfixed: true`: failing the build on base image CVEs with no available fix just adds noise. They're still reported in the Security tab.

### What the gates caught on the first run

The first image scan failed on a HIGH in Debian's `libpcre2` and on outdated `urllib3`, `msgpack` and `setuptools` that were vendored inside the base image's pip. None of them were in my own dependencies, which is exactly why the image scan exists in addition to the dependency scan. Fixed by upgrading OS packages and removing pip from the runtime stage.

## Custom Semgrep rules

`semgrep/rules.yml`: `eval`/`exec`, `shell=True`, `verify=False`, and `reload=True` shipping to production.

## Running locally

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

## Deploy setup (one time)

```bash
./deploy/setup-gcp.sh <gcp-project-id> <owner/repo> europe-west1
```

Creates the Artifact Registry repo, a deployer service account and the WIF pool/provider, then writes the required values as repo variables. If `GCP_PROJECT_ID` isn't set, the deploy job is skipped and the rest of the pipeline still runs.

## API

| method | path | |
|---|---|---|
| GET | /health | |
| GET | /notes | |
| POST | /notes | `{"title": "...", "body": "..."}` |
| GET | /notes/{id} | |
| DELETE | /notes/{id} | |

Data lives in memory and is gone on restart. On purpose.
