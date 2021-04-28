provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region = "${var.availability_zone}"
}

/*data "terraform_remote_state" "network" {
  backend = "s3"
  config {
    bucket = "pstack-terraform-remote-state"
    key    = "terraform.tfstate"
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
    region = "${var.availability_zone}"
  }
}*/

#resource "aws_iam_user" "pstack_infra_iam" {
#  name = "${var.pstack_infra_iam_name}"
#}

resource "aws_key_pair" "ubuntu_pstack_deploy_key_public" {
  key_name   = "ubuntu_pstack_deploy_key_public"
  public_key = "${file("resources/keys/ubuntu_pstack_deploy_id_rsa.pub")}"
}

/* Define VPC Production */
resource "aws_vpc" "production_vpc" {
  cidr_block            = "${var.vpc_production_cidr}"
  enable_dns_support    = true
  enable_dns_hostnames  = true
  tags {
    Name = "Production VPC"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "production_gw" {
  vpc_id = "${aws_vpc.production_vpc.id}"
  tags {
    Name = "Production VPC GW"
  }
}
/* */

/* Set DNS */
module "dns" {
  source = "modules/ps_aws/prod/dns"
  vpc_id = "${aws_vpc.production_vpc.id}"
  external_domain = "${var.external_domain}"
  internal_domain = "${var.internal_domain}"
}
/* */

/* Setup S3 */
module "s3" {
  source = "modules/ps_aws/prod/s3"
  vpc_id = "${aws_vpc.production_vpc.id}"
  elasticache_bucket_name = "${lookup(var.s3_buckets_map, "elasticache_bucket_name")}"
  rsearch_es_bucket_name = "${lookup(var.s3_buckets_map, "rsearch_es_bucket_name")}"
  analytics_es_bucket_name = "${lookup(var.s3_buckets_map, "analytics_es_bucket_name")}"
  codedeploy_bucket_name = "${lookup(var.s3_buckets_map, "codedeploy_bucket_name")}"
}
/* */

/* Setup Cloudtrail */
module "cloudtrail" {
  source = "modules/ps_aws/prod/cloudtrail"
  vpc_id = "${aws_vpc.production_vpc.id}"
  cloudtrail_log = "ps_cloudtrail_log"
  cloudtrail_bucket_name = "${lookup(var.s3_buckets_map, "cloudtrail_bucket_name")}"
  iam_user_name = "${var.pstack_infra_iam_name}"
}
/* */

/* AWS Instances */
# mgmt_access
module "mgmt_access" {
  source = "modules/ps_aws/mgmt/instance_groups/access"
  name = "mgmt_access"
  mgmt_subnet_cidrs_map = "${var.mgmt_subnet_cidrs_map}"
  prod_subnet_cidrs_map = "${var.prod_subnet_cidrs_map}"
  vpc_id = "${aws_vpc.production_vpc.id}"
  availability_zone = "${var.availability_zone_a}"
  internet_gw = "${aws_internet_gateway.production_gw.id}"
  route53_external_zone_id = "${module.dns.route53_external_zone_id}"
  host_access = "${lookup(var.external_domain_hosts_map, "mgmt_access")}"
  access_key_name = "${aws_key_pair.ubuntu_pstack_deploy_key_public.key_name}"
}

# Setting up NAT Gateway and respective Routes
resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = "${aws_eip.nat_eip.id}"
  subnet_id     = "${module.mgmt_access.subnet_mgmt_access_id}"
  depends_on    = ["aws_internet_gateway.production_gw"]
  tags {
    Name = "NAT gw"
  }
}
/* */

/* Setup IAM Role for EC2 Instances */
# Create code deploy iam_role
resource "aws_iam_role" "ec2_role_name" {
  name = "${var.pstack_ec2_iam_role}"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": [
            "codedeploy.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        },
        "Action": "sts:AssumeRole"
      }
    ]
}
EOF
}

resource "aws_iam_role_policy" "ec2_role_name_policy" {
  name = "ec2_role_name_policy"
  role = "${aws_iam_role.ec2_role_name.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "ec2:*",
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name  = "ec2_profile"
  role = "${aws_iam_role.ec2_role_name.name}"
}

# cust_auth_mysql
module "cust_auth_mysql" {
  source = "modules/ps_aws/prod/instance_groups/cust_auth_mysql"
  name = "pstack-cust_auth_mysql"
  prod_subnet_cidrs_map = "${var.prod_subnet_cidrs_map}"
  mgmt_subnet_cidrs_map = "${var.mgmt_subnet_cidrs_map}"
  vpc_id = "${aws_vpc.production_vpc.id}"
  availability_zone_a = "${var.availability_zone_a}"
  availability_zone_b = "${var.availability_zone_b}"
  route53_internal_zone_id = "${module.dns.route53_internal_zone_id}"
  host = "${lookup(var.internal_domain_hosts_map, "cust_auth_mysql")}"
  alarm_actions = "arn:aws:events:${var.availability_zone}:*:*"
  access_key_name = "${aws_key_pair.ubuntu_pstack_deploy_key_public.key_name}"
}

# cust_auth_redis
module "cust_auth_redis" {
  source = "modules/ps_aws/prod/instance_groups/cust_auth_redis"
  name = "pstack-cust_auth_redis"
  prod_subnet_cidrs_map = "${var.prod_subnet_cidrs_map}"
  mgmt_subnet_cidrs_map = "${var.mgmt_subnet_cidrs_map}"
  vpc_id = "${aws_vpc.production_vpc.id}"
  availability_zone = "${var.availability_zone_a}"
  route53_internal_zone_id = "${module.dns.route53_internal_zone_id}"
  host = "${lookup(var.internal_domain_hosts_map, "cust_auth_redis")}"
  alarm_actions = "arn:aws:events:${var.availability_zone}:*:*"
  snapshot_arns = "arn:aws:s3:::pstack_elasticache/redis_backup.rdb"
  access_key_name = "${aws_key_pair.ubuntu_pstack_deploy_key_public.key_name}"
}

# pstack_web_nginx
module "pstack_web_nginx" {
  source = "modules/ps_aws/prod/instance_groups/pstack_web_nginx"
  name = "pstack-web-nginx"
  prod_subnet_cidrs_map = "${var.prod_subnet_cidrs_map}"
  mgmt_subnet_cidrs_map = "${var.mgmt_subnet_cidrs_map}"
  vpc_id = "${aws_vpc.production_vpc.id}"
  nat_gw_id = "${aws_nat_gateway.nat_gw.id}"
  internet_gw = "${aws_internet_gateway.production_gw.id}"
  availability_zone = "${var.availability_zone_a}"
  route53_external_zone_id = "${module.dns.route53_external_zone_id}"
  host_mainsite = "${lookup(var.external_domain_hosts_map, "pstack_web_nginx_mainsite")}"
  host_domain = "${lookup(var.external_domain_hosts_map, "pstack_web_nginx_domain")}"
  host_dashboard = "${lookup(var.external_domain_hosts_map, "pstack_web_nginx_dashboard")}"
  host_developer = "${lookup(var.external_domain_hosts_map, "pstack_web_nginx_developer")}"
  host_blog = "${lookup(var.external_domain_hosts_map, "pstack_web_nginx_blog")}"
  host_web_api = "${lookup(var.external_domain_hosts_map, "pstack_web_nginx_web_api")}"
  sns_topic = "pstack_web_nginx"
  access_key_name = "${aws_key_pair.ubuntu_pstack_deploy_key_public.key_name}"
  ps_bastion_host = "${module.mgmt_access.mgmt_access_ip}"
  ec2_profile_name = "${aws_iam_instance_profile.ec2_profile.name}"
  ips_map = "${var.pstack_web_nginx_ips_map}"
  root_block_size = 12
}


# pstack_web_nodejs
module "pstack_web_nodejs" {
  source = "modules/ps_aws/prod/instance_groups/pstack_web_nodejs"
  name = "pstack-web-nodejs"
  prod_subnet_cidrs_map = "${var.prod_subnet_cidrs_map}"
  mgmt_subnet_cidrs_map = "${var.mgmt_subnet_cidrs_map}"
  vpc_id = "${aws_vpc.production_vpc.id}"
  nat_gw_id = "${aws_nat_gateway.nat_gw.id}"
  availability_zone = "${var.availability_zone_a}"
  route53_internal_zone_id = "${module.dns.route53_internal_zone_id}"
  host = "${lookup(var.internal_domain_hosts_map, "pstack_web_nodejs")}"
  alarm_actions = "arn:aws:events:${var.availability_zone}:*:*"
  access_key_name = "${aws_key_pair.ubuntu_pstack_deploy_key_public.key_name}"
  ps_bastion_host = "${module.mgmt_access.mgmt_access_ip}"
  ec2_profile_name = "${aws_iam_instance_profile.ec2_profile.name}"
  ips_map = "${var.pstack_web_nodejs_ips_map}"
  root_block_size = 20
}

# rsearch_web
module "rsearch_web" {
  source = "modules/ps_aws/prod/instance_groups/rsearch_web"
  name = "rsearch-web"
  prod_subnet_cidrs_map = "${var.prod_subnet_cidrs_map}"
  mgmt_subnet_cidrs_map = "${var.mgmt_subnet_cidrs_map}"
  vpc_id = "${aws_vpc.production_vpc.id}"
  nat_gw_id = "${aws_nat_gateway.nat_gw.id}"
  internet_gw = "${aws_internet_gateway.production_gw.id}"
  availability_zone = "${var.availability_zone_a}"
  route53_external_zone_id = "${module.dns.route53_external_zone_id}"
  host = "${lookup(var.external_domain_hosts_map, "rsearch_web")}"
  alarm_actions = "arn:aws:events:${var.availability_zone}:*:*"
  access_key_name = "${aws_key_pair.ubuntu_pstack_deploy_key_public.key_name}"
  ps_bastion_host = "${module.mgmt_access.mgmt_access_ip}"
  ec2_profile_name = "${aws_iam_instance_profile.ec2_profile.name}"
  ips_map = "${var.rsearch_web_ips_map}"
  root_block_size = 12
}

# rsearch_es
module "rsearch_es" {
  source = "modules/ps_aws/prod/instance_groups/rsearch_es"
  name = "rsearch-es"
  prod_subnet_cidrs_map = "${var.prod_subnet_cidrs_map}"
  mgmt_subnet_cidrs_map = "${var.mgmt_subnet_cidrs_map}"
  vpc_id = "${aws_vpc.production_vpc.id}"
  nat_gw_id = "${aws_nat_gateway.nat_gw.id}"
  availability_zone = "${var.availability_zone_a}"
  route53_internal_zone_id = "${module.dns.route53_internal_zone_id}"
  host = "${lookup(var.internal_domain_hosts_map, "rsearch_es")}"
  alarm_actions = "arn:aws:events:${var.availability_zone}:*:*"
  access_key_name = "${aws_key_pair.ubuntu_pstack_deploy_key_public.key_name}"
  ps_bastion_host = "${module.mgmt_access.mgmt_access_ip}"
  ec2_profile_name = "${aws_iam_instance_profile.ec2_profile.name}"
  ips_map = "${var.rsearch_es_ips_map}"
  root_block_size = 30
}


# analytics
module "analytics" {
  source = "modules/ps_aws/prod/instance_groups/analytics"
  name = "pstack-analytics"
  prod_subnet_cidrs_map = "${var.prod_subnet_cidrs_map}"
  mgmt_subnet_cidrs_map = "${var.mgmt_subnet_cidrs_map}"
  vpc_id = "${aws_vpc.production_vpc.id}"
  nat_gw_id = "${aws_nat_gateway.nat_gw.id}"
  availability_zone = "${var.availability_zone_a}"
  route53_internal_zone_id = "${module.dns.route53_internal_zone_id}"
  host = "${lookup(var.internal_domain_hosts_map, "analytics")}"
  alarm_actions = "arn:aws:events:${var.availability_zone}:*:*"
  access_key_name = "${aws_key_pair.ubuntu_pstack_deploy_key_public.key_name}"
  ps_bastion_host = "${module.mgmt_access.mgmt_access_ip}"
  ec2_profile_name = "${aws_iam_instance_profile.ec2_profile.name}"
  ips_map = "${var.analytics_ips_map}"
  root_block_size = 30
}

# Create code deploy iam_role
resource "aws_iam_role" "codedeploy_role_name" {
  name = "${var.pstack_codedeploy_iam_role}"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": [
            "codedeploy.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        },
        "Action": "sts:AssumeRole"
      }
    ]
}
EOF
}

resource "aws_iam_role_policy" "codedeploy_role_name_policy" {
  name = "codedeploy_role_name_policy"
  role = "${aws_iam_role.codedeploy_role_name.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "ec2:*",
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}


# Code deploy after all infrastructure is provisioned
# pstack_www
module "codedeploy_pstack_www" {
  source = "modules/ps_aws/prod/codedeploy"
  codedeploy_app = "pstack_www"
  codedeploy_iam_role_arn = "${aws_iam_role.codedeploy_role_name.arn}"
  codedeploy_group = "pstack_www"
  ec2_tag_filter_name = "pstack_www"
  codedeploy_deployment_config_name = "pstack_www_deployment_config"
}
# pstack_web_apis
module "codedeploy_pstack_web_apis" {
  source = "modules/ps_aws/prod/codedeploy"
  codedeploy_app = "pstack_web_apis"
  codedeploy_iam_role_arn = "${aws_iam_role.codedeploy_role_name.arn}"
  codedeploy_group = "pstack_web_apis"
  ec2_tag_filter_name = "pstack_www"
  codedeploy_deployment_config_name = "pstack_web_apis_deployment_config"
}

# pstack_blog
module "codedeploy_pstack_blog" {
  source = "modules/ps_aws/prod/codedeploy"
  codedeploy_app = "pstack_blog"
  codedeploy_iam_role_arn = "${aws_iam_role.codedeploy_role_name.arn}"
  codedeploy_group = "pstack_blog"
  ec2_tag_filter_name = "pstack_www"
  codedeploy_deployment_config_name = "pstack_blog_deployment_config"
}

# pstack_developer
module "codedeploy_pstack_developer" {
  source = "modules/ps_aws/prod/codedeploy"
  codedeploy_app = "pstack_developer"
  codedeploy_iam_role_arn = "${aws_iam_role.codedeploy_role_name.arn}"
  codedeploy_group = "pstack_developer"
  ec2_tag_filter_name = "pstack_www"
  codedeploy_deployment_config_name = "pstack_developer_deployment_config"
}
# pstack_dashboard
module "codedeploy_pstack_dashboard" {
  source = "modules/ps_aws/prod/codedeploy"
  codedeploy_app = "pstack_dashboard"
  codedeploy_iam_role_arn = "${aws_iam_role.codedeploy_role_name.arn}"
  codedeploy_group = "pstack_dashboard"
  ec2_tag_filter_name = "pstack_www"
  codedeploy_deployment_config_name = "pstack_dashboard_deployment_config"
}

# pstack_nginx
module "codedeploy_pstack_nginx" {
  source = "modules/ps_aws/prod/codedeploy"
  codedeploy_app = "pstack_nginx"
  codedeploy_iam_role_arn = "${aws_iam_role.codedeploy_role_name.arn}"
  codedeploy_group = "pstack_nginx"
  ec2_tag_filter_name = "pstack_www"
  codedeploy_deployment_config_name = "pstack_nginx_deployment_config"
}

# rsearch_web
module "codedeploy_rsearch_web" {
  source = "modules/ps_aws/prod/codedeploy"
  codedeploy_app = "rsearch_web"
  codedeploy_iam_role_arn = "${aws_iam_role.codedeploy_role_name.arn}"
  codedeploy_group = "rsearch_web"
  ec2_tag_filter_name = "rsearch_web"
  codedeploy_deployment_config_name = "rsearch_web_deployment_config"
}

# rsearch_es
module "codedeploy_rsearch_es" {
  source = "modules/ps_aws/prod/codedeploy"
  codedeploy_app = "rsearch_es"
  codedeploy_iam_role_arn = "${aws_iam_role.codedeploy_role_name.arn}"
  codedeploy_group = "rsearch_es"
  ec2_tag_filter_name = "rsearch_es"
  codedeploy_deployment_config_name = "rsearch_es_deployment_config"
}

# analytics
module "codedeploy_analytics" {
  source = "modules/ps_aws/prod/codedeploy"
  codedeploy_app = "analytics"
  codedeploy_iam_role_arn = "${aws_iam_role.codedeploy_role_name.arn}"
  codedeploy_group = "analytics"
  ec2_tag_filter_name = "analytics"
  codedeploy_deployment_config_name = "analytics_deployment_config"
}
#
