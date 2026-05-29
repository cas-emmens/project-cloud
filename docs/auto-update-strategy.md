# Auto-update strategy

Every container and Helm chart in the stack falls into one of four
tiers. The tier sets how aggressively new versions roll out — fully
automatic, alert-and-review, manual, or never. The goal is to ride
patch releases for free where it's safe, and to never get
silently broken by an upstream major bump.

## Tier table

| Tier | Description | What's in it | How updates happen |
|---|---|---|---|
| **A** | Customer apps managed by Argo CD | Customer Uptime Kuma instances (`customer-instances`, `test-customers`) | **Auto.** Drone builds a new image and pushes to the Gitea registry. Argo CD Image Updater detects the new SHA tag, rewrites every `customers/*.yaml` in the corresponding Gitea repo, Argo CD reconciles → all customers running the new image within ~60s of the push. |
| **B** | Platform apps managed by Argo CD | Management tool (after the Phase E refactor) | Same as Tier A — once the MT's deployment manifest moves into a GitOps repo, it inherits the same auto-update path with no extra wiring. |
| **C** | Platform services installed by Helm | Gitea, Drone server, Drone runner, DinD, Argo CD, Argo CD Image Updater, kube-prometheus-stack, Headlamp, Semaphore | **Pinned.** Chart versions and image tags are declared as variables at the top of `bootstrap-platform.yml`. Bumping a pin is a deliberate commit with release-notes-driven justification. A clean `./deploy.sh --destroy-first` always reproduces the same versions. |
| **D** | The cluster itself | k3s version | **Manual, infrequent.** Cluster-level upgrades happen out-of-band (e.g. once per semester) with one node at a time, after a snapshot. Not part of the everyday deploy pipeline. |

## What is pinned today

The Tier C pins live in `ansible/playbooks/bootstrap-platform.yml` in
the `vars:` block at the top of the platform play. Current values:

| Component | Variable | Value |
|---|---|---|
| Gitea chart | `gitea_chart_version` | `10.4.1` |
| Argo CD chart | `argocd_chart_version` | `7.6.12` |
| Argo CD Image Updater chart | `argocd_image_updater_chart_version` | `0.11.0` |
| kube-prometheus-stack chart | `prometheus_stack_chart_version` | `65.1.1` |
| Headlamp chart | `headlamp_chart_version` | `0.27.0` |
| Semaphore image | `semaphore_image` | `semaphoreui/semaphore:v2.10.34` |

Container images embedded in kubectl-applied manifests (Drone server,
Drone runner, DinD) are pinned inline:

- `drone/drone:2.20.0`
- `drone/drone-runner-docker:1` (major pin — needed for compatibility with our drone-server)
- `docker:26-dind` (major pin — DinD API has to match the docker client baked into `plugins/docker`)

## Why not auto-update Tier C as well

Two real incidents in this codebase argue against auto-upgrading
platform services:

1. **Drone 2.x port validation.** A newer 2.x release added strict
   validation that rejected our `DRONE_SERVER_HOST=10.24.36.10:30081`
   config. The fix required architectural changes (LoadBalancer
   service on port 80 + drop the port from the env var). An
   auto-upgrade would have silently broken the platform.
2. **DinD API version mismatch.** `plugins/docker` in our Drone
   pipelines requires Docker API 1.44; DinD `24-dind` only supports
   up to 1.43. Bumping to `26-dind` fixed it. A floating tag would
   have silently flipped which version got pulled on the next
   redeploy.

Both bugs were fixable, but only because we noticed them. Auto-applying
upstream chart updates on a school-project cadence is asking for
the same class of incident to land mid-presentation.

## How a sales-lane image update flows

The end-to-end story for Tier A, as a concrete example:

1. A developer commits to the `orange-uptime-kuma` repo on GitHub.
2. Drone CI builds the new image and pushes
   `10.24.36.10:30080/orange/orange-uptime-kuma:<sha7>` to the
   Gitea registry.
3. Argo CD Image Updater is polling that registry. It sees the new
   tag, picks it up because the `customer-instances` Application
   carries the `argocd-image-updater.argoproj.io/image-list`
   annotation matching this image.
4. The updater clones the `customer-instances` Gitea repo, rewrites
   the `image:` field in every `customers/*.yaml` to the new SHA,
   commits as user `image-updater` and pushes.
5. Argo CD sees the new commit, syncs each customer's Deployment to
   the new image, and the cluster rolls forward.

Audit trail at every step: Drone build log, Gitea registry tag
history, Git commit log on the `customer-instances` repo, Argo CD
sync history. Reverting a bad update is `git revert` on the manifest
commit; Argo CD reconciles back to the previous image automatically.

## Bumping a Tier C pin (the right way)

1. Read the upstream chart's release notes for breaking changes.
2. Edit only the relevant variable in `bootstrap-platform.yml`.
3. Run `./deploy.sh --destroy-first` against a staging cluster.
4. Verify the affected service still works end-to-end (login,
   build trigger, sync, etc.).
5. Commit the bump as a single `chore:` change with a link to the
   release notes in the message.

Never bump multiple pins in one commit. Never bump a major version
without notes in the commit body explaining the migration steps.
