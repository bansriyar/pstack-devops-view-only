# AWS access key
variable "access_key" {
  default = "somekey"
}
# AWS secret key
variable "secret_key" {
  default = "somekey"
}
# AWS availability zone
variable "availability_zone" {
  default = "ap-south-1"
}

variable "availability_zone_a" {
  default = "ap-south-1a"
}

variable "availability_zone_b" {
  default = "ap-south-1b"
}

# AWS account id
variable "account_id" {
  default = "someid"
}

variable "key_name_access_animesh" {
  default = "somename"
}

# IAM Name
variable "pstack_infra_iam_name" {
  default = "some name"
}
# Codedeploy role
variable "pstack_codedeploy_iam_role" {
  default = "some role"
}

variable "pstack_ec2_iam_role" {
  default = "pstack_ec2"
}

# VPC CIDRs
variable "vpc_production_cidr" {
  default = "10.1.0.0/16"
}

variable "vpc_management_cidr" {
  default = "10.2.1.0/24"
}

# Define S3 Bucket Names
variable "s3_buckets_map" {
  description = "Map for different S3 buckets"
  type = "map"
  default = {
    "elasticache_bucket_name" = "pstack-elasticache"
    "rsearch_es_bucket_name" = "pstack-rsearch-es"
    "analytics_es_bucket_name" = "pstack-analytics-es"
    "cloudtrail_bucket_name" = "pstack-cloudtrail"
    "codedeploy_bucket_name" = "pstack-codedeploy"
  }
}


# Define management CIDRs
variable "mgmt_subnet_cidrs_map" {
  description = "CIDRs for differnet subnets in Management"
  type = "map"
  default = {
    "mgmt_access" = "10.1.1.0/24"
  }
}

# Define production CIDRs
variable "prod_subnet_cidrs_map" {
  description = "CIDRs for different subnets in Production"
  type = "map"
  default = {
    "pstack_web_nginx" = "10.1.11.0/24"
    "pstack_web_nodejs" = "10.1.12.0/24"
    "rsearch_web" = "10.1.21.0/24"
    "rsearch_es" = "10.1.22.0/24"
    "cust_auth_mysql_a" = "10.1.31.0/24"
    "cust_auth_mysql_b" = "10.1.32.0/24"
    "cust_auth_redis" = "10.1.33.0/24"
    "analytics" = "10.1.41.0/24"
    "pstack_web_nginx_public" = "10.1.101.0/24"
    "rsearch_web_public" = "10.1.102.0/24"
  }
}

# Define production CIDRs needing NAT routes
variable "prod_subnet_cidrs_nat_map" {
  description = "CIDRs for different subnets in Production"
  type = "map"
  default = {
    "pstack_web_nginx" = "10.1.11.0/24"
    "pstack_web_nodejs" = "10.1.12.0/24"
    "rsearch_web" = "10.1.21.0/24"
    "rsearch_es" = "10.1.22.0/24"
    "analytics" = "10.1.41.0/24"
  }
}

variable "pstack_web_nginx_ips_map" {
  type = "map"
  default = {
    "0" = "10.1.11.10"
    "1" = "10.1.11.11"
    "2" = "10.1.11.12"
    "3" = "10.1.11.13"
  }
}


variable "pstack_web_nodejs_ips_map" {
  type = "map"
  default = {
    "0" = "10.1.12.10"
    "1" = "10.1.12.11"
    "2" = "10.1.12.12"
    "3" = "10.1.12.13"
  }
}

variable "rsearch_web_ips_map" {
  type = "map"
  default = {
    "0" = "10.1.21.10"
    "1" = "10.1.21.11"
    "2" = "10.1.21.12"
    "3" = "10.1.21.13"
  }
}

variable "rsearch_es_ips_map" {
  type = "map"
  default = {
    "0" = "10.1.22.10"
    "1" = "10.1.22.11"
    "2" = "10.1.22.12"
    "3" = "10.1.22.13"

  }
}

variable "analytics_ips_map" {
  type = "map"
  default = {
    "0" = "10.1.41.10"
    "1" = "10.1.41.11"
    "2" = "10.1.41.12"
    "3" = "10.1.41.13"
  }
}

/* Cloudtrail logging */
/* CloudWatch logging */

/* AWS Instances */
# Define aws_instance requirements for pstack_web_nginx
# AMI is Ubuntu 16.04 LTS Server
variable "pstack_web_nginx_map" {
  description = "List of variables for pstack_web_nginx"
  type = "map"
  default = {
    "var_ami" = "ami-49e59a26"
    "var_instance_type" = "t2.small"
    "var_instance_count" = 2

  }
}

# Internal and External domain definitions
variable "external_domain" { default = "somedomain.com"}
variable "internal_domain" { default = "awsmum.somedomain-internal.com"}

# External domain host definitions
variable "external_domain_hosts_map" {
  description = "Hosts which will need an external DNS"
  type = "map"
  default = {
    "mgmt_access"                 = "ac1.somedomain.com"
    "mgmt_ci_server"              = "ac2.somedomain.com"
    "pstack_web_nginx_mainsite"   = "www.somedomain.com"
    "pstack_web_nginx_domain"     = "somedomain.com"
    "pstack_web_nginx_dashboard"  = "dashboard.somedomain.com"
    "pstack_web_nginx_developer"  = "developer.somedomain.com"
    "pstack_web_nginx_blog"       = "blog.somedomain.com"
    "pstack_web_nginx_web_api"    = "web-api.somedomain.com"
    "rsearch_web"                 = "api.somedomain.com"
  }
}

# Internal Domain Host Definitions
variable "internal_domain_hosts_map" {
  description = "Hosts which will need an internal DNS"
  type = "map"
  default = {
    "rsearch_es"        = "rsearch-es.awsmum.somedomain-internal.com"
    "pstack_web_nodejs" = "pstack-web-nodejs.awsmum.somedomain-internal.com"
    "cust_auth_redis"   = "cust-auth-redis.awsmum.somedomain-internal.com"
    "cust_auth_mysql"   = "cust-auth-mysql.awsmum.somedomain-internal.com"
    "analytics"         = "analytics.awsmum.somedomain-internal.com"
  }
}

# SNS Topics
variable "sns_topics_list" {
  description = "All SNS Topics"
  type = "list"
  default = ["pstack_web_nginx", "pstack_web_nodejs", "cust_auth_mysql", "cust_auth_redis", "rsearch_web", "rsearch_es", "analytics"]
}

variable "sns_topics_list_count" {
  default = 7
}
