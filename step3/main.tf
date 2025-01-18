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

# --- ECS Cluster ---
resource "aws_ecs_cluster" "wordpress_cluster" {
  name = "wordpress-cluster"
}

# --- Security Group ---
resource "aws_security_group" "ecs_sg" {
  name_prefix = "ecs-wordpress-"
  vpc_id      = "vpc-0fffceeee860b6127" # use your VPC

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
  subnets            = ["subnet-0a3f921cb7f2b2727", "subnet-0a03c35dcc9db51cc"] #use public subnet
}

# --- Target Group ---
resource "aws_lb_target_group" "wordpress_tg" {
  name        = "wordpress-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "vpc-0fffceeee860b6127" # use your VPC
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

  container_definitions = jsonencode([
    {
      name      = "wordpress"
      image     = "571600859313.dkr.ecr.eu-central-1.amazonaws.com/wordpress-repo:custom" # use your docker image form ECR
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "WORDPRESS_DB_HOST"
          value = "slengpack-db-instance.cf4amqa86ky4.eu-central-1.rds.amazonaws.com" # use your endpoint
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
    subnets         = ["subnet-0b8870f65ff334f31", "subnet-0df8f70cc8cc79f7c"] #use private subnet
    security_groups = [aws_security_group.ecs_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
    container_name   = "wordpress"
    container_port   = 80
  }
}
