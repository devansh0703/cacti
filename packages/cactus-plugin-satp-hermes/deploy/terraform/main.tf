# Copyright 2026 Hyperledger Cacti Contributors
# SPDX-License-Identifier: Apache-2.0
#
# SATP Hermes local Kubernetes deployment
# (hyperledger-cacti/cacti#4706).
#
# Topology:
#   kind cluster "satp-hermes"
#   +-- namespace satp-hermes
#       +-- gateway-1 (primary)  : server 3010 / client 3011 / OpenAPI 4010
#       +-- gateway-2 (backup)   : server 3010 / client 3011 / OpenAPI 4010
#       +-- otel-lgtm (optional) : Grafana 3000 / OTLP 4317-4318 / ...
#
# This mirrors docker-compose-satp.yml (one gateway + otel-lgtm) and adds
# the second gateway plus in-cluster service discovery so the pair can run
# an end-to-end asset transfer.

locals {
  healthcheck_path = "/api/v1/@hyperledger-cacti/cactus-plugin-satp-hermes/healthcheck"

  gateways = {
    "gateway-1" = {
      service_name = "satp-hermes-gateway-1"
      gateway_id   = "mockID-1"
      proof_id     = "mockProofID10"
      ledger_id    = "EthereumLedgerTestNetwork1"
      pub_key      = "036256069f81bcaae52a64965b8add79521ee54cb2ad3d85de5250d78cf0fc171c"
      priv_key     = "38c732b7b86d752c5c051a9c944a683da994eac1cc1544462518b90f89d8146d"
      eth_account  = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
      eth_secret   = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
      ledger_rpc   = var.ledger_rpc_url_1
      counterparty = {
        service_name = "satp-hermes-gateway-2"
        gateway_id   = "mockID-2"
        proof_id     = "mockProofID11"
        ledger_id    = "EthereumLedgerTestNetwork2"
        pub_key      = "024c0cf54f92d23dbb3d409a8047aa2a44abcb911767d3516b19fd94c2358dec65"
      }
    }
    "gateway-2" = {
      service_name = "satp-hermes-gateway-2"
      gateway_id   = "mockID-2"
      proof_id     = "mockProofID11"
      ledger_id    = "EthereumLedgerTestNetwork2"
      pub_key      = "024c0cf54f92d23dbb3d409a8047aa2a44abcb911767d3516b19fd94c2358dec65"
      priv_key     = "28215964122bbc927fabd1b1c6a450c22852e5784510decfdb9a104b6a121578"
      eth_account  = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
      eth_secret   = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
      ledger_rpc   = var.ledger_rpc_url_2
      counterparty = {
        service_name = "satp-hermes-gateway-1"
        gateway_id   = "mockID-1"
        proof_id     = "mockProofID10"
        ledger_id    = "EthereumLedgerTestNetwork1"
        pub_key      = "036256069f81bcaae52a64965b8add79521ee54cb2ad3d85de5250d78cf0fc171c"
      }
    }
  }

  # Development credentials above mirror
  # src/examples/config/satp-gateway{1,2}-config.json. Replace the keys
  # and endpoint URLs for any non-development deployment.
}

# ---------------------------------------------------------------------------
# Local kind cluster with host port mappings for both gateways,
# Grafana, and the OTLP HTTP endpoint.
# ---------------------------------------------------------------------------

resource "kind_cluster" "satp" {
  name            = var.cluster_name
  kubeconfig_path = pathexpand("~/.kube/kind-${var.cluster_name}")
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Gateway-1 (primary)
      extra_port_mappings {
        container_port = 30010
        host_port      = var.host_port_offset
      }
      extra_port_mappings {
        container_port = 30011
        host_port      = var.host_port_offset + 1
      }
      extra_port_mappings {
        container_port = 30012
        host_port      = var.host_port_offset + 2
      }
      # Gateway-2 (backup)
      extra_port_mappings {
        container_port = 30020
        host_port      = var.host_port_offset + 10
      }
      extra_port_mappings {
        container_port = 30021
        host_port      = var.host_port_offset + 11
      }
      extra_port_mappings {
        container_port = 30022
        host_port      = var.host_port_offset + 12
      }
      # Grafana UI (otel-lgtm)
      extra_port_mappings {
        container_port = 30030
        host_port      = var.host_port_offset + 100
      }
      # OTLP HTTP ingest (otel-lgtm)
      extra_port_mappings {
        container_port = 30031
        host_port      = var.host_port_offset + 101
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Namespace
# ---------------------------------------------------------------------------

resource "kubernetes_namespace_v1" "satp" {
  metadata {
    name = var.namespace
  }

  depends_on = [kind_cluster.satp]
}

# ---------------------------------------------------------------------------
# Per-gateway configuration (mounted at /opt/cacti/satp-hermes/config/).
# ---------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "gateway" {
  for_each = local.gateways

  metadata {
    name      = "satp-${each.key}-config"
    namespace = kubernetes_namespace_v1.satp.metadata[0].name
  }

  data = {
    "config.json" = templatefile("${path.module}/templates/satp-gateway-config.json.tftpl", {
      gateway_id                = each.value.gateway_id
      proof_id                  = each.value.proof_id
      ledger_id                 = each.value.ledger_id
      service_name              = each.value.service_name
      server_port               = 3010
      client_port               = 3011
      oapi_port                 = 4010
      pub_key                   = each.value.pub_key
      priv_key                  = each.value.priv_key
      eth_account               = each.value.eth_account
      eth_secret                = each.value.eth_secret
      ledger_rpc_url            = each.value.ledger_rpc
      counterparty_id           = each.value.counterparty.gateway_id
      counterparty_proof_id     = each.value.counterparty.proof_id
      counterparty_ledger_id    = each.value.counterparty.ledger_id
      counterparty_service_name = each.value.counterparty.service_name
      counterparty_pub_key      = each.value.counterparty.pub_key
    })
  }
}

# ---------------------------------------------------------------------------
# Persistent storage for the gateway sqlite databases.
# ---------------------------------------------------------------------------

resource "kubernetes_persistent_volume_claim_v1" "gateway_data" {
  for_each = local.gateways

  metadata {
    name      = "satp-${each.key}-data"
    namespace = kubernetes_namespace_v1.satp.metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Gateway Deployments (primary + backup) and Services.
#
# The ClusterIP Services keep the hostnames used in the gateway configs
# (satp-hermes-gateway-1/2) resolvable in-cluster; the NodePort Services
# expose each gateway on the host via the kind port mappings above.
# ---------------------------------------------------------------------------

resource "kubernetes_deployment_v1" "gateway" {
  for_each = local.gateways

  metadata {
    name      = "satp-${each.key}"
    namespace = kubernetes_namespace_v1.satp.metadata[0].name
    labels = {
      app = "satp-${each.key}"
    }
  }

  spec {
    replicas = var.gateway_replicas

    selector {
      match_labels = {
        app = "satp-${each.key}"
      }
    }

    template {
      metadata {
        labels = {
          app = "satp-${each.key}"
        }
      }

      spec {
        container {
          name              = "satp-gateway"
          image             = var.gateway_image
          image_pull_policy = "IfNotPresent"

          port {
            name           = "server"
            container_port = 3010
          }
          port {
            name           = "client"
            container_port = 3011
          }
          port {
            name           = "oapi"
            container_port = 4010
          }

          env {
            name  = "NODE_ENV"
            value = "production"
          }
          env {
            name  = "TZ"
            value = "Etc/UTC"
          }
          env {
            name  = "DATABASE_CLIENT"
            value = "sqlite3"
          }
          env {
            name  = "DATABASE_NAME"
            value = "/opt/cacti/satp-hermes/database/satp.sqlite"
          }
          env {
            name  = "OTEL_EXPORTER_OTLP_PROTOCOL"
            value = "http/protobuf"
          }
          env {
            name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
            value = "http://otel-lgtm:4318"
          }

          volume_mount {
            name       = "config"
            mount_path = "/opt/cacti/satp-hermes/config/config.json"
            sub_path   = "config.json"
            read_only  = true
          }
          volume_mount {
            name       = "data"
            mount_path = "/opt/cacti/satp-hermes/database"
          }

          liveness_probe {
            http_get {
              path = local.healthcheck_path
              port = 4010
            }
            initial_delay_seconds = 120
            period_seconds        = 10
            timeout_seconds       = 10
            failure_threshold     = 6
          }
          readiness_probe {
            http_get {
              path = local.healthcheck_path
              port = 4010
            }
            initial_delay_seconds = 60
            period_seconds        = 10
            timeout_seconds       = 10
            failure_threshold     = 12
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.gateway[each.key].metadata[0].name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.gateway_data[each.key].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "gateway" {
  for_each = local.gateways

  metadata {
    name      = each.value.service_name
    namespace = kubernetes_namespace_v1.satp.metadata[0].name
  }

  spec {
    selector = {
      app = "satp-${each.key}"
    }

    port {
      name        = "server"
      port        = 3010
      target_port = 3010
    }
    port {
      name        = "client"
      port        = 3011
      target_port = 3011
    }
    port {
      name        = "oapi"
      port        = 4010
      target_port = 4010
    }
  }
}

resource "kubernetes_service_v1" "gateway_nodeport" {
  for_each = local.gateways

  metadata {
    name      = "${each.value.service_name}-external"
    namespace = kubernetes_namespace_v1.satp.metadata[0].name
  }

  spec {
    type = "NodePort"
    selector = {
      app = "satp-${each.key}"
    }

    port {
      name        = "server"
      port        = 3010
      target_port = 3010
      node_port   = each.key == "gateway-1" ? 30010 : 30020
    }
    port {
      name        = "client"
      port        = 3011
      target_port = 3011
      node_port   = each.key == "gateway-1" ? 30011 : 30021
    }
    port {
      name        = "oapi"
      port        = 4010
      target_port = 4010
      node_port   = each.key == "gateway-1" ? 30012 : 30022
    }
  }
}

# ---------------------------------------------------------------------------
# Observability backend (mirrors the otel-lgtm service in
# docker-compose-satp.yml).
# ---------------------------------------------------------------------------

resource "kubernetes_deployment_v1" "otel" {
  count = var.enable_observability ? 1 : 0

  metadata {
    name      = "otel-lgtm"
    namespace = kubernetes_namespace_v1.satp.metadata[0].name
    labels = {
      app = "otel-lgtm"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "otel-lgtm"
      }
    }

    template {
      metadata {
        labels = {
          app = "otel-lgtm"
        }
      }

      spec {
        container {
          name  = "otel-lgtm"
          image = var.otel_image

          port {
            container_port = 3000
          }
          port {
            container_port = 4317
          }
          port {
            container_port = 4318
          }
          port {
            container_port = 9090
          }

          env {
            name  = "OTEL_METRIC_EXPORT_INTERVAL"
            value = "1000"
          }
          env {
            name  = "OTEL_EXPORTER_OTLP_METRICS_DEFAULT_HISTOGRAM_AGGREGATION"
            value = "explicit_bucket_histogram"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "otel" {
  count = var.enable_observability ? 1 : 0

  metadata {
    name      = "otel-lgtm"
    namespace = kubernetes_namespace_v1.satp.metadata[0].name
  }

  spec {
    selector = {
      app = "otel-lgtm"
    }

    port {
      name        = "grafana"
      port        = 3000
      target_port = 3000
    }
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
    }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
    }
    port {
      name        = "prometheus"
      port        = 9090
      target_port = 9090
    }
  }
}

resource "kubernetes_service_v1" "otel_nodeport" {
  count = var.enable_observability ? 1 : 0

  metadata {
    name      = "otel-lgtm-external"
    namespace = kubernetes_namespace_v1.satp.metadata[0].name
  }

  spec {
    type = "NodePort"
    selector = {
      app = "otel-lgtm"
    }

    port {
      name        = "grafana"
      port        = 3000
      target_port = 3000
      node_port   = 30030
    }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
      node_port   = 30031
    }
  }
}

# ---------------------------------------------------------------------------
# Load the locally built gateway image into the kind nodes so the
# Deployments can use image_pull_policy IfNotPresent without a registry.
# ---------------------------------------------------------------------------

resource "null_resource" "load_gateway_image" {
  count = var.load_gateway_image ? 1 : 0

  triggers = {
    cluster_name  = kind_cluster.satp.name
    gateway_image = var.gateway_image
  }

  provisioner "local-exec" {
    command = "kind load docker-image ${var.gateway_image} --name ${kind_cluster.satp.name}"
  }

  depends_on = [kind_cluster.satp]
}
