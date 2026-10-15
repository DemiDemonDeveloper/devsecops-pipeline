output "cluster_name" {
  value = module.eks.cluster_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "artifacts_bucket" {
  value = module.artifacts_bucket.id
}

output "github_ci_role_arn" {
  description = "Set as the AWS_ROLE_ARN repository variable for GitHub Actions."
  value       = one(module.github_oidc[*].role_arn)
}
