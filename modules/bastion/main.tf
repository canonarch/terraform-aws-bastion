terraform {
  required_version = ">= 0.12"
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN AUTO SCALING GROUP (ASG) TO RUN THE BASTION
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_autoscaling_group" "bastion_asg" {
  # zero-downtime deployment support
  # explicitly depend on the launch configuration's name so each time it's replaced,
  # this ASG is also replaced
  # inspired from https://github.com/brikis98/terraform-up-and-running-code/blob/master/code/terraform/05-tips-and-tricks/zero-downtime-deployment/modules/services/webserver-cluster/main.tf
  name                      = aws_launch_configuration.bastion_launch_config.name
  launch_configuration      = aws_launch_configuration.bastion_launch_config.name
  max_size                  = 1
  min_size                  = 1
  desired_capacity          = 1
  health_check_type         = "EC2"
  health_check_grace_period = var.health_check_grace_period
  vpc_zone_identifier       = var.subnet_ids

  # zero-downtime deployment support
  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE LAUNCH CONFIGURATION TO DEFINE WHAT RUNS ON EACH INSTANCE IN THE ASG
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_launch_configuration" "bastion_launch_config" {
  name_prefix          = "${var.name}-"
  image_id             = var.ami_id
  instance_type        = var.instance_type
  iam_instance_profile = aws_iam_instance_profile.bastion_instance_profile.name

  # The bastion user_data script need access to the AWS EC2 service to associate the Elastic IP to the bastion instance.
  # The access is possible if the bastion has initially (before the association) a public IP (associate_public_ip_address = true)
  # _or_ if the bastion can access to an EC2 VPC Interface Endpoint (this is what is done via vpc-mgmt module).
  # In the last case, the bastion will have a public IP after the association.
  # So anyway, associate_public_ip_address can be always be true for a public bastion (does it make sense to have a private bastion !?)
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  security_groups             = [aws_security_group.bastion.id]
  enable_monitoring           = true

  user_data = var.user_data

  root_block_device {
    volume_type = "standard"
    volume_size = "20"
  }

  # Important note: whenever using a launch configuration with an auto scaling group, you must set
  # create_before_destroy = true. However, as soon as you set create_before_destroy = true in one resource, you must
  # also set it in every resource that it depends on, or you'll get an error about cyclic dependencies (especially when
  # removing resources). For more info, see:
  #
  # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html
  # https://terraform.io/docs/configuration/resources.html
  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A SECURITY GROUP
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "bastion" {
  name_prefix = "${var.name}-"
  description = "Security Group for ${var.name}"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.bastion.id

  type      = "egress"
  from_port = 0
  to_port   = 0
  protocol  = "-1"

  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_ssh_cidr_blocks" {
  count = length(var.allowed_ssh_cidr_blocks) >= 1 ? 1 : 0

  security_group_id = aws_security_group.bastion.id

  type      = "ingress"
  from_port = "22"
  to_port   = "22"
  protocol  = "tcp"

  cidr_blocks = var.allowed_ssh_cidr_blocks
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATES A ROLE THAT IS ATTACHED TO THE INSTANCE
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_instance_profile" "bastion_instance_profile" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.bastion_iam_role.name

  # aws_launch_configuration.bastion_launch_config in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "bastion_iam_role" {
  name = "${var.name}_iam_role"

  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "bastion_policy" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.bastion_iam_role.id

  policy = data.aws_iam_policy_document.bastion_policy_document.json

  # aws_launch_configuration.bastion_launch_config in this module sets create_before_destroy to true, which means
  # everything it depends on, including this resource, must set it as well, or you'll get cyclic dependency errors
  # when you try to do a terraform destroy.
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_iam_policy_document" "bastion_policy_document" {
  statement {
    sid    = "AssociateAddress"
    effect = "Allow"
    actions = [
      "ec2:AssociateAddress",
    ]

    # AWS don't support resource-level permissions for action AssociateAddress (as of July, 2019).
    # cf https://docs.aws.amazon.com/AWSEC2/latest/APIReference/ec2-api-permissions.html#ec2-api-unsupported-resource-permissions
    resources = ["*"]
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE AN ELASTIC IP ADDRESS (EIP)
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_eip" "bastion_eip" {
  vpc = true
}

