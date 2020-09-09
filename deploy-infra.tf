# ================VPC=================

resource "aws_vpc" "k8s-demo" {
  cidr_block = "10.0.0.0/16"

  tags = map(
    "Name", "k8s-demo-node",
    "kubernetes.io/cluster/${var.cluster-name}", "shared",
  )
}

resource "aws_internet_gateway" "k8s-demo" {
  vpc_id = aws_vpc.k8s-demo.id
}

#Public Subnet

resource "aws_subnet" "k8s-demo-public" {
    vpc_id = aws_vpc.k8s-demo.id
    cidr_block = "10.0.1.0/24"
	map_public_ip_on_launch = true
    availability_zone = "us-east-1a"
    tags = map (
        "Name", "Public Subnet"
    )
}

resource "aws_route_table" "k8s-demo-public" {
    vpc_id = aws_vpc.k8s-demo.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.k8s-demo.id
    }
    tags = map(
        "Name", "Public Subnet"
    )
}

resource "aws_route_table_association" "k8s-demo-public" {
    subnet_id = aws_subnet.k8s-demo-public.id
    route_table_id = aws_route_table.k8s-demo-public.id
}


#  Private Subnet

resource "aws_subnet" "k8s-demo-private" {
    vpc_id = aws_vpc.k8s-demo.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "us-east-1c"
    tags = map(
        "Name", "Private Subnet"
    )
}

resource "aws_eip" "nat" {
  vpc      = true
  depends_on = [aws_internet_gateway.k8s-demo]
}

resource "aws_nat_gateway" "k8s-demo" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.k8s-demo-public.id
  depends_on = [aws_internet_gateway.k8s-demo]
  tags = map(
    "Name", "k8s Demo VPC NAT"
  )
}

resource "aws_route_table" "k8s-demo-private" {
    vpc_id = aws_vpc.k8s-demo.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_nat_gateway.k8s-demo.id
    }
    tags = map(
        "Name", "Private Subnet"
    )
}

resource "aws_route_table_association" "k8s-demo-private" {
    subnet_id = aws_subnet.k8s-demo-private.id
    route_table_id = aws_route_table.k8s-demo-private.id
}

#============ EKS Node =========================

resource "aws_iam_role" "k8s-demo-node" {
  name = "k8s-demo-node"

  assume_role_policy = <<POLICY
{
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
}
POLICY
}

resource "aws_iam_role_policy_attachment" "k8s-demo-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.k8s-demo-node.name
}

resource "aws_iam_role_policy_attachment" "k8s-demo-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.k8s-demo-node.name
}

resource "aws_iam_role_policy_attachment" "k8s-demo-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.k8s-demo-node.name
}

resource "aws_eks_node_group" "k8s-demo" {
  cluster_name    = aws_eks_cluster.k8s-demo-cluster.name
  node_group_name = "k8s-demo"
  node_role_arn   = aws_iam_role.k8s-demo-node.arn
  subnet_ids      = aws_subnet.k8s-demo-private.*.id

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  depends_on = [
    aws_iam_role_policy_attachment.k8s-demo-node-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.k8s-demo-node-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.k8s-demo-node-AmazonEC2ContainerRegistryReadOnly,
  ]
}

#================== Cluster config ========================

resource "aws_iam_role" "k8s-demo-cluster" {
  name = "k8s-demo-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "k8s-demo-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.k8s-demo-cluster.name
}

resource "aws_security_group" "k8s-demo-cluster" {
  name        = "k8s-demo-cluster"
  description = "Cluster communication with worker nodes" 
  vpc_id      = aws_vpc.k8s-demo.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 65535
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = map(
    "Name", "k8s-demo-sg"
  )
}

resource "aws_eks_cluster" "k8s-demo-cluster" {
  name     = var.cluster-name
  role_arn = aws_iam_role.k8s-demo-cluster.arn

  vpc_config {
    security_group_ids = [aws_security_group.k8s-demo-cluster.id]
    subnet_ids         = aws_subnet.k8s-demo-private.*.id
  }

  depends_on = [
    aws_iam_role_policy_attachment.k8s-demo-cluster-AmazonEKSClusterPolicy,
  ]
}

#=============== RDS ======================

resource "aws_rds_cluster" "rds-demo" {
  count                               = 1
  availability_zones = ["us-east-1b", "us-east-1c", "us-east-1f"]
  cluster_identifier                  = "aurora-cluster1"
  database_name                       = "mydb1"
  master_username                     = "admin"
  master_password                     = "dbpassword"
  backup_retention_period             = "5"
  preferred_backup_window             = "07:00-09:00"
  copy_tags_to_snapshot               = "false"
  engine                              = "aurora"
}


#RDS SG

resource "aws_security_group" "default" {
  name        = "db-sg"
  description = "Allow inbound traffic from Security Groups and CIDRs"
  vpc_id      = aws_vpc.k8s-demo.id

  ingress {
    from_port       = "3306"
    to_port         = "3306"
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
