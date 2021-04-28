
/** Entire configuration for pstack_web_nginx group **/

variable "name" { default = "access"}
variable "ami" { default = "ami-49e59a26" }
variable "instance_type" { default = "t2.micro" }
variable "vpc_id" {}
variable "availability_zone" {}
variable "mgmt_subnet_cidrs_map" { type = "map" }
variable "prod_subnet_cidrs_map" { type = "map" }
variable "host_access" { }
variable "route53_external_zone_id" {}
variable "access_key_name" {}
variable "internet_gw" {}

/* Define subnet */
resource "aws_subnet" "subnet_mgmt_access" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone}"
  cidr_block = "${lookup(var.mgmt_subnet_cidrs_map, "mgmt_access")}"
  tags {
    Name = "subnet-${var.name}"
    terraform = true
  }
  map_public_ip_on_launch = false
}

/* Define Security Group */
resource "aws_security_group" "sg_mgmt_access" {
  name = "sg_mgmt_access"
  vpc_id = "${var.vpc_id}"
  description = "security group for mgmt access"
  ingress {
    to_port = 22
    from_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["${values(var.prod_subnet_cidrs_map)}"]
  }
  tags {
    Name = "mgmt_access Security Group"
  }
}


/* Configure EIP */
#resource "aws_eip" "eip_mgmt_access" {
#  instance = "${aws_instance.mgmt_access.id}"
#  vpc = true
#}

resource "aws_route_table" "mgmt_access_route" {
  vpc_id = "${var.vpc_id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${var.internet_gw}"
  }
  tags {
    Name = "Mgmt Subnet Route"
  }
}

resource "aws_route_table_association" "mgmt_access_public" {
  subnet_id = "${aws_subnet.subnet_mgmt_access.id}"
  route_table_id = "${aws_route_table.mgmt_access_route.id}"
}

/* Configure Instances */
resource "aws_instance" "mgmt_access" {
  ami                     = "${var.ami}"
  instance_type           = "${var.instance_type}"
  availability_zone       = "${var.availability_zone}"
  key_name                = "${var.access_key_name}"
  vpc_security_group_ids  = ["${aws_security_group.sg_mgmt_access.id}"]
  subnet_id               = "${aws_subnet.subnet_mgmt_access.id}"
  associate_public_ip_address = true
  tags {
    Name = "mgmt_access"
  }
  # remote-exec to
  # create admin users, copy public key for access to jump box, to the right place and set permissions
  # copy private key of admin users (/home/animesh/.ssh/id_rsa) for access to all production servers
  # copy private key for deployment to /home/ubuntu/.ssh/id_rsa to be able to connect to all servers during deployment

  provisioner "remote-exec" {
    inline = [
      "sudo useradd --home-dir /home/animesh --shell /bin/bash --gid admin animesh -m",
      "sudo mkdir /home/animesh/.ssh",
      "sudo chown animesh:admin /home/animesh/.ssh",
      "echo 'animesh ALL=(ALL) NOPASSWD:ALL' | sudo tee -a /etc/sudoers"
    ]
    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
    }
  }
  provisioner "file" {
    source      = "${path.module}/resources/keys/animesh_jumpbox_id_rsa.pub"
    destination = "/tmp/animesh_jumpbox_id_rsa.pub"
    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
    }
  }
  provisioner "file" {
    source      = "${path.module}/resources/keys/ubuntu_pstack_prod_id_rsa"
    destination = "/tmp/ubuntu_pstack_prod_id_rsa"
    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
    }
  }
  provisioner "file" {
    source      = "${path.module}/resources/keys/ubuntu_pstack_deploy_id_rsa"
    destination = "/tmp/ubuntu_pstack_deploy_id_rsa"
    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
    }
  }
  provisioner "remote-exec" {
    inline = [
      "sudo cp -fpr /tmp/animesh_jumpbox_id_rsa.pub /home/animesh/.ssh/authorized_keys",
      "sudo cp -fpr /tmp/ubuntu_pstack_prod_id_rsa /home/animesh/.ssh/id_rsa",
      "sudo chmod 600 /home/animesh/.ssh/*",
      "sudo chown animesh:admin /home/animesh/.ssh/*",
      "cp -fpr /tmp/ubuntu_pstack_deploy_id_rsa /home/ubuntu/.ssh/id_rsa",
      "chmod 600 /home/ubuntu/.ssh/id_rsa"
    ]
    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
    }
  }
}

/* Map all DNS records to Gateway IP */
resource "aws_route53_record" "rr_mgmt_access" {
  zone_id = "${var.route53_external_zone_id}"
  name = "${var.host_access}"
  type = "A"
  ttl     = "300"
#  records = ["${aws_eip.eip_mgmt_access.public_ip}"]
  records = ["${aws_instance.mgmt_access.public_ip}"]
}

output "subnet_mgmt_access_id" {
  value = "${aws_subnet.subnet_mgmt_access.id}"
}

output "mgmt_access_ip" {
#  value = "${aws_eip.eip_mgmt_access.public_ip}"
  value = "${aws_instance.mgmt_access.public_ip}"
}
