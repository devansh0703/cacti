# Copyright 2026 Hyperledger Cacti Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Outputs for the SATP Hermes local Kubernetes deployment
# (hyperledger-cacti/cacti#4706).

output "cluster_name" {
  description = "Name of the provisioned kind cluster."
  value       = kind_cluster.satp.name
}

output "kubeconfig_path" {
  description = "Kubeconfig written by the kind provider for out-of-band kubectl access."
  value       = kind_cluster.satp.kubeconfig_path
}

output "namespace" {
  description = "Namespace holding all SATP workloads."
  value       = kubernetes_namespace_v1.satp.metadata[0].name
}

output "gateway_healthchecks" {
  description = "Host URLs for the gateway OpenAPI healthcheck endpoints. Expect {\"status\":\"AVAILABLE\"}."
  value = {
    for name in keys(local.gateways) :
    name => "http://localhost:${name == "gateway-1" ? var.host_port_offset + 2 : var.host_port_offset + 12}${local.healthcheck_path}"
  }
}

output "grafana_url" {
  description = "Grafana UI of the otel-lgtm backend (empty when observability is disabled)."
  value       = var.enable_observability ? "http://localhost:${var.host_port_offset + 100}" : ""
}
