<!-- --8<-- [start:content] -->
# SATP Hermes local Kubernetes deployment (Terraform)

Terraform Infrastructure-as-Code for running SATP Hermes gateways on a
local Kubernetes cluster. Implements
[hyperledger-cacti/cacti#4706](https://github.com/hyperledger-cacti/cacti/issues/4706).

## What gets deployed

| Workload | Replicas | Ports (in-cluster) | Host ports (default offset `30100`) |
| --- | --- | --- | --- |
| `gateway-1` (primary) | `gateway_replicas` | server `3010` / client `3011` / OpenAPI `4010` | `30100` / `30101` / `30102` |
| `gateway-2` (backup) | `gateway_replicas` | server `3010` / client `3011` / OpenAPI `4010` | `30110` / `30111` / `30112` |
| `otel-lgtm` (optional) | 1 | Grafana `3000` / OTLP `4317-4318` / Prometheus `9090` | Grafana `30200` / OTLP-HTTP `30201` |

Gateway configs are rendered from
[`templates/satp-gateway-config.json.tftpl`](./templates/satp-gateway-config.json.tftpl),
which mirrors
[`src/examples/config/`](../../src/examples/config/satp-gateway1-config.json)
(gateway-1) and
[`satp-gateway2-config.json`](../../src/examples/config/satp-gateway2-config.json)
(gateway-2). In-cluster DNS keeps the example hostnames working:
`satp-hermes-gateway-1` and `satp-hermes-gateway-2` are the ClusterIP
Service names. This matches the topology in
[`docker-compose-satp.yml`](../../docker-compose-satp.yml) plus the second
gateway and Kubernetes service discovery.

> Development credentials and keys in the default configs mirror the
> tracked example configs. Replace them for any non-development
> deployment (see [Gateway Configuration](../../docs/configuration.md)).

## Prerequisites

| Tool | Minimum version | Install |
| --- | --- | --- |
| Terraform | `>= 1.5` | <https://developer.hashicorp.com/terraform/install> |
| Docker | any recent | <https://docs.docker.com/get-docker/> |
| kind | `>= 0.20` | <https://kind.sigs.k8s.io/docs/user/quick-start/#installation> |
| kubectl | `>= 1.28` | <https://kubernetes.io/docs/tasks/tools/> |

No prior Terraform knowledge is required beyond the commands below.

## Step-by-step deployment

```sh
# 1. Build the gateway image from the package root so kind can load it.
cd packages/cactus-plugin-satp-hermes
docker build -f satp-hermes-gateway.Dockerfile -t satp-hermes-gateway:local .

# 2. Start local Ethereum test ledgers the gateways bridge to.
#    Defaults: gateway-1 -> :8545, gateway-2 -> :8546
#    (override with -var ledger_rpc_url_1=... -var ledger_rpc_url_2=...).
#    On Linux, host.docker.internal does not resolve by default; either
#    export host IPs or pass reachable URLs, e.g.:
#    -var ledger_rpc_url_1=http://192.168.1.10:8545

# 3. Provision the cluster and deploy everything.
cd deploy/terraform
terraform init
terraform validate
terraform plan -out satp.plan
terraform apply satp.plan
```

To scale the gateway tier horizontally (the `n` in the target topology):

```sh
terraform apply -var gateway_replicas=3
```

To point at existing registry images instead of a locally built one:

```sh
terraform apply -var load_gateway_image=false \
  -var gateway_image=ghcr.io/your-org/satp-hermes-gateway:<tag>
```

## Verify the deployment

```sh
# 1. Nodes and pods are ready.
kubectl --kubeconfig ~/.kube/kind-satp-hermes get nodes
kubectl -n satp-hermes get pods -w

# 2. Both gateways report AVAILABLE (mirrors the container HEALTHCHECK).
curl -s http://localhost:30102/api/v1/@hyperledger-cacti/cactus-plugin-satp-hermes/healthcheck
# {"status":"AVAILABLE"}
curl -s http://localhost:30112/api/v1/@hyperledger-cacti/cactus-plugin-satp-hermes/healthcheck
# {"status":"AVAILABLE"}

# 3. Gateway-to-gateway connectivity from inside the cluster.
kubectl -n satp-hermes exec deploy/satp-gateway-1 -- \
  curl -s http://satp-hermes-gateway-2:4010/api/v1/@hyperledger-cacti/cactus-plugin-satp-hermes/healthcheck
# {"status":"AVAILABLE"}

# 4. Observability backend.
open http://localhost:30200  # Grafana (otel-lgtm)
```

Basic end-to-end asset transfer test: with both healthchecks green and
the ledger RPC endpoints reachable, drive a transfer through the
gateway-1 OpenAPI service (`http://localhost:30102`) following the
[application-to-gateway API examples](../../docs/operations.md#health-and-status-endpoints)
and poll the transfer status endpoint on either gateway until the
session reaches a terminal state.

## Teardown

```sh
cd deploy/terraform
terraform destroy
kind delete cluster --name satp-hermes  # only if the destroy leftovers
rm -f satp.plan
```

`terraform destroy` removes the kind cluster and all SATP workloads.
Gateway sqlite data lives on cluster PVCs and is deleted with them;
nothing is written to the host outside `~/.kube/kind-satp-hermes`.

## Verified

Validated end to end on Ubuntu 26.04 (Terraform 1.16.5, kind 0.31.0,
kubectl 1.37.1, Docker 29.7.2) against this branch:

- `terraform init`, `terraform validate` (no warnings), and
  `terraform plan` (16 to add, 0 to change) all pass.
- `terraform apply` brings up the kind cluster with both gateways
  `1/1 Running`; both host healthchecks, gateway-to-gateway healthcheck,
  and Grafana all respond as documented above.
- The package suite
  `test:integration:docker-local/satp-e2e-transfer-dockerization.test.ts`
  passes 3/3, each realizing a real SATP asset transfer between
  containerized gateways backed by Besu and Go-Ethereum test ledgers.

## Files

| File | Purpose |
| --- | --- |
| [`versions.tf`](./versions.tf) | Terraform + provider (`kind`, `kubernetes`) pins |
| [`variables.tf`](./variables.tf) | Cluster name, image, replicas, ledger endpoints, ports |
| [`main.tf`](./main.tf) | kind cluster, namespace, ConfigMaps, PVCs, Deployments, Services, otel stack, image load |
| [`outputs.tf`](./outputs.tf) | Healthcheck URLs, Grafana URL, kubeconfig path |
| [`templates/`](./templates/) | Gateway `config.json` template (per-gateway identity + counterparty) |

## Extending to the cloud

The module targets local `kind` per the issue's first phase. The
workload resources (namespace and below) are cloud-agnostic: point the
`kubernetes` provider at an EKS/GKE/AKS kubeconfig, drop the
`kind_cluster` resource and the `null_resource` image load (push
`gateway_image` to a registry instead), and replace `NodePort` Services
with your ingress of choice.
<!-- --8<-- [end:content] -->
