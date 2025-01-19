terraform {
  backend "s3"{
  bucket = "github-actions-slengpack"
  key = "terrraformECR.tfstate"
  region = "eu-central-1"
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

variable "ecr_image_uri" {
  type        = string
  default     = "ecr_image_uri"
  description = "ecr_image_uri"
}

variable "vpc_id" {
  type        = string
  default     = "vpc_id"
  description = "vpc_id"
}

variable "public_subnet_id_1" {
  type        = string
  default     = "public_subnet_id_1"
  description = "public_subnet_id_1"
}

variable "public_subnet_id_2" {
  type        = string
  default     = "public_subnet_id_2"
  description = "public_subnet_id_2"
}

variable "private_subnet_id_1" {
  type        = string
  default     = "private_subnet_id_1"
  description = "private_subnet_id_1"
}

variable "private_subnet_id_2" {
  type        = string
  default     = "private_subnet_id_2"
  description = "private_subnet_id_2"
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "wordpress_cluster" {
  name = "wordpress-cluster"
}

# --- IAM Policy Attachments ---
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_secrets_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_container_service_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

resource "aws_iam_role_policy_attachment" "ecs_ssm_full_access" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

resource "aws_iam_role_policy_attachment" "ecs_cloudwatch_full_access" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

# --- Security Group ---
resource "aws_security_group" "ecs_sg" {
  name_prefix = "ecs-wordpress-"
  vpc_id      = var.vpc_id # use your VPC

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- ALB ---
resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets            = [var.public_subnet_id_1, var.public_subnet_id_2] #use public subnet
}

# --- Target Group ---
resource "aws_lb_target_group" "wordpress_tg" {
  name        = "wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id # use your VPC
  target_type = "ip"
}

# --- Listener ---
resource "aws_lb_listener" "wordpress_listener" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

# --- Task Definition ---
resource "aws_ecs_task_definition" "wordpress" {
  family                   = "wordpress"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = var.ecr_image_uri # use your docker image form ECR
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

# --- ECS Service ---
resource "aws_ecs_service" "wordpress" {
  name            = "wordpress-service"
  cluster         = aws_ecs_cluster.wordpress_cluster.id
  task_definition = aws_ecs_task_definition.wordpress.arn
  desired_count   = 1

  launch_type = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets         = [var.private_subnet_id_1, var.private_subnet_id_2] #use private subnet
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
    container_name   = "wordpress"
    container_port   = 80
  }
}

output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}
