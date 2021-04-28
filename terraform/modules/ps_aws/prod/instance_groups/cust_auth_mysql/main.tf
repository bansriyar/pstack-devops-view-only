
# Entire configuration for cust_auth_mysql group

variable "name" { default = "cust_auth_mysql"}
variable "ami" { default = "ami-49e59a26" }
variable "instance_type" { default = "db.t2.small" }
variable "instance_count" { default = 2 }
variable "vpc_id" {}
variable "availability_zone_a" {}
variable "availability_zone_b" {}
variable "access_key_name" {}
variable "prod_subnet_cidrs_map" { type = "map" }
variable "mgmt_subnet_cidrs_map" { type = "map" }

variable "host" { }
variable "route53_internal_zone_id" {}
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
resource "aws_subnet" "subnet_cust_auth_mysql_a" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone_a}"
  cidr_block = "${lookup(var.prod_subnet_cidrs_map, "cust_auth_mysql_a")}"
  tags {
    Name = "subnet-a-${var.name}"
    terraform = true
  }
  map_public_ip_on_launch = false
}

resource "aws_subnet" "subnet_cust_auth_mysql_b" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone_b}"
  cidr_block = "${lookup(var.prod_subnet_cidrs_map, "cust_auth_mysql_b")}"
  tags {
    Name = "subnet-b-${var.name}"
    terraform = true
  }
  map_public_ip_on_launch = false
}

/* Define Security Group */
resource "aws_security_group" "sg_cust_auth_mysql" {
  name = "sg_cust_auth_mysql"
  vpc_id = "${var.vpc_id}"
  description = "security group for main mysql service"
  ingress {
    to_port = 22
    from_port = 22
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.mgmt_subnet_cidrs_map, "mgmt_access")}"]
  }
  ingress {
    to_port = 3306
    from_port = 3306
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "pstack_web_nodejs")}"]
  }
  tags {
    Name = "MySql Security Group"
  }
}

resource "aws_db_subnet_group" "subnet_cust_auth_mysql_db" {
  name       = "subnet_cust_auth_mysql_db"
  subnet_ids = ["${aws_subnet.subnet_cust_auth_mysql_a.id}", "${aws_subnet.subnet_cust_auth_mysql_b.id}"]

  tags {
    Name = "DB subnet group"
  }
}

/* Configure Instances */
resource "aws_db_instance" "cust_auth_mysql" {
#  availability_zone    = "${var.availability_zone}"
  allocated_storage    = 10
  storage_type         = "standard"
  engine               = "mysql"
  engine_version       = "5.7"
  final_snapshot_identifier = "cust-auth-mysql-final-snapshot"
  skip_final_snapshot  = false
  backup_window        = "02:00-03:00"
  maintenance_window   = "Mon:04:00-Mon:05:00"
  backup_retention_period = 7
  port                 = 3306
  instance_class       = "${var.instance_type}"
  name                 = "pstack_db"
  username             = "pstack"
  password             = "PstacK1010$"
  db_subnet_group_name = "subnet_cust_auth_mysql_db"
  vpc_security_group_ids = ["${aws_security_group.sg_cust_auth_mysql.id}"]
}

/* Map DNS to ELB */
resource "aws_route53_record" "rr_cust_auth_mysql" {
  zone_id = "${var.route53_internal_zone_id}"
  name = "${var.host}"
  #ttl = "300"
  type = "A"
    alias {
      name            = "${aws_db_instance.cust_auth_mysql.address}"
      zone_id         = "${aws_db_instance.cust_auth_mysql.hosted_zone_id}"
      evaluate_target_health = true
    }
}
