
# Entire configuration for analytics group

variable "name" { default = "analytics"}
variable "ami" { default = "ami-49e59a26" }
variable "instance_type" { default = "t2.medium" }
variable "instance_count" { default = 2 }
variable "vpc_id" {}
variable "nat_gw_id" {}
variable "availability_zone" {}
variable "prod_subnet_cidrs_map" { type = "map" }
variable "mgmt_subnet_cidrs_map" { type = "map" }
variable "host" {}
variable "ec2_profile_name" {}
variable "ps_bastion_host" {}
variable "access_key_name" {}
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
resource "aws_subnet" "subnet_analytics" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone}"
  cidr_block = "${lookup(var.prod_subnet_cidrs_map, "analytics")}"
  tags {
    Name = "subnet-${var.name}"
    terraform = true
  }
  map_public_ip_on_launch = false
}

resource "aws_route_table" "analytics_route_table" {
  vpc_id = "${var.vpc_id}"
  tags {
    Name = "analytics_route_table"
  }
}

# add the nat gateway
resource "aws_route" "analytics_nat_gateway_route" {
  route_table_id = "${aws_route_table.analytics_route_table.id}"
  destination_cidr_block = "0.0.0.0/0"
  depends_on = ["aws_route_table.analytics_route_table"]
  nat_gateway_id = "${var.nat_gw_id}"
}

# associate subnet to each route table
resource "aws_route_table_association" "analytics_route_table_association" {
  subnet_id      = "${aws_subnet.subnet_analytics.id}"
  route_table_id = "${aws_route_table.analytics_route_table.id}"
}

/* Define Security Group */
resource "aws_security_group" "sg_analytics" {
  name = "sg_analytics"
  vpc_id = "${var.vpc_id}"
  description = "security group for analytics"
  ingress {
    to_port = 22
    from_port = 22
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.mgmt_subnet_cidrs_map, "mgmt_access")}"]
  }
  ingress {
    to_port = 9092
    from_port = 9092
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "rsearch_web")}"]
  }
  ingress {
    from_port = 9200
    to_port = 9200
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "pstack_web_nodejs")}"]
  }
  ingress {
    to_port = 9200
    from_port = 9200
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "analytics")}"]
  }
  egress {
    to_port = 9200
    from_port = 9200
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "analytics")}"]
  }
  ingress {
    to_port = 9092
    from_port = 9092
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "analytics")}"]
  }
  egress {
    to_port = 9092
    from_port = 9092
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
  tags {
    Name = "analytics Security Group"
  }
}

/* Configure ELB */
resource "aws_elb" "elb_analytics" {
  name                        = "${var.name}"
  connection_draining         = true
  connection_draining_timeout = 400
  idle_timeout                = 30
  subnets                     = ["${aws_subnet.subnet_analytics.id}"]
  security_groups             = ["${aws_security_group.sg_analytics.id}"]
  internal                    = true
  instances                   = ["${aws_instance.analytics.*.id}"]
  listener {
    lb_port           = 9092
    lb_protocol       = "tcp"
    instance_port     = 9092
    instance_protocol = "tcp"
  }

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
    target              = "TCP:9092"
  }
}

/* Configure Instances */
resource "aws_instance" "analytics" {
  count = "${var.instance_count}"
  ami = "${var.ami}"
  instance_type = "${var.instance_type}"
  key_name        = "${var.access_key_name}"
  vpc_security_group_ids = ["${aws_security_group.sg_analytics.id}"]
  subnet_id = "${aws_subnet.subnet_analytics.id}"
  private_ip = "${lookup(var.ips_map,count.index)}"
  iam_instance_profile = "${var.ec2_profile_name}"
  root_block_device {
    volume_size = "${var.root_block_size}"
  }
  tags {
    Name = "analytics-${count.index}"
    CodeDeploy = "analytics"
  }
  # remote-exec to
  # create admin users, copy public key for access to jump box, to the right place and set permissions
  # copy public key for prod access to /home/ubuntu/.ssh/id_rsa.pub to be able to receive connections
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
      # install zookeeper
      "sudo apt-get update",
      "cat /tmp/ubuntu_pstack_prod_id_rsa.pub | sudo tee -a /home/ubuntu/.ssh/authorized_keys",
      "sudo chmod 600 /home/ubuntu/.ssh/*",
      "sudo apt-get -y install openjdk-8-jre",
      "sudo apt-get -y install zookeeper zookeeperd",
      # download and install kafka
      "sudo curl -o /opt/kafka.tgz  http://ftp.jaist.ac.jp/pub/apache/kafka/0.10.0.0/kafka_2.11-0.10.0.0.tgz",
      "sudo tar xvfz /opt/kafka.tgz -C /opt/",
      "sudo mv /opt/kafka_2.11-0.10.0.0 /opt/kafka",
      "sudo /usr/sbin/adduser --disabled-password --gecos '' --home /opt/kafka kafka",
      "sudo cp -fpr /tmp/config_files/kafka.service /etc/systemd/system/",
      "sudo cp -fpr /tmp/config_files/kafka.server.properties ~kafka/config/server.properties",
      "sudo /bin/systemctl enable kafka.service",
      "sudo /bin/systemctl daemon-reload",
      "sudo /bin/systemctl start kafka.service",
      "/opt/kafka/bin/kafka-topics.sh --create --topic RSearch --zookeeper localhost:2181 --partitions 1 --replication-factor 1",

      # Install Elasticsearch
      "wget -O - http://packages.elasticsearch.org/GPG-KEY-elasticsearch | sudo apt-key add -",
      "echo 'deb https://artifacts.elastic.co/packages/5.x/apt stable main' | sudo tee -a /etc/apt/sources.list.d/elastic-5.x.list",
      "sudo apt-get update",
      "sudo apt-get -y install elasticsearch",
      "sudo systemctl enable elasticsearch.service",
      "sudo /bin/systemctl daemon-reload",
      "sudo cp -fpr /tmp/config_files/elasticsearch.yml /etc/elasticsearch/",
      "sudo cp -fpr /tmp/config_files/elasticsearch.jvm.options /etc/elasticsearch/jvm.options",
      "sudo systemctl start elasticsearch.service",
      "sudo apt-get -y install logstash",
      "sudo cp /tmp/config_files/10-rsearch-kafka.conf /etc/logstash/conf.d/",
      "sudo systemctl enable logstash.service",
      "sudo /bin/systemctl daemon-reload",
      "sudo systemctl start logstash.service",
      "sudo apt-get -y install ruby",
      "sudo apt-get -y install wget",
      "cd /home/ubuntu",
      "wget https://aws-codedeploy-ap-south-1.s3.amazonaws.com/latest/install -P /home/ubuntu/",
      "chmod +x /home/ubuntu/install",
      "sudo /home/ubuntu/install auto",
      "sudo service codedeploy-agent start",
      "rm -f /home/ubuntu/install"
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
resource "aws_cloudwatch_metric_alarm" "analytics_cpu" {
  alarm_name          = "alarmAnalyticsServerCPUUtilization"
  alarm_description   = "Analytics server CPU utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "${var.alarm_cpu_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.analytics.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "analytics_queue" {
  alarm_name          = "alarmAnalyticsServerDiskQueueDepth"
  alarm_description   = "Analytics server disk queue depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DiskQueueDepth"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_disk_queue_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.analytics.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "analytics_disk_free" {
  alarm_name          = "alarmAnalyticsServerFreeStorageSpace"
  alarm_description   = "Analytics server free storage space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_free_disk_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.analytics.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}

resource "aws_cloudwatch_metric_alarm" "analytics_memory_free" {
  alarm_name          = "alarmAnalyticsServerFreeableMemory"
  alarm_description   = "Analytics server freeable memory"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "60"
  statistic           = "Average"
  threshold           = "${var.alarm_free_memory_threshold}"
  count               = "${var.instance_count}"
  dimensions {
    InstanceIdentifier = "${element(aws_instance.analytics.*.id, count.index)}"
  }

  alarm_actions = ["${var.alarm_actions}"]
}
*/


/* Map all DNS records to ELB */
resource "aws_route53_record" "rr_analytics" {
  zone_id = "${var.route53_internal_zone_id}"
  name = "${var.host}"
  #ttl = "300"
  type = "A"
    alias {
    name                   = "${aws_elb.elb_analytics.dns_name}"
    zone_id                = "${aws_elb.elb_analytics.zone_id}"
    evaluate_target_health = true
  }
}
