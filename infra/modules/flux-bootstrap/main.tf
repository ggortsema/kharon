data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

resource "tls_private_key" "flux" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}

provider "flux" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }

  git = {
    url    = "ssh://git@github.com/${var.github_owner}/${var.github_repository}.git"
    branch = var.github_branch
    ssh = {
      username    = "git"
      private_key = tls_private_key.flux.private_key_pem
    }
  }
}

resource "github_repository_deploy_key" "flux" {
  title      = var.deploy_key_title
  repository = var.github_repository
  key        = tls_private_key.flux.public_key_openssh
  read_only  = false
}

resource "flux_bootstrap_git" "this" {
  depends_on = [github_repository_deploy_key.flux]

  embedded_manifests = true
  components_extra   = ["image-reflector-controller", "image-automation-controller"]
  path               = var.flux_path

  # Keep Git history intact if this Terraform resource is ever destroyed.
  delete_git_manifests = false
}
