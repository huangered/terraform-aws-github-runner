variable "environment" {
  default = ""
}

variable "github_app_key_base64" {
  default = ""
}

variable "github_app_id" {
  default = ""
}

variable "github_app_client_id" {
  default = ""
}

variable "github_app_client_secret" {
  default = ""
}

variable "github_vpc_id" {
  default = ""
}

variable "github_subnet_ids" {
  default = []
}

variable "github_ssm_vpce_id" {
  default = ""
}

variable "github_runner_labels" {
  default = []
}

variable "github_runner_instance_type" {
  default = "c6g.4xlarge"
}

variable "role_permissions_boundary" {
  default = "arn:aws:iam::174781959807:policy/ProjAdminsPermBoundary"
}

variable "github_runner_key" {
  default = ""
}