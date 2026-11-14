variable "name" { type = string }
variable "max_images" {
  type    = number
  default = 20
}
variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE" # every build is a unique commit-SHA tag
  force_delete         = true        # lets `terraform destroy` clean up the demo
  tags                 = var.tags

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.max_images} images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = var.max_images }
      action       = { type = "expire" }
    }]
  })
}

output "repository_url" { value = aws_ecr_repository.this.repository_url }
output "repository_name" { value = aws_ecr_repository.this.name }
