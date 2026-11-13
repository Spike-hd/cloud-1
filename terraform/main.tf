terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-3" # Paris
}

/*
 * data = source d'information, ici l'AMI Ubuntu 24.04
 * data "aws_ami" "ubuntu" -> on cherche aws_ami et on l'appelle ubuntu
 * AMi = Amazon Machine Image, c'est l'image de base pour créer une instance EC2
 * owners = ["099720109477"] = ID du propriétaire de l'AMI Ubuntu
 * filter = filtre pour trouver l'AMI Ubuntu 24.04 la plus récente
 * En résumé, ce bloc de code Terraform permet de récupérer l'AMI Ubuntu 24.04 la plus récente
 */

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

/*
 * resource = ressource à créer, ici une instance EC2
 * resource "aws_instance" "key_pair" -> on crée une instance EC2 et on l'appelle key_pair

resource "aws_key_pair" "key_pair" {
  key_name   = "hadrien"
  public_key = file("~/.ssh/id_ed25519.pub")
}

* Mais on ne va pas utiliser cette clé pour se connecter à l'instance EC2.
* On va utiliser celle que je possede deja

*/

# data source pour récupérer la clé publique existante "Macbook" dans AWS
data "aws_key_pair" "macbook_key" {
  key_name = "Macbook"
}

# Ingress -> connexion entrante
# Egress -> connexion sortante (initiée par l'instance EC2 en premier)
resource "aws_security_group" "ssh" {
  name = "ssh-access"

  # SSH : seulement
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["91.151.126.62/32"] # Mon ip
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 signifie tous les protocoles
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web" {
  name = "web-access"

  # HTTP : ouvert à tous
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS : ouvert à tous
  ingress {
    from_port   = 443
    to_port     = 443
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

# L'instance
resource "aws_instance" "serveur" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  key_name               = data.aws_key_pair.macbook_key.key_name
  vpc_security_group_ids = [aws_security_group.ssh.id, aws_security_group.web.id]

  tags = { Name = "cloud-1" }
}

output "ip_publique" {
  value = aws_instance.serveur.public_ip
}