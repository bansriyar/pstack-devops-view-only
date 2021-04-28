
# Entire configuration for rsearch_es group

variable "name" { default = "rsearch_es"}
variable "ami" { default = "ami-49e59a26" }
variable "instance_type" { default = "m5.xlarge" }
variable "instance_count" { default = 3 }
variable "vpc_id" {}
variable "nat_gw_id" {}
variable "availability_zone" {}
variable "access_key_name" {}
variable "prod_subnet_cidrs_map" { type = "map" }
variable "mgmt_subnet_cidrs_map" { type = "map" }

variable "host" { }
variable "ec2_profile_name" {}
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
resource "aws_subnet" "subnet_rsearch_es" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone}"
  cidr_block = "${lookup(var.prod_subnet_cidrs_map, "rsearch_es")}"
  tags {
    Name = "subnet-${var.name}"
    terraform = true
  }
  map_public_ip_on_launch = false
}

resource "aws_route_table" "rsearch_es_route_table" {
  vpc_id = "${var.vpc_id}"
  tags {
    Name = "rsearch_es_route_table"
  }
}

# add the nat gateway
resource "aws_route" "rsearch_es_nat_gateway_route" {
  route_table_id = "${aws_route_table.rsearch_es_route_table.id}"
  destination_cidr_block = "0.0.0.0/0"
  depends_on = ["aws_route_table.rsearch_es_route_table"]
  nat_gateway_id = "${var.nat_gw_id}"
}

# associate subnet to each route table
resource "aws_route_table_association" "rsearch_es_route_table_association" {
  subnet_id      = "${aws_subnet.subnet_rsearch_es.id}"
  route_table_id = "${aws_route_table.rsearch_es_route_table.id}"
}

/* Define Security Group */
resource "aws_security_group" "sg_rsearch_es" {
  name = "sg_rsearch_es"
  vpc_id = "${var.vpc_id}"
  description = "security group for rsearch_es"
  ingress {
    to_port = 22
    from_port = 22
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.mgmt_subnet_cidrs_map, "mgmt_access")}"]
  }
  ingress {
    from_port = 9200
    to_port = 9200
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "pstack_web_nodejs")}"]
  }
  ingress {
    from_port = 9200
    to_port = 9200
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "rsearch_web")}"]
  }
  ingress {
    from_port = 9200
    to_port = 9200
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "rsearch_es")}"]
  }
  ingress {
    from_port = 9300
    to_port = 9300
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "rsearch_es")}"]
  }
  # Needed for ZELB to work properly
  egress {
    from_port = 9200
    to_port = 9200
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "rsearch_es")}"]
  }
  egress {
    from_port = 9300
    to_port = 9300
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "rsearch_es")}"]
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
  tags {
    Name = "RSearch ES Security Group"
  }
}

/* Configure ELB */
resource "aws_elb" "elb_rsearch_es" {
  name                        = "${var.name}"
  connection_draining         = true
  connection_draining_timeout = 400
  idle_timeout                = 30
  subnets                     = ["${aws_subnet.subnet_rsearch_es.id}"]
  security_groups             = ["${aws_security_group.sg_rsearch_es.id}"]
  internal                    = true
  instances                   = ["${aws_instance.rsearch_es.*.id}"]

  listener {
    lb_port           = 9200
    lb_protocol       = "http"
    instance_port     = 9200
    instance_protocol = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 60
    interval            = 120
    target              = "TCP:9200"
  }
}

/* Configure Instances */
resource "aws_instance" "rsearch_es" {
  count = "${var.instance_count}"
  ami = "${var.ami}"
  instance_type = "${var.instance_type}"
  key_name        = "${var.access_key_name}"
  vpc_security_group_ids = ["${aws_security_group.sg_rsearch_es.id}"]
  subnet_id = "${aws_subnet.subnet_rsearch_es.id}"
  private_ip = "${lookup(var.ips_map,count.index)}"
  iam_instance_profile = "${var.ec2_profile_name}"
  root_block_device {
    volume_size = "${var.root_block_size}"
  }
  ebs_block_device {
    device_name = "/dev/sdg"
    volume_size = 100
    volume_type = "io1"
    iops = 1000
    delete_on_termination = false
  }
  tags {
    Name = "rsearch_es-${count.index}",
    Type = "rsearch_es"
    CodeDeploy = "rsearch_es"
  }
  # Allow AWS infrastructure metadata to propagate.
  provisioner "local-exec" {
    command = "sleep 120"
  }
  # Allow EBS BLOCK Device Mounting
  user_data = "${file("${path.module}/resources/scripts/attach_ebs.sh")}"

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
      "sudo apt-get -y install openjdk-8-jre",
      # Install Elasticsearch
      "wget -O - http://packages.elasticsearch.org/GPG-KEY-elasticsearch | sudo apt-key add -",
      "echo 'deb https://artifacts.elastic.co/packages/5.x/apt stable main' | sudo tee -a /etc/apt/sources.list.d/elastic-5.x.list",
      "sudo apt-get update",
      "sudo apt-get -y install elasticsearch",
      "sudo /bin/systemctl enable elasticsearch.service",
      "sudo /bin/systemctl daemon-reload",
      "sudo cp -fpr /tmp/config_files/elasticsearch.yml /etc/elasticsearch/",
      "sudo cp -fpr /tmp/config_files/elasticsearch.jvm.options /etc/elasticsearch/jvm.options",
      "sudo cp -fpr /tmp/config_files/elasticsearch.service /usr/lib/systemd/system/elasticsearch.service",
      "sudo cp -fpr /tmp/config_files/default_index_template.json /tmp/",
      # ES Specific Options
      "sudo swapoff -a",
      "sudo sysctl -w vm.swappiness=1",
      "sudo ulimit -l unlimited",
      "sudo /bin/systemctl daemon-reload",
      "sudo /bin/systemctl start elasticsearch.service",
      "sudo apt-get -y install ruby",
      "sudo apt-get -y install wget",
      "curl -XPUT 'http://127.0.0.1:9200/_template/default_template' -H 'Content-Type: application/json' -d @/tmp/default_index_template.json",
      "cd /home/ubuntu",
      "wget https://aws-codedeploy-ap-south-1.s3.amazonaws.com/latest/install -P /home/ubuntu/",
      "chmod +x /home/ubuntu/install",
      "sudo /home/ubuntu/install auto",
      "sudo service codedeploy-agent start",
      "rm -f /home/ubuntu/install",
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
resource "aws_cloudwatch_metric_alarm" "rsearch_es_cpu" {
  alarm_name          = "alarmRsearchESServerCPUUtilization"
  alarm_description   = "RsearchES server CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "${var.alarm_cpu_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.rsearch_es.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "rsearch_es_queue" {
  alarm_name          = "alarmRsearchESServerDiskQueueDepth"
  alarm_description   = "RsearchES server disk queue depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DiskQueueDepth"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_disk_queue_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.rsearch_es.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "rsearch_es_disk_free" {
  alarm_name          = "alarmRsearchESServerFreeStorageSpace"
  alarm_description   = "RsearchES server free storage space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_free_disk_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.rsearch_es.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "rsearch_es_memory_free" {
  alarm_name          = "alarmRsearchESServerFreeableMemory"
  alarm_description   = "RsearchES server freeable memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_free_memory_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.rsearch_es.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}*/

/* Map DNS records for ELB */
resource "aws_route53_record" "rr_rsearch_es" {
  zone_id = "${var.route53_internal_zone_id}"
  name = "${var.host}"
  #ttl = "300"
  type = "A"
    alias {
    name                   = "${aws_elb.elb_rsearch_es.dns_name}"
    zone_id                = "${aws_elb.elb_rsearch_es.zone_id}"
    evaluate_target_health = true
  }
}
