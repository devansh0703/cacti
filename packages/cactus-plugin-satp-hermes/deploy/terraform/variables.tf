# Copyright 2026 Hyperledger Cacti Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Input variables for the SATP Hermes local Kubernetes deployment
# (hyperledger-cacti/cacti#4706).

variable "cluster_name" {
  description = "Name of the kind cluster to create."
  type        = string
  default     = "satp-hermes"
}

variable "namespace" {
  description = "Kubernetes namespace holding all SATP workloads."
  type        = string
  default     = "satp-hermes"
}

variable "gateway_image" {
  description = "Container image for the SATP Hermes gateway. Build it with `docker build -f satp-hermes-gateway.Dockerfile -t <this value> .` from the package root, then keep load_gateway_image true so the image is pushed into the kind nodes."
  type        = string
  default     = "satp-hermes-gateway:local"
}

variable "load_gateway_image" {
  description = "Whether to run `kind load docker-image` for var.gateway_image after the cluster is created. Disable when the image already lives in a registry reachable from the cluster."
  type        = bool
  default     = true
}

variable "gateway_replicas" {
  description = "Replicas per gateway Deployment. Horizontal scalability knob for the n-gateway topology."
  type        = number
  default     = 1
}

variable "enable_observability" {
  description = "Whether to deploy the Grafana OpenTelemetry LGTM backend (mirrors docker-compose-satp.yml)."
  type        = bool
  default     = true
}

variable "otel_image" {
  description = "Container image for the OpenTelemetry backend."
  type        = string
  default     = "grafana/otel-lgtm:latest"
}

variable "ledger_rpc_url_1" {
  description = "Ethereum JSON-RPC endpoint reachable from gateway-1 pods (gateway-1 bridgeConfig connectorOptions.rpcApiHttpHost)."
  type        = string
  default     = "http://host.docker.internal:8545"
}

variable "ledger_rpc_url_2" {
  description = "Ethereum JSON-RPC endpoint reachable from gateway-2 pods (gateway-2 bridgeConfig connectorOptions.rpcApiHttpHost)."
  type        = string
  default     = "http://host.docker.internal:8546"
}

variable "host_port_offset" {
  description = "Host port base for the kind extraPortMappings. Gateway-1 API/NodePorts are exposed at host_port_offset + {0,1,2}; gateway-2 at host_port_offset + {10,11,12}."
  type        = number
  default     = 30100
}
