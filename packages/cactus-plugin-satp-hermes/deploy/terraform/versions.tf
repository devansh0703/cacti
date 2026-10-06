# Copyright 2026 Hyperledger Cacti Contributors
# SPDX-License-Identifier: Apache-2.0
#
# Provider and Terraform version requirements for the SATP Hermes
# local Kubernetes deployment (hyperledger-cacti/cacti#4706).

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # Provisions the local kind cluster itself.
    kind = {
      source  = "tehcyx/kind"
      version = ">= 0.9.0"
    }

    # Deploys all SATP workloads into the kind cluster.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30.0"
    }
  }
}

# The kind provider writes a kubeconfig for the ephemeral cluster. The
# kubernetes provider reads it back so a single `terraform apply` both
# creates the cluster and deploys the gateways into it.
provider "kind" {}

provider "kubernetes" {
  host                   = kind_cluster.satp.endpoint
  client_certificate     = kind_cluster.satp.client_certificate
  client_key             = kind_cluster.satp.client_key
  cluster_ca_certificate = kind_cluster.satp.cluster_ca_certificate
}
