# Copy to terraform.tfvars (git-ignored) and edit.
region      = "us-east-1"
admin_cidrs = ["203.0.113.10/32"] # your public IP: curl -s https://checkip.amazonaws.com

# node_instance_types = ["t3.medium"]
# node_desired_size   = 2
# create_github_oidc_provider = false  # if the account already has one
