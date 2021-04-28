
# Entire configuration for pstack_web_nodejs group

variable "name" { default = "pstack_web_nodejs"}
variable "ami" { default = "ami-49e59a26" }
variable "instance_type" { default = "t2.medium" }
variable "instance_count" { default = 2 }
variable "vpc_id" {}
variable "nat_gw_id" {}
variable "availability_zone" {}
variable "access_key_name" {}
variable "prod_subnet_cidrs_map" { type = "map" }
variable "mgmt_subnet_cidrs_map" { type = "map" }
variable "ec2_profile_name" {}
variable "host" { }
variable "ps_bastion_host" {}
variable "route53_internal_zone_id" {}
variable "ips_map" { type = "map"}
variable "root_block_size" {}

variable "alarm_cpu_threshold" {
  default = "75"
}
variable "alarm_disk_queue_threshold" {
  default = "10"
}
variable "alarm_free_disk_threshold" {
  default = "5000000000"
}
variable "alarm_free_memory_threshold" {
  default = "128000000"
}
variable "alarm_actions" {
  default = ""
}

/* Define subnet */
resource "aws_subnet" "subnet_pstack_web_nodejs" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone}"
  cidr_block = "${lookup(var.prod_subnet_cidrs_map, "pstack_web_nodejs")}"
  tags {
    Name = "subnet-${var.name}"
    terraform = true
  }
  map_public_ip_on_launch = false
}

resource "aws_route_table" "pstack_web_nodejs_route_table" {
  vpc_id = "${var.vpc_id}"
  tags {
    Name = "pstack_web_nodejs_route_table"
  }
}

# add the nat gateway
resource "aws_route" "pstack_web_nodejs_nat_gateway_route" {
  route_table_id = "${aws_route_table.pstack_web_nodejs_route_table.id}"
  destination_cidr_block = "0.0.0.0/0"
  depends_on = ["aws_route_table.pstack_web_nodejs_route_table"]
  nat_gateway_id = "${var.nat_gw_id}"
}

# associate subnet to each route table
resource "aws_route_table_association" "pstack_web_nodejs_route_table_association" {
  subnet_id      = "${aws_subnet.subnet_pstack_web_nodejs.id}"
  route_table_id = "${aws_route_table.pstack_web_nodejs_route_table.id}"
}

/* Define Security Group */
resource "aws_security_group" "sg_pstack_web_nodejs" {
  name = "sg_pstack_web_nodejs"
  vpc_id = "${var.vpc_id}"
  description = "security group for nodejs"
  ingress {
    to_port = 22
    from_port = 22
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.mgmt_subnet_cidrs_map, "mgmt_access")}"]
  }
  ingress {
    from_port = 10001
    to_port = 10005
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "pstack_web_nginx")}"]
  }
  ingress {
    from_port = 10001
    to_port = 10005
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 9200
    to_port = 9200
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "rsearch_es")}"]
  }
  egress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "cust_auth_mysql_a")}", "${lookup(var.prod_subnet_cidrs_map, "cust_auth_mysql_b")}"]
  }
  egress {
    from_port = 6379
    to_port = 6379
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "cust_auth_redis")}"]
  }
  egress {
    from_port = 9200
    to_port = 9200
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "analytics")}"]
  }
  egress {
    from_port = 80
    to_port   = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 443
    to_port   = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 10001
    to_port = 10005
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "pstack_web_nginx")}"]
  }
  egress {
    from_port = 10001
    to_port = 10005
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name = "pstack_nodejs Security Group"
  }
}

/* Configure ELB */
resource "aws_elb" "elb_pstack_web_nodejs" {
  name                        = "${var.name}"
  connection_draining         = true
  connection_draining_timeout = 400
  idle_timeout                = 30
  subnets                     = ["${aws_subnet.subnet_pstack_web_nodejs.id}"]
  security_groups             = ["${aws_security_group.sg_pstack_web_nodejs.id}"]
  internal                    = true
  instances                   = ["${aws_instance.pstack_web_nodejs.*.id}"]

  listener {
    lb_port           = 10001
    lb_protocol       = "http"
    instance_port     = 10001
    instance_protocol = "http"
  }

  listener {
    lb_port           = 10002
    lb_protocol       = "http"
    instance_port     = 10002
    instance_protocol = "http"
  }

  listener {
    lb_port           = 10003
    lb_protocol       = "http"
    instance_port     = 10003
    instance_protocol = "http"
  }

  listener {
    lb_port           = 10004
    lb_protocol       = "http"
    instance_port     = 10004
    instance_protocol = "http"
  }

  listener {
    lb_port           = 10005
    lb_protocol       = "http"
    instance_port     = 10005
    instance_protocol = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 60
    interval            = 120
    target              = "TCP:10001"
  }
}

/* Configure Instances */
resource "aws_instance" "pstack_web_nodejs" {
  count = "${var.instance_count}"
  ami = "${var.ami}"
  instance_type = "${var.instance_type}"
  key_name        = "${var.access_key_name}"
  vpc_security_group_ids = ["${aws_security_group.sg_pstack_web_nodejs.id}"]
  subnet_id = "${aws_subnet.subnet_pstack_web_nodejs.id}"
  private_ip = "${lookup(var.ips_map,count.index)}"
  iam_instance_profile = "${var.ec2_profile_name}"
  root_block_device {
    volume_size = "${var.root_block_size}"
  }
  tags {
    Name = "pstack_web_nodejs-${count.index}"
    CodeDeploy = "pstack_www"
  }

  # Allow AWS infrastructure metadata to propagate.
  provisioner "local-exec" {
    command = "sleep 120"
  }
  provisioner "file" {
    source      = "${path.module}/resources/config_files"
    destination = "/tmp/config_files"
    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
      type     = "ssh"
      bastion_host = "${var.ps_bastion_host}"
      bastion_user = "ubuntu"
      bastion_private_key  = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
    }
  }
  provisioner "file" {
    source      = "${path.module}/resources/keys/ubuntu_pstack_prod_id_rsa.pub"
    destination = "/tmp/ubuntu_pstack_prod_id_rsa.pub"
    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
      type     = "ssh"
      bastion_host = "${var.ps_bastion_host}"
      bastion_user = "ubuntu"
      bastion_private_key  = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
    }
  }
  provisioner "file" {
    source      = "${path.module}/resources/scripts"
    destination = "/tmp/scripts"
    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
      type     = "ssh"
      bastion_host = "${var.ps_bastion_host}"
      bastion_user = "ubuntu"
      bastion_private_key  = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
    }
  }
  provisioner "remote-exec" {
    inline = [
      # install nginx
      "cat /tmp/ubuntu_pstack_prod_id_rsa.pub | sudo tee -a /home/ubuntu/.ssh/authorized_keys",
      "sudo chmod 600 /home/ubuntu/.ssh/*",
      "curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -",
      "sudo apt-get update",
      "sudo apt-get -y install mysql-client",
      "sudo apt-get -y install nginx",
      "sudo apt-get -y install nodejs",
      "sudo apt-get install -y build-essential",
      "sudo apt-get -y install npm",
      "sudo npm install pm2 -g",
      "sudo npm install http-server -g",
      "sudo npm install -g @angular/cli",
      "sudo apt-get -y install python-pip",
      "sudo pip2 install mkdocs",
      "sudo mkdir -p /var/www/somedomain/www_somedomain_com",
      "sudo mkdir -p /var/www/somedomain/dashboard_somedomain_com",
      "sudo mkdir -p /var/www/somedomain/blog_somedomain_com",
      "sudo mkdir -p /var/www/somedomain/developer_somedomain_com",
      "sudo mkdir -p /var/www/somedomain/web-api_somedomain_com",
      "sudo pm2 startup ubuntu",
      "sudo /bin/systemctl daemon-reload",
      "sudo cp -fpr /tmp/config_files/*.conf /etc/nginx/conf.d/",
      "sudo systemctl enable nginx",
      "sudo /bin/systemctl daemon-reload",
      "sudo apt-get -y install ruby",
      "sudo apt-get -y install wget",
      "sudo npm install -g ghost-cli",
      "cd /var/www/somedomain/blog_somedomain_com",
      "/bin/bash /tmp/scripts/install_ghost.sh",
      "cd /home/ubuntu",
      "wget https://aws-codedeploy-ap-south-1.s3.amazonaws.com/latest/install -P /home/ubuntu/",
      "chmod +x /home/ubuntu/install",
      "sudo /home/ubuntu/install auto",
      "sudo service codedeploy-agent start",
      "rm -f /home/ubuntu/install",
      "sudo systemctl start nginx"
    ]
    connection {
      type     = "ssh"
      user     = "ubuntu"
      private_key = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
      type     = "ssh"
      bastion_host = "${var.ps_bastion_host}"
      bastion_user = "ubuntu"
      bastion_private_key  = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa")}"
    }
  }
}

/*resource "aws_cloudwatch_metric_alarm" "pstack_web_nodejs_cpu" {
  alarm_name          = "alarmPstackWebNodejsServerCPUUtilization"
  alarm_description   = "PstackWebNodejs server CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "${var.alarm_cpu_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.pstack_web_nodejs.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "pstack_web_nodejs_queue" {
  alarm_name          = "alarmPstackWebNodejsServerDiskQueueDepth"
  alarm_description   = "PstackWebNodejs server disk queue depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DiskQueueDepth"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_disk_queue_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.pstack_web_nodejs.*.id, count.index)}"
  }
  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "pstack_web_nodejs_disk_free" {
  alarm_name          = "alarmPstackWebNodejsServerFreeStorageSpace"
  alarm_description   = "PstackWebNodejs server free storage space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_free_disk_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.pstack_web_nodejs.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "pstack_web_nodejs_memory_free" {
  alarm_name          = "alarmPstackWebNodejsServerFreeableMemory"
  alarm_description   = "PstackWebNodejs server freeable memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_free_memory_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.pstack_web_nodejs.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}*/


/* Map DNS to ELB */
resource "aws_route53_record" "rr_pstack_web_nodejs" {
  zone_id = "${var.route53_internal_zone_id}"
  name = "${var.host}"
  #ttl = "300"
  type = "A"
    alias {
    name                   = "${aws_elb.elb_pstack_web_nodejs.dns_name}"
    zone_id                = "${aws_elb.elb_pstack_web_nodejs.zone_id}"
    evaluate_target_health = true
  }
}
