variable "name" {
  description = "ECR repository name"
  type        = string
}

variable "image_tag_mutability" {
  description = "Whether image tags can be overwritten"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "Enable image scanning when pushing"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to ECR resources"
  type        = map(string)
  default     = {}
}
