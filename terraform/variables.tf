variable "project" {
  type    = string
  default = "devsecops"
}

variable "environment" {
  type    = string
  default = "staging"
}

variable "region" {
  type        = string
  description = "AWS region to deploy into."
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "admin_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the public EKS API endpoint (e.g. your IP as x.x.x.x/32)."

  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must be non-empty and must not contain 0.0.0.0/0."
  }
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "github_repository" {
  type        = string
  description = "owner/repo allowed to assume the CI role via GitHub OIDC."
  default     = "DemiDemonDeveloper/devsecops-pipeline"
}

variable "create_github_oidc_provider" {
  type        = bool
  description = "Set false if the account already has the token.actions.githubusercontent.com provider."
  default     = true
}
