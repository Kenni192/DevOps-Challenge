variable "name" { type = string }
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "alb_security_group_id" { type = string }
variable "target_group_arn" { type = string }
variable "image" {
  type        = string
  description = "Full image URI including tag"
}
variable "container_port" { type = number }
variable "container_cpu" {
  type    = number
  default = 256
}
variable "container_memory" {
  type        = number
  default     = 256
  description = "Hard memory limit (MiB) per task"
}
variable "instance_type" {
  type    = string
  default = "t3.small"
}
variable "asg_min" {
  type    = number
  default = 2
}
variable "asg_max" {
  type    = number
  default = 4
}
variable "desired_count" {
  type    = number
  default = 2
}
variable "min_tasks" {
  type    = number
  default = 2
}
variable "max_tasks" {
  type    = number
  default = 6
}
variable "cpu_target_percent" {
  type    = number
  default = 60
}
variable "log_retention_days" {
  type    = number
  default = 30
}
variable "environment_variables" {
  type    = map(string)
  default = {}
}
variable "tags" {
  type    = map(string)
  default = {}
}
