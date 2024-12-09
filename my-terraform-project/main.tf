provider "aws" {
  region = "us-east-1" # Remplacez par votre région préférée
}
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
      
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.0"
    }
    
  }
}
# Define required providers
terraform {
  

  backend "s3" {
    bucket         = "custom-terraform-state-bucket-123456-06e3f585"  # Remplacez par le nom unique de votre bucket S3
    key            = "aws-backend/backend/terraform.tfstate"                 # Emplacement du fichier d'état dans le bucket
    region         = "us-east-1"                                     # Région AWS
    dynamodb_table = "custom-terraform-state-locks-123456"           # Remplacez par le nom de votre table DynamoDB
    encrypt        = true                                            # Active le chiffrement pour le fichier d'état
  }
}

# Configuration VPC
resource "aws_vpc" "tp_cloud_devops_vpc" {
  cidr_block           = var.vpc_cidr_block # Utilisation d'une variable pour le CIDR VPC
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "tp_cloud_devops_vpc"
  }
}

# Sous-réseau public 1
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.tp_cloud_devops_vpc.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = var.availability_zone_1
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet1"
  }
}

# Sous-réseau public 2
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.tp_cloud_devops_vpc.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = var.availability_zone_2
  map_public_ip_on_launch = true
  tags = {
    Name = "PublicSubnet2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main_gateway" {
  vpc_id = aws_vpc.tp_cloud_devops_vpc.id
  tags = {
    Name = "MainInternetGateway"
  }
}

# Table de routage pour les sous-réseaux publics
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.tp_cloud_devops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_gateway.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

# Association de la table de routage au sous-réseau public 1
resource "aws_route_table_association" "public_rta1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

# Association de la table de routage au sous-réseau public 2
resource "aws_route_table_association" "public_rta2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}

# Génération d'une clé SSH privée
resource "tls_private_key" "example_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Création d'une paire de clés AWS avec la clé publique générée
resource "aws_key_pair" "deployer_key" {
  key_name   = var.ssh_key_name
  public_key = tls_private_key.example_ssh_key.public_key_openssh
}

# Stockage de la clé privée SSH dans un bucket S3 sécurisé
resource "aws_s3_bucket_object" "private_key_object" {
  bucket                  = "custom-terraform-state-bucket-123456-06e3f585"  # Nom du bucket S3 où la clé sera stockée
  key                     = "${var.ssh_key_name}.pem"  # Nom de la clé avec l'extension .pem
  content                 = tls_private_key.example_ssh_key.private_key_pem  # Contenu de la clé privée générée
  acl                     = "private"  # Contrôle d'accès, ici la clé est privée
  server_side_encryption  = "AES256"  # Chiffrement côté serveur, ici utilisant AES256 pour sécuriser la clé
}


# Création d'un groupe de sécurité pour le serveur web et l'accès SSH
resource "aws_security_group" "web_sg" {
  name        = "web-server-sg"
  vpc_id      = aws_vpc.tp_cloud_devops_vpc.id
  description = "Security group for web server and SSH access"
}

# Autoriser le trafic HTTP entrant sur le port 8080
resource "aws_security_group_rule" "allow_web_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Autoriser le trafic HTTP entrant sur le port 80
resource "aws_security_group_rule" "allow_web_http_inbound_80" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Autoriser le trafic SSH entrant sur le port 22
resource "aws_security_group_rule" "allow_web_ssh_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Autoriser tout le trafic sortant
resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1" # "-1" signifie tous les protocoles
  cidr_blocks       = ["0.0.0.0/0"]
}

# IAM Role for EC2 to access ECR
resource "aws_iam_role" "ec2_ecr_access_role" {
  name = "ec2-ecr-access-role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  })
}

# Attach AWS managed policy for ECR access
resource "aws_iam_role_policy_attachment" "ec2_ecr_policy_attachment" {
  role       = aws_iam_role.ec2_ecr_access_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2-ecr-instance-profile"
  role = aws_iam_role.ec2_ecr_access_role.name
}

# Modify your EC2 instance to include the IAM instance profile
resource "aws_instance" "public_instance" {
  ami                    = var.ec2_ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet_1.id
  key_name               = aws_key_pair.deployer_key.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_instance_profile.name

  user_data = <<-EOF
    #!/bin/bash
    echo "<h1>Hello, World</h1>" > index.html
    # Start a simple HTTP server on port 8080
    python3 -m http.server 8080 &
  EOF

  tags = {
    Name = "PublicInstance"
  }
}
# Create a DB subnet group
resource "aws_db_subnet_group" "mydb_subnet_group" {
  name       = "mydb_subnet_group"
  subnet_ids = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  tags = {
    Name = "mydb_subnet_group"
  }
}

# Create an RDS MySQL database instance
resource "aws_db_instance" "mydb" {
  allocated_storage    = 20  # Minimum storage size for MySQL
  engine               = "mysql"
  engine_version      = "8.0.35"  # Specify the MySQL engine version
  instance_class      = "db.t3.micro"  # Free-tier eligible instance type
  identifier          = "mydb"
  username            = "dbuser"  # Master username
  password            = "DBpassword2024"  # Master password
  db_subnet_group_name = aws_db_subnet_group.mydb_subnet_group.name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  publicly_accessible = true  # Restrict public access
  multi_az            = false  # Single-AZ deployment
  skip_final_snapshot = true  # Skip snapshot on deletion
  tags = {
    Name = "enis_tp"
  }
}
# Allow inbound RDS traffic (e.g., MySQL on port 3306)
resource "aws_security_group_rule" "allow_rds_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  # For production, replace this with a specific IP or CIDR block
}

# Allow inbound to backend on port 8000
resource "aws_security_group_rule" "allow_backend_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 8000
  to_port           = 8000
  protocol          = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
  # For production, replace this with a specific IP or CIDR block
}

# Allow inbound HTTP traffic on port 81 to access the final application
resource "aws_security_group_rule" "allow_web_http_inbound_81" {
  type              = "ingress"
  security_group_id = aws_security_group.web_sg.id
  from_port         = 81
  to_port           = 81
  protocol          = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
}

