data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  name       = "${var.project}-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

# One customer-managed key for EKS secrets, EBS, CloudWatch Logs and S3.
resource "aws_kms_key" "main" {
  description             = "${local.name} encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}

data "aws_iam_policy_document" "kms" {
  # In a key policy, Resource "*" means "this key"; access is scoped by principal.
  #checkov:skip=CKV_AWS_111:Key policy resource "*" refers only to this key
  #checkov:skip=CKV_AWS_356:Key policy resource "*" refers only to this key
  #checkov:skip=CKV_AWS_109:Key policy resource "*" refers only to this key
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:*"]
    }
  }

  # Lets the EC2 Auto Scaling service-linked role use the key for encrypted node volumes.
  statement {
    sid = "AutoScalingEBS"
    actions = [
      "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
  }
}

module "network" {
  source      = "./modules/network"
  name        = local.name
  cidr        = var.vpc_cidr
  kms_key_arn = aws_kms_key.main.arn
}

module "eks" {
  source              = "./modules/eks"
  name                = local.name
  kubernetes_version  = var.kubernetes_version
  subnet_ids          = module.network.private_subnet_ids
  public_access_cidrs = var.admin_cidrs
  kms_key_arn         = aws_kms_key.main.arn
  instance_types      = var.node_instance_types
  desired_size        = var.node_desired_size
}

# Receives S3 server access logs for the artifacts bucket.
module "access_logs_bucket" {
  source        = "./modules/secure-bucket"
  name          = "${local.name}-access-logs-${local.account_id}"
  is_log_bucket = true
}

# Stores pipeline evidence: SBOMs, scan reports, ZAP results.
module "artifacts_bucket" {
  source      = "./modules/secure-bucket"
  name        = "${local.name}-artifacts-${local.account_id}"
  kms_key_arn = aws_kms_key.main.arn
  log_bucket  = module.access_logs_bucket.id
}

module "github_oidc" {
  count                = var.enable_github_oidc ? 1 : 0
  source               = "./modules/github-oidc"
  name                 = "${local.name}-github-ci"
  repository           = var.github_repository
  create_provider      = var.create_github_oidc_provider
  artifacts_bucket_arn = module.artifacts_bucket.arn
  kms_key_arn          = aws_kms_key.main.arn
  eks_cluster_arn      = module.eks.cluster_arn
}
