data "aws_iam_policy_document" "alb_controller_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = var.alb_controller_role_name
  assume_role_policy = data.aws_iam_policy_document.alb_controller_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "alb_controller_admin" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_iam_policy_document" "external_dns_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = var.external_dns_role_name
  assume_role_policy = data.aws_iam_policy_document.external_dns_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "external_dns_route53" {
  role       = aws_iam_role.external_dns.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
}

data "aws_iam_policy_document" "flux_image_reflector_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:flux-system:image-reflector-controller"]
    }
  }
}

resource "aws_iam_role" "flux_image_reflector" {
  name               = var.flux_image_reflector_role_name
  assume_role_policy = data.aws_iam_policy_document.flux_image_reflector_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "flux_image_reflector_ecr_readonly" {
  role       = aws_iam_role.flux_image_reflector.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
