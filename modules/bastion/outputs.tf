output "public_ip" {
  value = aws_eip.bastion_eip.public_ip
}

output "elastic_ip_id" {
  value = aws_eip.bastion_eip.id
}

output "security_group_id" {
  value = aws_security_group.bastion.id
}

