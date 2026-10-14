# Lets GitHub Actions in one repo assume a narrowly scoped AWS role with
# short-lived OIDC tokens, so no long-lived AWS keys are stored in GitHub.
variable "name" { type = string }
variable "repository" { type = string }
variable "create_provider" { type = bool }
variable "artifacts_bucket_arn" { type = string }
variable "kms_key_arn" { type = string }
variable "eks_cluster_arn" { type = string }

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  oidc_url          = "token.actions.githubusercontent.com"
  oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_url}"
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_provider ? 1 : 0
  url            = "https://${local.oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only workflows on main in this exact repository.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["repo:${var.repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
  depends_on           = [aws_iam_openid_connect_provider.github]
}

data "aws_iam_policy_document" "permissions" {
  statement {
    sid       = "UploadEvidence"
    actions   = ["s3:PutObject"]
    resources = ["${var.artifacts_bucket_arn}/ci/*"]
  }
  statement {
    sid       = "EncryptEvidence"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
  statement {
    sid       = "DescribeCluster"
    actions   = ["eks:DescribeCluster"]
    resources = [var.eks_cluster_arn]
  }
}

resource "aws_iam_role_policy" "this" {
  name   = "ci-least-privilege"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

output "role_arn" { value = aws_iam_role.this.arn }
