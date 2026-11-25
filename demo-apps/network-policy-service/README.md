# NetworkPolicy-Service

Eigenständiger HTTP-Service ohne Python-Abhängigkeiten. Alle Befehle starten im Repository-Root. Die bestehende Demo und ihre Argo-CD-Anwendung werden nicht verändert.

| GET-Endpunkt | Verhalten |
| --- | --- |
| `/hello` | `Hello from <namespace>` als Text, HTTP 200 |
| `/call` | Ruft `/hello` des konfigurierten Partners auf und liefert dessen Text |
| `/health`, `/ready` | Lokal HTTP 200; mit `CHECK_PEER=true` Partnerprüfung |
| `/startup` | Prüft immer den Partner |

`POD_NAMESPACE` (Standard `local`) bestimmt die Antwort. `PEER_URL` ist die Basis-URL des Partners ohne `/hello`. `CHECK_PEER` ist standardmäßig `false`. Der Partneraufruf hat zwei Sekunden Timeout und keine Wiederholung. HTTP-/Verbindungsfehler liefern bei `/call` 502, Timeouts 504; fehlgeschlagene Probes liefern 503. Jeder eingehende und ausgehende GET-Aufruf erzeugt einen JSON-Logeintrag auf stdout. Fehlerursachen werden protokolliert; ein Timeout allein beweist keine NetworkPolicy-Sperre.

## Image und Deployment

Voraussetzungen: Docker, kubectl, Kustomize mit Component-Unterstützung sowie ein Zielcluster, dessen CNI NetworkPolicies durchsetzt. Die vorhandene kind-Konfiguration installiert kein solches Plugin. Ohne Durchsetzung kann ein Policy-Objekt existieren, ohne Traffic zu blockieren. Andere bereits vorhandene Policies können das Ergebnis beeinflussen; NetworkPolicy-Freigaben wirken additiv.

Den Zielkontext ausdrücklich auf einen geeigneten Testcluster setzen:

```bash
export DEMO_CONTEXT=$(k config current-context)
export DEMO_IMAGE='<registry>/<repository>/network-policy-service:0.1.0'
docker build -t "$DEMO_IMAGE" demo-apps/network-policy-service
docker push "$DEMO_IMAGE"

# Image in beiden Namespace-Overlays konfigurieren:
(cd gitops/network-policy-service/overlays/a && kustomize edit set image "network-policy-service=$DEMO_IMAGE")
(cd gitops/network-policy-service/overlays/b && kustomize edit set image "network-policy-service=$DEMO_IMAGE")

kubectl --context "$DEMO_CONTEXT" apply -k gitops/network-policy-service/overlays/a
kubectl --context "$DEMO_CONTEXT" apply -k gitops/network-policy-service/overlays/b
kubectl --context "$DEMO_CONTEXT" -n network-demo-a rollout status deployment/network-policy-service --timeout=180s
kubectl --context "$DEMO_CONTEXT" -n network-demo-b rollout status deployment/network-policy-service --timeout=180s
```

Für einen vorhandenen, NetworkPolicy-fähigen kind-Testcluster alternativ lokal bauen und laden, statt zu pushen:

```bash
export DEMO_CONTEXT='kind-<clustername>'
docker build -t network-policy-service:0.1.0 demo-apps/network-policy-service
kind load docker-image network-policy-service:0.1.0 --name '<clustername>'
```

Die Manifeste verwenden dieses lokale Image bereits mit `IfNotPresent`. Für private Registries muss der Cluster Lesezugriff haben. Der Service läuft als UID 10001 mit schreibgeschütztem Dateisystem und ohne ServiceAccount-Token.

## Aufrufe und Policies testen

In einem eigenen Terminal Instanz A weiterleiten:

```bash
kubectl --context "$DEMO_CONTEXT" -n network-demo-a port-forward service/network-policy-service 8080:8080 --address 127.0.0.1
```

In einem zweiten Terminal (mit denselben Umgebungsvariablen):

```bash
curl -i http://localhost:8080/hello  # Hello from network-demo-a
curl -i http://localhost:8080/call   # Hello from network-demo-b

kubectl --context "$DEMO_CONTEXT" apply -f gitops/network-policy-service/policies/deny-b.yaml
curl -i http://localhost:8080/call   # nach Policy-Propagation: 502 oder 504

kubectl --context "$DEMO_CONTEXT" apply -f gitops/network-policy-service/policies/allow-a-to-b.yaml
curl -i http://localhost:8080/call   # nach Policy-Propagation wieder 200

kubectl --context "$DEMO_CONTEXT" -n network-demo-a logs deployment/network-policy-service --tail=30
kubectl --context "$DEMO_CONTEXT" -n network-demo-b logs deployment/network-policy-service --tail=30
```

Die Sperre betrifft nur Ingress zu den Demo-Pods in B. Die zusätzliche Freigabe erlaubt TCP 8080 ausschließlich von Demo-Pods in A; Namespace- und Pod-Selektor stehen im selben `from`-Eintrag. Egress und DNS werden nicht eingeschränkt. Bei erfolgreichem Aufruf sieht man in A `/call` und `peer_request`, in B `/hello`. Port-forward direkt nach B eignet sich nicht als Nachweis des Pod-zu-Pod-Policy-Verhaltens.

Vor erneutem Sperrtest die additive Freigabe entfernen:

```bash
kubectl --context "$DEMO_CONTEXT" delete -f gitops/network-policy-service/policies/allow-a-to-b.yaml --ignore-not-found
```

## Optionale Partner-Probes

Zunächst beide Policies entfernen, dann statt der normalen Overlays die Probe-Varianten anwenden:

```bash
kubectl --context "$DEMO_CONTEXT" delete -f gitops/network-policy-service/policies/ --ignore-not-found
kubectl --context "$DEMO_CONTEXT" apply -k gitops/network-policy-service/overlays/a-peer-probes
kubectl --context "$DEMO_CONTEXT" apply -k gitops/network-policy-service/overlays/b-peer-probes
kubectl --context "$DEMO_CONTEXT" -n network-demo-a rollout status deployment/network-policy-service --timeout=240s
kubectl --context "$DEMO_CONTEXT" -n network-demo-b rollout status deployment/network-policy-service --timeout=240s
```

Diese Varianten übernehmen die Image-Konfiguration aus A/B, aktivieren `CHECK_PEER=true` und ergänzen die Startup-Probe. Startup prüft alle fünf Sekunden mit 24 Fehlversuchen (ungefähr zwei Minuten Budget). Danach prüfen Readiness alle fünf und Liveness alle zehn Sekunden, jeweils mit drei Fehlversuchen. Alle Kubernetes-Probes haben drei Sekunden Timeout.

`publishNotReadyAddresses: true` lässt beide Instanzen auch während gegenseitiger Startprüfungen über Service-DNS erreichbar bleiben. Das ist eine bewusste Demo-Einstellung: Nicht bereite Pods bleiben ebenfalls Service-Ziele. `/hello` selbst prüft niemals den Partner und erzeugt keine rekursiven Aufrufe.

Nun `deny-b.yaml` erneut anwenden. A verliert seine Bereitschaft und wird nach Liveness-Fehlern neu gestartet. Nach dem Neustart scheitert seine Startup-Probe; währenddessen pausieren Readiness und Liveness. B kann A weiterhin erreichen, solange dessen HTTP-Server läuft. Probe-Fehler und Neustarts beobachten:

```bash
kubectl --context "$DEMO_CONTEXT" -n network-demo-a get pods -w
# In einem weiteren Terminal:
kubectl --context "$DEMO_CONTEXT" -n network-demo-a describe pods -l app.kubernetes.io/name=network-policy-service
```

`allow-a-to-b.yaml` wieder anwenden; beide Deployments müssen anschließend wieder bereit werden. Die Server-Prozesse laufen während fehlgeschlagener Startup-Probes weiter und können `/hello` beantworten. Nach einem Neustart kann ein bestehender Port-forward abbrechen; für weitere Aufrufe neu starten.

Zum Deaktivieren wieder die normalen Overlays `a` und `b` anwenden. Zum Aufräumen ausschließlich die Demo-Namespaces löschen:

```bash
kubectl --context "$DEMO_CONTEXT" delete namespace network-demo-a network-demo-b
```

## Lokale Tests

```bash
python3 -m unittest discover -s demo-apps/network-policy-service -v
kustomize build gitops/network-policy-service/overlays/a
kustomize build gitops/network-policy-service/overlays/b
kustomize build gitops/network-policy-service/overlays/a-peer-probes
kustomize build gitops/network-policy-service/overlays/b-peer-probes
```

Die Anwendungstests prüfen echte lokale HTTP-Aufrufe, Partnerweiterleitung, beide Probe-Modi, Fehlerabbildung, Timeout-Konfiguration und Fehlerlogs. NetworkPolicy-Durchsetzung und kubelet-Neustarts müssen im Zielcluster mit obigem Ablauf verifiziert werden.
