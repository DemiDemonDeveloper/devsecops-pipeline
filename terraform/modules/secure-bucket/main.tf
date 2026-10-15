variable "name" { type = string }

variable "kms_key_arn" {
  type        = string
  default     = null
  description = "SSE-KMS key. Required unless is_log_bucket is true."
}

variable "log_bucket" {
  type    = string
  default = null
}

variable "is_log_bucket" {
  type        = bool
  default     = false
  description = "S3 server access log delivery only supports SSE-S3 targets, so log buckets use AES256."
}

resource "aws_s3_bucket" "this" {
  bucket = var.name
  #checkov:skip=CKV_AWS_145:S3 access-log delivery requires SSE-S3, so log buckets use AES256; data buckets use SSE-KMS
  #checkov:skip=CKV_AWS_144:Cross-region replication not required for staging evidence
  #checkov:skip=CKV2_AWS_62:No downstream consumers of object events yet
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced" # disables ACLs entirely
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.is_log_bucket ? "AES256" : "aws:kms"
      kms_master_key_id = var.is_log_bucket ? null : var.kms_key_arn
    }
    bucket_key_enabled = !var.is_log_bucket
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    id     = "expire-noncurrent-and-abort-mpu"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_logging" "this" {
  count         = var.log_bucket == null ? 0 : 1
  bucket        = aws_s3_bucket.this.id
  target_bucket = var.log_bucket
  target_prefix = "${var.name}/"
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = var.is_log_bucket ? [1] : []
    content {
      sid       = "S3ServerAccessLogDelivery"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]
      principals {
        type        = "Service"
        identifiers = ["logging.s3.amazonaws.com"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket     = aws_s3_bucket.this.id
  policy     = data.aws_iam_policy_document.this.json
  depends_on = [aws_s3_bucket_public_access_block.this]
}

output "id" { value = aws_s3_bucket.this.id }
output "arn" { value = aws_s3_bucket.this.arn }
