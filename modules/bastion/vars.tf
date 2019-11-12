variable "region" {
}

variable "vpc_id" {
}

variable "name" {
}

variable "subnet_ids" {
  type = list(string)
}

variable "ami_id" {
}

variable "instance_type" {
}

variable "key_pair_name" {
}

variable "user_data" {
}

variable "allowed_ssh_cidr_blocks" {
  type = list(string)
}

variable "health_check_grace_period" {
  default     = "30"
}

