# demo-service

Python's standard HTTP server plus `prometheus-client==0.21.1`. No database or external backend. Endpoints: `GET /`, `/health`, `/ready`, `/metrics`; unknown GET paths return 404. Every GET logs JSON to stdout and records counter/histogram samples with bounded route labels. Metrics cover the current process only.

For local development (Python 3.9+):

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python app.py
curl -f http://localhost:8080/health
```

The server listens on port 8080. `SERVICE_VERSION` defaults to `0.1.0`. From the repository root, `make build-image` builds `demo-service:0.1.0` and loads it into the existing kind cluster. Argo CD owns the deployment; see the root README for GitOps and rebuild workflows.

Future backend-dependent behavior can be implemented in `do_GET` without changing the metric or logging pipeline. No incident behavior is implemented yet.
