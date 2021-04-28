
# Entire configuration for rsearch_web group

variable "name" { default = "rsearch_web"}
variable "ami" { default = "ami-49e59a26" }
variable "instance_type" { default = "m5.large" }
variable "instance_count" { default = 2 }
variable "vpc_id" {}
variable "nat_gw_id" {}
variable "internet_gw" {}
variable "availability_zone" {}
variable "access_key_name" {}
variable "prod_subnet_cidrs_map" { type = "map" }
variable "mgmt_subnet_cidrs_map" { type = "map" }

variable "host" {}
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
resource "aws_subnet" "subnet_rsearch_web_public" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone}"
  cidr_block = "${lookup(var.prod_subnet_cidrs_map, "rsearch_web_public")}"
  tags {
    Name = "subnet-public-${var.name}"
    terraform = true
  }
  map_public_ip_on_launch = false
}

resource "aws_route_table" "rsearch_web_public_route_table" {
    vpc_id = "${var.vpc_id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${var.internet_gw}"
    }
    tags {
        Name = "RSearch Web Public Route"
    }
}

resource "aws_route_table_association" "rsearch_web_public_route_association" {
    subnet_id = "${aws_subnet.subnet_rsearch_web_public.id}"
    route_table_id = "${aws_route_table.rsearch_web_public_route_table.id}"
}

/* Define subnet */
resource "aws_subnet" "subnet_rsearch_web" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone}"
  cidr_block = "${lookup(var.prod_subnet_cidrs_map, "rsearch_web")}"
  tags {
    Name = "subnet-${var.name}"
    terraform = true
  }
  map_public_ip_on_launch = false
}

resource "aws_route_table" "rsearch_web_route_table" {
  vpc_id = "${var.vpc_id}"
  tags {
    Name = "rsearch_web_route_table"
  }
}

# add the nat gateway
resource "aws_route" "rsearch_web_nat_gateway_route" {
  route_table_id = "${aws_route_table.rsearch_web_route_table.id}"
  destination_cidr_block = "0.0.0.0/0"
  depends_on = ["aws_route_table.rsearch_web_route_table"]
  nat_gateway_id = "${var.nat_gw_id}"
}

# associate subnet to each route table
resource "aws_route_table_association" "rsearch_web_route_table_association" {
  subnet_id      = "${aws_subnet.subnet_rsearch_web.id}"
  route_table_id = "${aws_route_table.rsearch_web_route_table.id}"
}

/* Define Security Group */
resource "aws_security_group" "sg_rsearch_web" {
  name = "sg_rsearch_web"
  vpc_id = "${var.vpc_id}"
  description = "security group for main rsearch nginx site"
  ingress {
    to_port = 22
    from_port = 22
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.mgmt_subnet_cidrs_map, "mgmt_access")}"]
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
    from_port = 6379
    to_port = 6379
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "cust_auth_redis")}"]
  }
  egress {
    from_port = 9200
    to_port = 9200
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "rsearch_es")}"]
  }
  egress {
    from_port = 9092
    to_port = 9092
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
    from_port = 1443
    to_port   = 1443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags {
    Name = "RSearch Web API Security Group"
  }
}

/* Configure IAM certificate */
resource "aws_iam_server_certificate" "rsearch_cert" {
  name_prefix      = "somedomain.com"
  certificate_body = "${file("${path.module}/resources/web_certs/somedomain.com.crt")}"
  certificate_chain = "${file("${path.module}/resources/web_certs/somedomain.com.chain.crt")}"
  private_key      = "${file("${path.module}/resources/web_certs/somedomain.com.key")}"
  lifecycle {
    create_before_destroy = true
  }
}
/* */

/* Configure ELB */
resource "aws_elb" "elb_rsearch_web" {
  name                        = "${var.name}"
  connection_draining         = true
  connection_draining_timeout = 400
  idle_timeout                = 30
  subnets                     = ["${aws_subnet.subnet_rsearch_web_public.id}"]
  security_groups             = ["${aws_security_group.sg_rsearch_web.id}"]
  instances                   = ["${aws_instance.rsearch_web.*.id}"]

  listener {
    lb_port           = 443
    lb_protocol       = "https"
    instance_port     = 1443
    instance_protocol = "http"
    ssl_certificate_id = "${aws_iam_server_certificate.rsearch_cert.arn}"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 60
    interval            = 120
    target              = "TCP:80"
  }
}

/* Configure Instances */
resource "aws_instance" "rsearch_web" {
  count = "${var.instance_count}"
  ami = "${var.ami}"
  instance_type = "${var.instance_type}"
  key_name        = "${var.access_key_name}"
  vpc_security_group_ids = ["${aws_security_group.sg_rsearch_web.id}"]
  subnet_id = "${aws_subnet.subnet_rsearch_web.id}"
  private_ip = "${lookup(var.ips_map,count.index)}"
  iam_instance_profile = "${var.ec2_profile_name}"
  root_block_device {
    volume_size = "${var.root_block_size}"
  }
  tags {
    Name = "rsearch_web-${count.index}",
    Type = "rsearch_web"
    CodeDeploy = "rsearch_web"
  }

  # Allow AWS infrastructure metadata to propagate.
  provisioner "local-exec" {
    command = "sleep 120"
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
  provisioner "remote-exec" {
    inline = [
      # install all software
      "sudo apt-get update",
      "cat /tmp/ubuntu_pstack_prod_id_rsa.pub | sudo tee -a /home/ubuntu/.ssh/authorized_keys",
      "sudo chmod 600 /home/ubuntu/.ssh/*",
      "sudo apt-get -y install nginx",
      "sudo apt-get -y install python3",
      "sudo apt-get -y install python3-pip",
      "sudo apt-get -y install python3-dev",
      "sudo apt-get -y install uwsgi",
      "sudo apt-get -y install uwsgi-plugin-python3",
      #"sudo -H pip3 install --upgrade pip3",
      #"sudo -H pip3 install uwsgi",
      "sudo pip3 install Django==2.0.1",
      "sudo pip3 install django-cors-headers==2.1.0",
      "sudo pip3 install django-filter==1.1.0",
      "sudo pip3 install djangorestframework==3.7.7",
      "sudo pip3 install elasticsearch==5.5.0",
      "sudo pip3 install redis==2.10.6",
      "sudo pip3 install kafka-python==1.2.4",
      "sudo pip3 install requests==2.9.1",
      "sudo pip3 install jsonschema==2.6.0",
      "sudo pip3 install deepdiff==3.3.0",
      "wget -qO - http://packages.confluent.io/deb/4.0/archive.key | sudo apt-key add -",
      "sudo add-apt-repository 'deb [arch=amd64] http://packages.confluent.io/deb/4.0 stable main'",
      "sudo apt-get -y update",
      "sudo apt-get -y install librdkafka1",
      "sudo apt-get -y install librdkafka-dev",
      "sudo pip3 install confluent-kafka==0.11.0",
      "sudo mkdir -p /var/www/somedomain",
      "sudo chown -R www-data:www-data /var/www/somedomain",
      "sudo mkdir /var/log/rsearch",
      "sudo chown www-data:www-data /var/log/rsearch/",
      "sudo mkdir -p /etc/uwsgi/vassals/",
      "sudo cp /tmp/config_files/somedomain_rsearch.ini /etc/uwsgi/vassals/",
      "sudo cp /tmp/config_files/api_somedomain_com.conf /etc/nginx/conf.d/",
      "sudo cp -fpr /tmp/config_files/uwsgi.service /etc/systemd/system/",
      "sudo apt-get -y install ruby",
      "sudo apt-get -y install wget",
      "cd /home/ubuntu",
      "wget https://aws-codedeploy-ap-south-1.s3.amazonaws.com/latest/install -P /home/ubuntu/",
      "chmod +x /home/ubuntu/install",
      "sudo /home/ubuntu/install auto",
      "sudo service codedeploy-agent start",
      "rm -f /home/ubuntu/install",
      "sudo mv /etc/init.d/uwsgi /home/ubuntu/",
      "sleep 20",
      "sudo /bin/systemctl daemon-reload",
      "sleep 10",
      "sudo /bin/systemctl enable nginx",
      "sudo /bin/systemctl enable uwsgi",
      "sudo /bin/systemctl start nginx",
      "sudo /bin/systemctl start uwsgi"
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

/*
resource "aws_cloudwatch_metric_alarm" "rsearch_web_cpu" {
  alarm_name          = "alarmRsearchWebServerCPUUtilization"
  alarm_description   = "RsearchWeb server CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "${var.alarm_cpu_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.rsearch_web.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "rsearch_web_queue" {
  alarm_name          = "alarmRsearchWebServerDiskQueueDepth"
  alarm_description   = "RsearchWeb server disk queue depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DiskQueueDepth"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_disk_queue_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.rsearch_web.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "rsearch_web_disk_free" {
  alarm_name          = "alarmRsearchWebServerFreeStorageSpace"
  alarm_description   = "RsearchWeb server free storage space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_free_disk_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.rsearch_web.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "rsearch_web_memory_free" {
  alarm_name          = "alarmRsearchWebServerFreeableMemory"
  alarm_description   = "RsearchWeb server freeable memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_free_memory_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.rsearch_web.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}
*/


/* Map all DNS records to ELB */
resource "aws_route53_record" "rr_rsearch_web" {
  zone_id = "${var.route53_external_zone_id}"
  name = "${var.host}"
  #ttl = "3600"
  type = "A"
    alias {
    name                   = "${aws_elb.elb_rsearch_web.dns_name}"
    zone_id                = "${aws_elb.elb_rsearch_web.zone_id}"
    evaluate_target_health = true
  }
}
