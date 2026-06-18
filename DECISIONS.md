# Architecture Decision Records

This document captures the key design decisions behind this project, the trade-offs considered, and the rationale for each choice. Each record follows a lightweight ADR format: **Context → Decision → Consequences → Alternatives considered.**

---

## ADR-001: Provision everything with Terraform (Infrastructure as Code)

**Context.** The same architecture can be built by clicking through the Cloud Console. That approach is fast for a one-off but is not reproducible, not reviewable, and not easily destroyable, which matters for a billable demo environment.

**Decision.** Define the entire stack declaratively in Terraform. No resource is created manually.

**Consequences.**
- The environment is reproducible from scratch with a single `terraform apply` and fully removable with `terraform destroy`, important for cost control.
- The configuration is reviewable as code and version-controlled.
- Adds a dependency on Terraform/provider versions, which are pinned in `provider.tf`.

**Alternatives considered.** Console clickops (rejected: not reproducible); `gcloud` shell scripts (rejected: imperative, no state reconciliation or drift detection).

---

## ADR-002: Regional Managed Instance Group instead of zonal

**Context.** A zonal MIG keeps all instances in a single zone. A zone is a single failure domain; a zonal outage would take the whole application down, defeating the "highly available" goal.

**Decision.** Use a **regional** MIG, which spreads instances across multiple zones in the region automatically.

**Consequences.**
- The application survives the loss of an entire zone, observed in testing, where instances were distributed across `europe-west1-b/c/d`.
- Slightly higher complexity (regional resources, regional autoscaler).

**Alternatives considered.** Zonal MIG (rejected: single failure domain); multi-region deployment (deferred: unnecessary cost/complexity for the stated scope, but noted as a future extension).

---

## ADR-003: Private instances with Cloud NAT for egress (no external IPs)

**Context.** Instances need outbound internet access (to install Nginx at boot) but should not be directly reachable from the internet.

**Decision.** Give instances **private IPs only** (no `access_config` block in the instance template) and route outbound traffic through **Cloud NAT** via a Cloud Router.

**Consequences.**
- The attack surface is dramatically reduced: there is no public endpoint on any VM.
- Outbound access (package installs, updates) still works through NAT.
- Requires a Cloud Router + Cloud NAT, and the load balancer/health-check firewall rules must explicitly allow Google's infrastructure ranges.

**Alternatives considered.** Public IPs on each VM (rejected: unnecessary exposure); proxy/bastion for all egress (rejected: Cloud NAT is the managed, lower-maintenance option).

---

## ADR-004: IAP-tunneled SSH instead of a public bastion or open port 22

**Context.** Administrative SSH access is needed, but exposing port 22 to the internet (even to a bastion with a public IP) is a common and avoidable risk.

**Decision.** Use **Identity-Aware Proxy** for SSH (`gcloud compute ssh --tunnel-through-iap`). The firewall permits port 22 only from the IAP source range `35.235.240.0/20`.

**Consequences.**
- No public SSH endpoint and no bastion VM to patch and maintain.
- Access is gated by IAM identity rather than network position.
- Requires the IAP API to be enabled and the corresponding firewall rule.

**Alternatives considered.** Public bastion host (rejected: extra VM, still an exposed surface); open `0.0.0.0/0` on port 22 (rejected: insecure).

---

## ADR-005: Global external HTTP(S) Load Balancer

**Context.** The entrypoint must distribute traffic across the regional MIG, perform health checking, and be highly available itself.

**Decision.** Use GCP's **global external Application Load Balancer** (`EXTERNAL_MANAGED` scheme) with a backend service bound to the MIG's instance group and an HTTP health check.

**Consequences.**
- The LB is anycast and globally distributed, it is not itself a single point of failure.
- A single static global IP serves as the stable entrypoint.
- The `EXTERNAL_MANAGED` scheme must be used consistently across the forwarding rule and backend service.

**Alternatives considered.** Regional load balancer (rejected: less resilient entrypoint); network (L4) load balancer (rejected: L7 features such as Cloud Armor and URL maps are wanted here).

---

## ADR-006: One health check reused for autohealing and the LB backend

**Context.** Both the MIG (for autohealing) and the load balancer backend service need an HTTP health check. They could be defined separately.

**Decision.** Define a **single** HTTP health check and reference it from both the autohealing policy and the backend service.

**Consequences.**
- Consistent definition of "healthy" across self-healing and traffic routing, no divergence between the two.
- One resource to tune (interval, thresholds).

**Alternatives considered.** Two independent health checks (rejected: risk of inconsistent health semantics and duplicated configuration).

---

## ADR-007: Cloud Armor `rate_based_ban` policy at the edge

**Context.** The backend should have basic protection against volumetric abuse from a single source before requests reach the instances.

**Decision.** Attach a **Cloud Armor** security policy with a `rate_based_ban` rule (100 requests / 60s per IP, ban for 600s) to the backend service, plus a default-allow rule.

**Consequences.**
- Abusive clients are throttled at the edge, not on the instances.
- `rate_based_ban` requires `ban_duration_sec`; omitting it is rejected by the API at apply time.
- The thresholds are illustrative and would be tuned against real traffic in production.

**Alternatives considered.** `throttle` action (viable, no ban duration required, but rejected here in favor of demonstrating temporary banning); no edge policy (rejected: leaves the backend unprotected).

---

## ADR-008: Serve HTTP by default; document HTTPS as an optional upgrade

**Context.** A Google-managed SSL certificate requires a domain name whose DNS points at the load balancer IP. Hardcoding a domain would make the project non-reproducible for anyone cloning it.

**Decision.** Ship the default deployment on **HTTP** so it stands up with zero external dependencies, and **document** the HTTPS path (managed certificate, HTTPS target proxy, 443 forwarding rule, HTTP→HTTPS redirect) for anyone who has a domain.

**Consequences.**
- Anyone can deploy and validate the architecture without owning a domain.
- TLS is a documented, additive step rather than a hard prerequisite.

**Alternatives considered.** Self-signed certificate (rejected: poor UX, browser warnings); mandatory managed cert (rejected: introduces a domain/DNS dependency that breaks reproducibility).

---

## ADR-009: `e2-small` instances on Debian 12

**Context.** The compute size and base image affect cost and boot behavior for a demo workload that only serves a static page via Nginx.

**Decision.** Use **`e2-small`** (cost-efficient, burstable) instances running **Debian 12**, bootstrapped by a startup script that installs Nginx and renders the instance name and zone.

**Consequences.**
- Low cost; sufficient for the workload and for triggering CPU-based autoscaling under `stress`.
- The instance/zone in the served page provides immediate, visible proof of load distribution.

**Alternatives considered.** Larger machine types (rejected: unnecessary cost); a pre-baked custom image (deferred: a startup script is simpler for this scope, though a baked image would cut boot time in production).

---

## ADR-010: Local Terraform state (with a documented path to remote state)

**Context.** Terraform state can live locally or in a remote backend (e.g., a GCS bucket) with locking.

**Decision.** Use **local state** for this single-author portfolio project, and exclude `*.tfstate` and `*.tfvars` from version control via `.gitignore`.

**Consequences.**
- Simple to run and review; no bootstrap bucket required.
- Not suitable for teams or CI-driven applies, remote state with locking is listed as a roadmap item.
- Secrets and state never reach the public repository.

**Alternatives considered.** GCS remote backend from the start (deferred: adds a chicken-and-egg bootstrap step that isn't justified for a solo demo, but is the correct choice for team/production use).