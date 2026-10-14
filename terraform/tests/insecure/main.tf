# INTENTIONALLY INSECURE fixture. CI asserts Checkov and Trivy FAIL on this
# directory, proving the IaC gate actually blocks these misconfigurations.
# Never apply this.

resource "aws_s3_bucket" "public" {
  bucket = "insecure-fixture-public-bucket"
}

resource "aws_s3_bucket_public_access_block" "public" {
  bucket                  = aws_s3_bucket.public.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_iam_policy" "admin_everything" {
  name = "insecure-fixture-admin"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }]
  })
}

resource "aws_ebs_volume" "unencrypted" {
  availability_zone = "us-east-1a"
  size              = 10
  encrypted         = false
}

resource "aws_security_group" "ssh_world" {
  name = "insecure-fixture-ssh"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
