locals {
  environment = var.environment
  aws_region  = "eu-west-1"
}

resource "random_password" "random" {
  length = 28
}

// sg

module "runners" {
  source = "../../"

  aws_region = local.aws_region
  vpc_id     = var.github_vpc_id
  subnet_ids = var.github_subnet_ids

  environment = local.environment
  tags = {
    Project = "ProjectX"
  }

  github_app = {
    key_base64     = var.github_app_key_base64
    id             = var.github_app_id
    client_id      = var.github_app_client_id
    client_secret  = var.github_app_client_secret
    webhook_secret = random_password.random.result
  }

  webhook_lambda_zip                = "lambdas-download/webhook.zip"
  runner_binaries_syncer_lambda_zip = "lambdas-download/runner-binaries-syncer.zip"
  runners_lambda_zip                = "lambdas-download/runners.zip"

  enable_organization_runners = false
  runner_extra_labels         = var.github_runner_labels

  # enable access to the runners via SSM
  enable_ssm_on_runners = true

  userdata_template = "./templates/user-data.sh"
  ami_owners        = ["099720109477"] # Canonical's Amazon account ID

  ami_filter = {
    name = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-arm64-server-*"]
  }

  block_device_mappings = {
    # Set the block device name for Ubuntu root device
    device_name = "/dev/sda1"
  }

  # Uncommet idle config to have idle runners from 9 to 5 in time zone Amsterdam
  # idle_config = [{
  #   cron      = "* * 9-17 * * *"
  #   timeZone  = "Europe/Amsterdam"
  #   idleCount = 1
  # }]

  # disable KMS and encryption
  # encrypt_secrets = false

  role_permissions_boundary = var.role_permissions_boundary
  key_name = aws_key_pair.runner_key.key_name
  instance_type = var.github_runner_instance_type

  runner_additional_security_group_ids = [ aws_security_group.allow_ssm.id ]
}

resource "aws_key_pair" "runner_key" {
  key_name = "${var.environment}-github-runner-key"
  public_key = var.github_runner_key
}

resource "aws_security_group" "allow_ssm" {
  name        = "github-allow-ssm"
  description = "Allow ssm outbound traffic"
  vpc_id      = var.github_vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-github-allow-ssm"
    region = local.aws_region
    ssm = var.github_ssm_vpce_id
  }

# the provision (when = destroy) only accept variable from self, so inject the variable into tags map, then use it.
  provisioner "local-exec" {
    when = destroy
    command ="aws ec2 modify-vpc-endpoint --vpc-endpoint-id ${self.tags["ssm"]}  --remove-security-group-ids ${self.id} --region ${self.tags["region"]}"
  }
}

resource "null_resource" "create-endpoint" {
  provisioner "local-exec" {
    command = "aws ec2 modify-vpc-endpoint --vpc-endpoint-id ${var.github_ssm_vpce_id} --add-security-group-ids ${aws_security_group.allow_ssm.id} --region eu-west-1"
  }

  triggers = {
    sg = aws_security_group.allow_ssm.id
    vpce = var.github_ssm_vpce_id
  }
}
