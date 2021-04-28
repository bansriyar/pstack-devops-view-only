
# Entire configuration for cust_auth_redis group

variable "name" { default = "cust_auth_redis"}
variable "ami" { default = "ami-49e59a26" }
variable "instance_type" { default = "t2.small" }
variable "instance_count" { default = 2 }
variable "vpc_id" {}
variable "availability_zone" {}
variable "access_key_name" {}
variable "prod_subnet_cidrs_map" { type = "map" }
variable "mgmt_subnet_cidrs_map" { type = "map" }

variable "host" { }
variable "route53_internal_zone_id" {}
variable "alarm_cpu_threshold" {
  default = "75"
}
variable "alarm_free_memory_threshold" {
  default = "128000000"
}
variable "alarm_actions" {
  default = ""
}
variable "snapshot_arns" {}


/* Define subnet */
resource "aws_subnet" "subnet_cust_auth_redis" {
  vpc_id = "${var.vpc_id}"
  availability_zone = "${var.availability_zone}"
  cidr_block = "${lookup(var.prod_subnet_cidrs_map, "cust_auth_redis")}"
  tags {
    Name = "subnet-${var.name}"
    terraform = true
  }
}

/* Define Security Group */
resource "aws_security_group" "sg_cust_auth_redis" {
  name = "sg_cust_auth_redis"
  vpc_id = "${var.vpc_id}"
  description = "security group for redis customer authentication"
  ingress {
    to_port = 22
    from_port = 22
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.mgmt_subnet_cidrs_map, "mgmt_access")}"]
  }
  ingress {
    to_port = 6379
    from_port = 6379
    protocol = "tcp"
    cidr_blocks = ["${lookup(var.prod_subnet_cidrs_map, "pstack_web_nodejs")}", "${lookup(var.prod_subnet_cidrs_map, "rsearch_web")}"]
  }
  tags {
    Name = "Redis Security Group"
  }
}

resource "aws_elasticache_subnet_group" "subnet_cust_auth_redis_ec" {
  name       = "subnet-cust-auth-redis-ec"
  subnet_ids = ["${aws_subnet.subnet_cust_auth_redis.id}"]
}
/* */

/* Configure Instances */
resource "aws_elasticache_cluster" "cust_auth_redis" {
  cluster_id           = "cust-auth-redis"
  #availability_zone    = "${var.availability_zone}"
  engine               = "redis"
  node_type            = "cache.t2.micro"
  port                 = 6379
  num_cache_nodes      = 1
  maintenance_window   = "Mon:04:00-Mon:05:00"
  #snapshot_arns        = ["${var.snapshot_arns}"]
  #snapshot_window      = "02:00-03:00"
  #snapshot_retention_limit = 7
  subnet_group_name    = "${aws_elasticache_subnet_group.subnet_cust_auth_redis_ec.name}"
  security_group_ids   = ["${aws_security_group.sg_cust_auth_redis.id}"]
}

#
# CloudWatch resources
#

/* Map DNS to ELB */
resource "aws_route53_record" "rr_cust_auth_redis" {
  zone_id = "${var.route53_internal_zone_id}"
  name = "${var.host}"
  type = "CNAME"
  ttl     = "300"
  records = ["${aws_elasticache_cluster.cust_auth_redis.cache_nodes.0.address}"]
}
