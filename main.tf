data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

locals {
  name   = "db-example"
  region = "eu-west-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-vpc"
    GithubOrg  = "terraform-aws-modules"
  }
}

data "aws_ami" "amazon-linux-2" {
 most_recent = true


 filter {
   name   = "owner-alias"
   values = ["amazon"]
 }


 filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
 }
}

data "aws_iam_policy_document" "get-secret" {
  statement {
    sid = "AllowGetSecret"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      "arn:aws:secretsmanager:*:${data.aws_caller_identity.current.account_id}:secret:rds*",
    ]
  }
}

resource "aws_iam_policy" "get-secret" {
  name   = "example_policy"
  path   = "/"
  policy = data.aws_iam_policy_document.get-secret.json
}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = local.name
  cidr = local.vpc_cidr

  azs              = local.azs
  private_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  public_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 4)]
  database_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 8)]

  create_database_subnet_group = true


  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true



  tags = local.tags

}

resource "aws_security_group" "private_bastion_host" {
  name        = "private_bastion_host"
  description = "Security group to access the Database Instance"

  vpc_id = module.vpc.vpc_id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private_bastion_host"
  }
}


resource "aws_security_group" "instance_db_sg" {
  name        = "instance_db_sg"
  description = "Security group for the Databases"

  vpc_id = module.vpc.vpc_id

  // Only the EC2 instances should be able to communicate with RDS."
  // So we will create an
  // inbound rule that allows traffic from the EC2 security group
  // through TCP port 3306, which is the port that MySQL 
  // communicates through
  ingress {
    description     = "Allow MySQL traffic from only the web sg"
    from_port       = "3306"
    to_port         = "3306"
    protocol        = "tcp"
    security_groups = [aws_security_group.private_bastion_host.id]
  }

  tags = {
    Name = "instance_db_sg"
  }
}

resource "aws_iam_role" "dev-resources-iam-role" {
  name               = "dev-ssm-role"
  description        = "The role for the developer resources EC2"
  assume_role_policy = <<EOF
{
"Version": "2012-10-17",
"Statement": {
"Effect": "Allow",
"Principal": {"Service": "ec2.amazonaws.com"},
"Action": "sts:AssumeRole"
}
}
EOF
  tags = {
    stack = "test"
  }
}

resource "aws_iam_role_policy_attachment" "dev-resources-ssm-policy" {
  role       = aws_iam_role.dev-resources-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "dev-resources-secret-policy" {
  role       = aws_iam_role.dev-resources-iam-role.name
  policy_arn = aws_iam_policy.get-secret.arn
}

resource "aws_iam_instance_profile" "dev-resources-iam-profile" {
  name = "ec2_profile"
  role = aws_iam_role.dev-resources-iam-role.name
}

resource "aws_instance" "private_bastion_host" {
  ami                    = data.aws_ami.amazon-linux-2.id
  instance_type          = var.instance_type
  subnet_id              = module.vpc.private_subnets[1]
  vpc_security_group_ids = [aws_security_group.private_bastion_host.id]
  iam_instance_profile   = aws_iam_instance_profile.dev-resources-iam-profile.name

	user_data = <<EOF
    #! /bin/bash
    yum update -y
    yum install mysql jq -y
  EOF

  tags = {
    Name = "private_bastion_host"
  }
}

resource "aws_db_instance" "default" {
  allocated_storage    = 10
  identifier           = "the-db-test"
  db_name              = "mydb"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  username             = "richard"

  db_subnet_group_name   = module.vpc.database_subnet_group_name

  vpc_security_group_ids = [aws_security_group.instance_db_sg.id]
  manage_master_user_password = true
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true
}