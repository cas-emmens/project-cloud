# Management Tool pivot — from provisioning UI to customer health dashboard

Status: **direction agreed, refactor pending** in the
`orange-uptime-kuma-management-tool` repo. This document captures the
target shape so the team can land the refactor in a single coherent
pass.

---

## Why the pivot

The school rubric explicitly names Semaphore as the salesperson tool
("scripts worden via de Semaphore UI gestart"). Aligning with that
literal text removes any "is this *vergelijkbaar product*?" argument at
grading. With Semaphore now hosting both provisioning templates
(`Nieuwe klant aanmaken`, `Testklant aanmaken`) and Argo CD applying
the manifests they commit, the Management Tool no longer needs to do
provisioning.

The MT is too useful to throw away. Same code, same branding, new
purpose: a **read-only customer health dashboard** aggregating
information from the cluster (k8s API), the GitOps source of truth
(Gitea API) and the deployment engine (Argo CD API).

## New role at a glance

| Concern | Before | After |
|---|---|---|
| Who provisions customers? | MT (kubectl) | Semaphore (Ansible → Gitea → Argo CD) |
| Who shows customer status? | MT (basic list) | MT (full dashboard) |
| Writes to k8s? | Yes | **No** |
| Writes to Gitea? | No | **No** |
| Reads from k8s? | Yes | Yes (read-only) |
| Reads from Gitea? | No | Yes (commit history per customer) |
| Reads from Argo CD? | No | Yes (sync + health status) |

## What the dashboard shows per customer

For each `customer-<slug>` namespace, surfaced via a grid or table:

- **Identity:** customer slug, the `provisioned-by` label
  (sales / ops), the contact email from the
  `orange-kuma/customer-email` annotation.
- **Cluster state:** namespace age, deployment replica counts, pod
  phase (Running / Pending / Failed), restart count.
- **GitOps state:** which repo the manifest lives in
  (`customer-instances` or `test-customers`), the latest commit on
  that file (author, message, sha, timestamp).
- **Argo CD state:** sync status (Synced / OutOfSync), health
  (Healthy / Progressing / Degraded), last sync time.

Optional polish:

- A "Nieuwe klant aanmaken" button on the dashboard that
  **deep-links** into Semaphore's template UI
  (`http://10.24.36.10:30084/project/<id>/template/<id>`) — the sales
  rep clicks from the Orange Kuma branded dashboard and lands in the
  Semaphore form they need to fill. Pre-rendered URL, no client-side
  Semaphore API plumbing needed.

## Integrations the MT pod needs

### Kubernetes API
Already wired via the in-cluster `ServiceAccount management-tool`.
After the ClusterRole shrinkage (below) it's read-only.

### Gitea API
Already reachable via the existing `GITEA_URL` ConfigMap value. Add a
non-write token if private repo reads are ever needed; while
`customer-instances` and `test-customers` are public there is
nothing to add.

### Argo CD API
New integration. Add a ConfigMap entry:

- `ARGOCD_API_URL: "http://argocd-server.argocd.svc"` (in-cluster
  HTTP, the same way Semaphore reaches Gitea).

Argo CD's API needs a bearer token. Two ways:
- Create an Argo CD local user with read-only role and mint a token
  via `argocd account generate-token` — the token gets dropped into
  a Secret the MT mounts.
- Or use Argo CD project tokens (CRD-driven, more idiomatic).

Whichever is chosen, the MT only needs `applications, get` and
`applications, list` permissions.

## k8s permissions shrinkage

In `k8s/management-tool/deployment.yml`, the ClusterRole currently
allows create/patch/update/delete on `namespaces`, `deployments`,
`services`, `persistentvolumeclaims`, `networkpolicies`. **Reduce to
read-only on the resources the dashboard renders:**

```yaml
rules:
  - apiGroups: [""]
    resources: ["namespaces", "pods", "services"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch"]
```

All write verbs go away. NetworkPolicy and PVC rules can be removed
entirely — the dashboard does not render them.

## Source-side checklist for the MT repo refactor

These belong in the `orange-uptime-kuma-management-tool` repo, **not**
in `project-cloud`:

- [ ] Remove the `POST /api/customers` handler (Semaphore owns
      creation now).
- [ ] Remove the `DELETE /api/customers/:id` handler. Deprovisioning
      moves to a future `deprovision-customer.yml` Ansible playbook
      run from Semaphore.
- [ ] Add a customer-list endpoint that queries
      `kubernetes.client.namespaces.list(labelSelector='app=orange-kuma')`
      and joins with Argo CD + Gitea data.
- [ ] Add an Argo CD client (or just `fetch`) authenticated with the
      new bearer token Secret.
- [ ] Add a Gitea client for reading per-customer commit history.
- [ ] Update the UI: a single page listing all customers with the
      columns above. No "create customer" form (link out to Semaphore
      instead).
- [ ] Drop the `better-sqlite3` dependency if it was only used for
      tracking creations the MT itself made (no longer needed; Git is
      the source of truth).

## Compatibility notes

- The existing MT image stays in the Gitea registry; the deployment
  manifest's image reference doesn't change.
- The deployment's name, namespace and Service port stay the same so
  Phase 4 verification (`kubectl -n orange-kuma get deploy
  management-tool`) keeps working through the refactor.
- The new Argo CD ConfigMap key and the bearer-token Secret are the
  only deployment.yml additions. Everything else *shrinks*.

## Out of scope for this document

- Authentication for the dashboard itself. Right now any visitor on
  the cluster network can hit it. Adding OIDC (via Argo CD's Dex, or
  Gitea OAuth) is a reasonable follow-up but not required by the
  rubric.
- Per-customer dashboards (drilling into a single customer's Uptime
  Kuma metrics). The Kuma instance has its own UI on its own
  ClusterIP — a sensible future addition is a per-customer Ingress
  that the MT links out to.
