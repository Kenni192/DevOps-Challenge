variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "project" {
  type    = string
  default = "devops-challenge"
}
variable "environment" {
  type    = string
  default = "prod"
}
variable "image_tag" {
  type        = string
  description = "Container image tag to deploy (set by CI to the git SHA)"
}
variable "alarm_email" {
  type    = string
  default = ""
}
variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
variable "container_port" {
  type    = number
  default = 8080
}
variable "instance_type" {
  type    = string
  default = "t3.small"
}
