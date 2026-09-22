# ECS Task Execution Role (used by Fargate/ECS agent to pull images and push logs)
resource "aws_iam_role" "ecs_execution_role" {
  name = "${local.rendered_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_execution_custom" {
  for_each = {
    for index, policy_arn in var.custom_ecs_execution_policies :
    tostring(index) => policy_arn
  }

  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = each.value
}

# ECS Task Job Role (used by container code itself to query S3, DynamoDB, SSM, etc.)
resource "aws_iam_role" "ecs_job_role" {
  name = "${local.rendered_name}-ecs-job-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

# Attach custom policies to the ECS Job Role
resource "aws_iam_role_policy_attachment" "ecs_job_custom" {
  for_each = {
    for index, policy_arn in var.custom_ecs_job_role_policies :
    tostring(index) => policy_arn
  }

  role       = aws_iam_role.ecs_job_role.name
  policy_arn = each.value
}
