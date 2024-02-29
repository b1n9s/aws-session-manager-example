terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.20"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      "source" : "aws-session-manager-example"
    }
  }
}

variable "region" {
  type        = string
  description = "Region for the resource deployment"
  default     = "us-west-2"
}

variable "create_vpc" {
  type        = bool
  description = "Determine if create the VPC"
  default     = true
}

variable "vpc_cidr" {
  type        = string
  description = "The CIDR block for the VPC"
  default     = "192.168.100.0/24"
}

variable "subnet_cidr" {
  type        = string
  description = "The CIDR of the private subnet"
  default     = null
}

data "aws_vpc" "this" {
  count = var.create_vpc ? 0 : 1

  cidr_block = var.vpc_cidr
}

data "aws_subnet" "private" {
  count = var.create_vpc ? 0 : 1

  vpc_id     = data.aws_vpc.this[0].id
  cidr_block = var.subnet_cidr
}

resource "aws_vpc" "this" {
  count = var.create_vpc ? 1 : 0

  cidr_block = var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "private" {
  count = var.create_vpc ? 1 : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = coalesce(var.subnet_cidr, var.vpc_cidr)
  availability_zone = "${var.region}a"
}

locals {
  vpc_id    = var.create_vpc ? aws_vpc.this[0].id : data.aws_vpc.this[0].id
  subnet_id = var.create_vpc ? aws_subnet.private[0].id : data.aws_subnet.private[0].id
}
resource "aws_route_table" "private" {
  count = var.create_vpc ? 1 : 0

  vpc_id = local.vpc_id
}

resource "aws_route_table_association" "private" {
  count = var.create_vpc ? 1 : 0

  subnet_id      = local.subnet_id
  route_table_id = aws_route_table.private[0].id
}

resource "aws_security_group" "endpoints" {
  name_prefix = "vpc-endpoint-sg"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}

resource "aws_vpc_endpoint" "endpoints" {
  for_each = toset(["ec2messages", "ssm", "ssmmessages"])

  vpc_id              = local.vpc_id
  vpc_endpoint_type   = "Interface"
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.endpoints.id]
  subnet_ids          = [local.subnet_id]
}

resource "aws_security_group" "instance" {
  name_prefix = "instance-sg"
  vpc_id      = local.vpc_id
  description = "security group for the EC2 instance"

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS outbound traffic"
  }
}

resource "aws_iam_role" "ec2" {
  name = "EC2_SSM_Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "SSM"

  role = aws_iam_role.ec2.name
}

data "aws_ami" "al2023" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

resource "aws_instance" "bastion" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t2.micro"
  subnet_id     = local.subnet_id
  vpc_security_group_ids = [
    aws_security_group.instance.id,
  ]
  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  metadata_options {
    http_tokens = "required"
  }
}

output "instance_id" {
  description = "The instance ID of the instance created"
  value       = aws_instance.bastion.id
}