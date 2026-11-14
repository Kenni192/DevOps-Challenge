output "app_url" { value = "http://${module.alb.dns_name}" }
output "ecr_repository_url" { value = module.ecr.repository_url }
output "ecs_cluster" { value = module.ecs.cluster_name }
output "ecs_service" { value = module.ecs.service_name }
output "log_group" { value = module.ecs.log_group_name }
output "dashboard" { value = module.monitoring.dashboard_name }
output "asg_name" { value = module.ecs.asg_name }
