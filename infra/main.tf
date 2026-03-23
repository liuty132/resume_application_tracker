terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "apptracker-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "apptracker-vpc"
  }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "apptracker-private-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "apptracker-private-2"
  }
}

# Security Groups
resource "aws_security_group" "lambda" {
  name        = "apptracker-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "apptracker-lambda-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "apptracker-rds-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "apptracker-rds-sg"
  }
}

# RDS Database
resource "aws_db_subnet_group" "main" {
  name       = "apptracker-db-subnet-group"
  subnet_ids = [aws_subnet.private_1.id, aws_subnet.private_2.id]

  tags = {
    Name = "apptracker-db-subnet-group"
  }
}

resource "aws_rds_cluster" "main" {
  cluster_identifier      = "apptracker-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = "16.1"
  database_name           = var.db_name
  master_username         = var.db_user
  master_password         = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  storage_encrypted       = true
  skip_final_snapshot     = false
  final_snapshot_identifier = "apptracker-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  backup_retention_period = 7

  tags = {
    Name = "apptracker-cluster"
  }
}

resource "aws_rds_cluster_instance" "main" {
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = "db.t4g.micro"
  engine              = aws_rds_cluster.main.engine
  engine_version      = aws_rds_cluster.main.engine_version
  publicly_accessible = false

  tags = {
    Name = "apptracker-instance"
  }
}

# S3 Bucket for HTML snapshots
resource "aws_s3_bucket" "snapshots" {
  bucket = "apptracker-html-snapshots-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "apptracker-snapshots"
  }
}

resource "aws_s3_bucket_versioning" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "snapshots" {
  bucket = aws_s3_bucket.snapshots.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 180
    }
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name = "apptracker-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "lambda-s3-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.snapshots.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_ssm" {
  name = "lambda-ssm-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/apptracker/*"
      }
    ]
  })
}

# SSM Parameters for secrets
resource "aws_ssm_parameter" "db_host" {
  name  = "/apptracker/db_host"
  type  = "SecureString"
  value = aws_rds_cluster.main.endpoint
}

resource "aws_ssm_parameter" "db_port" {
  name  = "/apptracker/db_port"
  type  = "SecureString"
  value = "5432"
}

resource "aws_ssm_parameter" "db_name" {
  name  = "/apptracker/db_name"
  type  = "SecureString"
  value = var.db_name
}

resource "aws_ssm_parameter" "db_user" {
  name  = "/apptracker/db_user"
  type  = "SecureString"
  value = var.db_user
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/apptracker/db_password"
  type  = "SecureString"
  value = var.db_password
}

resource "aws_ssm_parameter" "s3_bucket" {
  name  = "/apptracker/s3_bucket"
  type  = "SecureString"
  value = aws_s3_bucket.snapshots.id
}

resource "aws_ssm_parameter" "lambda_sg" {
  name  = "/apptracker/lambda_sg"
  type  = "SecureString"
  value = aws_security_group.lambda.id
}

resource "aws_ssm_parameter" "lambda_subnet_1" {
  name  = "/apptracker/lambda_subnet_1"
  type  = "SecureString"
  value = aws_subnet.private_1.id
}

resource "aws_ssm_parameter" "lambda_subnet_2" {
  name  = "/apptracker/lambda_subnet_2"
  type  = "SecureString"
  value = aws_subnet.private_2.id
}

data "aws_caller_identity" "current" {}
