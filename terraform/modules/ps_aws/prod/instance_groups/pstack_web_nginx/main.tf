# Entire configuration for pstack_web_nginx group

variable "name" { default = "pstack_web_nginx"}
variable "ami" { default = "ami-49e59a26" }
variable "instance_type" { default = "t2.small" }
variable "instance_count" { default = 2 }
variable "vpc_id" {}
variable "nat_gw_id" {}
variable "internet_gw" {}
variable "access_key_name" {}
variable "availability_zone" {}
variable "prod_subnet_cidrs_map" { type = "map" }
variable "mgmt_subnet_cidrs_map" { type = "map" }
variable "sns_topic" {}
variable "host_domain" {}
variable "host_mainsite" { }
variable "host_dashboard" { }
variable "host_developer" { }
variable "host_blog" { }
variable "host_web_api" { }
variable "ec2_profile_name" {}
variable "ps_bastion_host" {}
variable "route53_external_zone_id" {}
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


/* Define public subnet to be used by ELB */
resource "aws_subnet" "subnet_pstack_web_nginx_public" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone}"
  cidr_block = "${lookup(var.prod_subnet_cidrs_map, "pstack_web_nginx_public")}"
  tags {
    Name = "subnet-public-${var.name}"
    terraform = true
  }
  map_public_ip_on_launch = false
}

resource "aws_route_table" "pstack_web_nginx_public_route_table" {
    vpc_id = "${var.vpc_id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${var.internet_gw}"
    }
    tags {
        Name = "Pstack Web Nginx Public Route"
    }
}

resource "aws_route_table_association" "pstack_web_nginx_public_route_association" {
    subnet_id = "${aws_subnet.subnet_pstack_web_nginx_public.id}"
    route_table_id = "${aws_route_table.pstack_web_nginx_public_route_table.id}"
}

/* Define subnet */
resource "aws_subnet" "subnet_pstack_web_nginx" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone}"
  cidr_block = "${lookup(var.prod_subnet_cidrs_map, "pstack_web_nginx")}"
  tags {
    Name = "subnet-${var.name}"
    terraform = true
  }
  map_public_ip_on_launch = false
}

resource "aws_route_table" "pstack_web_nginx_route_table" {
  vpc_id = "${var.vpc_id}"
  tags {
    Name = "pstack_web_nginx_route_table"
  }
}

# add the nat gateway
resource "aws_route" "pstack_web_nginx_nat_gateway_route" {
  route_table_id = "${aws_route_table.pstack_web_nginx_route_table.id}"
  destination_cidr_block = "0.0.0.0/0"
  depends_on = ["aws_route_table.pstack_web_nginx_route_table"]
  nat_gateway_id = "${var.nat_gw_id}"
}

# associate subnet to each route table
resource "aws_route_table_association" "pstack_web_nginx_route_table_association" {
  subnet_id      = "${aws_subnet.subnet_pstack_web_nginx.id}"
  route_table_id = "${aws_route_table.pstack_web_nginx_route_table.id}"
}

/* Define Security Group */
resource "aws_security_group" "sg_pstack_web_nginx" {
  name = "sg_pstack_web_nginx"
  vpc_id = "${var.vpc_id}"
  description = "security group for main nginx site"
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
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "pstack_web_nodejs")}"]
  }
  ingress {
    to_port = 80
    from_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    to_port = 443
    from_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    to_port = 1443
    from_port = 1443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 10001
    to_port = 10005
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "pstack_web_nodejs")}"]
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
    from_port = 1443
    to_port   = 1443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name = "pstack_nginx Security Group"
  }
}

/* Configure IAM certificate */
resource "aws_iam_server_certificate" "pstack_cert" {
  name_prefix      = "somedomain.com"
  certificate_body = "${file("${path.module}/resources/web_certs/somedomain.com.crt")}"
  private_key      = "${file("${path.module}/resources/web_certs/somedomain.com.key")}"
  lifecycle {
    create_before_destroy = true
  }
}
/* */

/* Configure ELB */
resource "aws_elb" "elb_pstack_web_nginx" {
  name                        = "${var.name}"
  connection_draining         = true
  connection_draining_timeout = 400
  idle_timeout                = 30
  subnets                     = ["${aws_subnet.subnet_pstack_web_nginx_public.id}"]
  security_groups             = ["${aws_security_group.sg_pstack_web_nginx.id}"]
  instances                   = ["${aws_instance.pstack_web_nginx.*.id}"]

  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = 80
    instance_protocol = "http"
  }

  listener {
    lb_port           = 443
    lb_protocol       = "https"
    instance_port     = 1443
    instance_protocol = "http"
    ssl_certificate_id = "${aws_iam_server_certificate.pstack_cert.arn}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 60
    interval            = 120
    target              = "TCP:80"
  }
}

/* Configure Instances */
resource "aws_instance" "pstack_web_nginx" {
  count = "${var.instance_count}"
  ami = "${var.ami}"
  instance_type = "${var.instance_type}"
  key_name        = "${var.access_key_name}"
  vpc_security_group_ids = ["${aws_security_group.sg_pstack_web_nginx.id}"]
  subnet_id = "${aws_subnet.subnet_pstack_web_nginx.id}"
  private_ip = "${lookup(var.ips_map,count.index)}"
  iam_instance_profile = "${var.ec2_profile_name}"
  root_block_device {
    volume_size = "${var.root_block_size}"
  }
  tags {
    Name = "pstack_web_nginx-${count.index}"
    CodeDeploy = "pstack_web"
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
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "cat /tmp/ubuntu_pstack_prod_id_rsa.pub | sudo tee -a /home/ubuntu/.ssh/authorized_keys",
      "sudo chmod 600 /home/ubuntu/.ssh/*",
      "sudo apt-get -y install nginx",
      "sudo cp -fpr /tmp/config_files/*.conf /etc/nginx/conf.d/",
      "sudo systemctl enable nginx",
      "sudo /bin/systemctl daemon-reload",
      "sudo systemctl enable nginx",
      "sudo apt-get -y install ruby",
      "sudo apt-get -y install wget",
      "cd /home/ubuntu",
      "wget https://aws-codedeploy-ap-south-1.s3.amazonaws.com/latest/install -P /home/ubuntu/",
      "chmod +x /home/ubuntu/install",
      "sudo /home/ubuntu/install auto",
      "sudo service codedeploy-agent start",
      "rm -f /home/ubuntu/install",
      "sudo systemctl restart nginx"
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

resource "aws_sns_topic" "sns_topic" {
  name = "${var.sns_topic}"
}

#resource "aws_cloudwatch_metric_alarm" "pstack_web_nginx_cpu" {
#  alarm_name          = "alarmPstackWebNginxServerCPUUtilization"
#  alarm_description   = "stackWebNginx server CPU utilization"
#  comparison_operator = "GreaterThanThreshold"
#  evaluation_periods  = "1"
#  metric_name         = "CPUUtilization"
#  namespace           = "AWS/EC2"
#  period              = "300"
#  statistic           = "Average"
#  threshold           = "${var.alarm_cpu_threshold}"
#  count               = "${var.instance_count}"
#  dimensions {
#    InstanceId = "${element(aws_instance.pstack_web_nginx.*.id, count.index)}"
#  }
#  alarm_actions = ["${aws_sns_topic.sns_topic.id}"]
#}

#resource "aws_cloudwatch_metric_alarm" "pstack_web_nginx_disk_queue" {
#  alarm_name          = "alarmstackWebNginxServerDiskQueueDepth"
#  alarm_description   = "stackWebNginx server disk queue depth"
#  comparison_operator = "GreaterThanThreshold"
#  evaluation_periods  = "1"
#  metric_name         = "DiskQueueDepth"
#  namespace           = "AWS/RDS"
#  period              = "60"
#  statistic           = "Average"
#  threshold           = "${var.alarm_disk_queue_threshold}"
#  count               = "${var.instance_count}"
#  dimensions {
#    InstanceIdentifier = "${element(aws_instance.pstack_web_nginx.*.id, count.index)}"
#  }

#  alarm_actions = ["${var.alarm_actions}"]
#}

#resource "aws_cloudwatch_metric_alarm" "pstack_web_nginx_disk_free" {
#  alarm_name          = "alarmstackWebNginxServerFreeStorageSpace"
#  alarm_description   = "stackWebNginx server free storage space"
#  comparison_operator = "LessThanThreshold"
#  evaluation_periods  = "1"
#  metric_name         = "FreeStorageSpace"
#  namespace           = "AWS/RDS"
#  period              = "60"
#  statistic           = "Average"
#  threshold           = "${var.alarm_free_disk_threshold}"

#  count               = "${var.instance_count}"
#  dimensions {
#    InstanceIdentifier = "${element(aws_instance.pstack_web_nginx.*.id, count.index)}"
#  }

#  alarm_actions = ["${var.alarm_actions}"]
#}

#resource "aws_cloudwatch_metric_alarm" "pstack_web_nginx_memory_free" {
#  alarm_name          = "alarmstackWebNginxServerFreeableMemory"
#  alarm_description   = "stackWebNginx server freeable memory"
#  comparison_operator = "LessThanThreshold"
#  evaluation_periods  = "1"
#  metric_name         = "FreeableMemory"
#  namespace           = "AWS/RDS"
#  period              = "60"
#  statistic           = "Average"
#  threshold           = "${var.alarm_free_memory_threshold}"

#  count               = "${var.instance_count}"
#  dimensions {
#    InstanceIdentifier = "${element(aws_instance.pstack_web_nginx.*.id, count.index)}"
#  }

#  alarm_actions = ["${var.alarm_actions}"]
#}


/* Map all DNS records to ELB */
resource "aws_route53_record" "rr_pstack_web_nginx_mainsite" {
  zone_id = "${var.route53_external_zone_id}"
  name = "${var.host_mainsite}"
  #ttl = "3600"
  type = "A"
    alias {
    name                   = "${aws_elb.elb_pstack_web_nginx.dns_name}"
    zone_id                = "${aws_elb.elb_pstack_web_nginx.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "rr_pstack_web_nginx_domain" {
  zone_id = "${var.route53_external_zone_id}"
  name = "${var.host_domain}"
  #ttl = "3600"
  type = "A"
    alias {
    name                   = "${aws_elb.elb_pstack_web_nginx.dns_name}"
    zone_id                = "${aws_elb.elb_pstack_web_nginx.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "rr_pstack_web_nginx_dashboard" {
  zone_id = "${var.route53_external_zone_id}"
  name = "${var.host_dashboard}"
  #ttl = "3600"
  type = "A"
    alias {
    name                   = "${aws_elb.elb_pstack_web_nginx.dns_name}"
    zone_id                = "${aws_elb.elb_pstack_web_nginx.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "rr_pstack_web_nginx_developer" {
  zone_id = "${var.route53_external_zone_id}"
  name = "${var.host_developer}"
  #ttl = "3600"
  type = "A"
    alias {
    name                   = "${aws_elb.elb_pstack_web_nginx.dns_name}"
    zone_id                = "${aws_elb.elb_pstack_web_nginx.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "rr_pstack_web_nginx_blog" {
  zone_id = "${var.route53_external_zone_id}"
  name = "${var.host_blog}"
  #ttl = "3600"
  type = "A"
    alias {
    name                   = "${aws_elb.elb_pstack_web_nginx.dns_name}"
    zone_id                = "${aws_elb.elb_pstack_web_nginx.zone_id}"
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "rr_pstack_web_nginx_web_api" {
  zone_id = "${var.route53_external_zone_id}"
  name = "${var.host_web_api}"
  #ttl = "3600"
  type = "A"
    alias {
    name                   = "${aws_elb.elb_pstack_web_nginx.dns_name}"
    zone_id                = "${aws_elb.elb_pstack_web_nginx.zone_id}"
    evaluate_target_health = true
  }
}
