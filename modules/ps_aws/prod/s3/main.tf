
# Setup entire DNS process

# External Definitions

variable "vpc_id" {}
variable "elasticache_bucket_name" {}
variable "rsearch_es_bucket_name" {}
variable "analytics_es_bucket_name" {}
variable "codedeploy_bucket_name" {}


# S3 bucket for ElastiCache
resource "aws_s3_bucket" "elasticache_bucket" {
  bucket = "${var.elasticache_bucket_name}"
  acl    = "private"
  versioning {
    enabled = true
  }
  lifecycle_rule {
    id      = "${var.elasticache_bucket_name}"
    enabled = true
    prefix  = "${var.elasticache_bucket_name}/"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 60
      storage_class = "GLACIER"
    }
    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "elasticache_bucket_policy" {
  bucket = "${aws_s3_bucket.elasticache_bucket.id}"
  policy =<<POLICY
{
  "Version": "2012-10-17",
  "Id": "ElasticCachePolicy",
  "Statement": [
    {
      "Principal": "*",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::pstack-elasticache/*"
    }
  ]
}
POLICY
}


# S3 bucket for Main ES backup
resource "aws_s3_bucket" "rsearch_es_bucket" {
  bucket = "${var.rsearch_es_bucket_name}"
  acl    = "private"
  versioning {
    enabled = true
  }
  lifecycle_rule {
    id      = "${var.rsearch_es_bucket_name}"
    enabled = true
    prefix  = "${var.rsearch_es_bucket_name}/"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 60
      storage_class = "GLACIER"
    }
    expiration {
      days = 180
    }
  }
}

resource "aws_s3_bucket_policy" "rsearch_es_bucket_policy" {
  bucket = "${aws_s3_bucket.rsearch_es_bucket.id}"
  policy =<<POLICY
{
  "Version": "2012-10-17",
  "Id": "RSearchESPolicy",
  "Statement": [
    {
      "Principal": "*",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::pstack-rsearch-es/*"
    }
  ]
}
POLICY
}

# S3 bucket for Analytics ES backup
resource "aws_s3_bucket" "analytics_es_bucket" {
  bucket = "${var.analytics_es_bucket_name}"
  acl    = "private"
  versioning {
    enabled = true
  }
  lifecycle_rule {
    id      = "${var.analytics_es_bucket_name}"
    enabled = true
    prefix  = "${var.analytics_es_bucket_name}/"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 60
      storage_class = "GLACIER"
    }
    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "analytics_es_bucket_policy" {
  bucket = "${aws_s3_bucket.analytics_es_bucket.id}"
  policy =<<POLICY
{
  "Version": "2012-10-17",
  "Id": "AnalyticsESPolicy",
  "Statement": [
    {
      "Principal": "*",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::pstack-analytics-es/*"
    }
  ]
}
POLICY
}

# S3 bucket for Analytics ES backup
resource "aws_s3_bucket" "codedeploy_bucket" {
  bucket = "${var.codedeploy_bucket_name}"
  acl    = "private"
  versioning {
    enabled = true
  }
  lifecycle_rule {
    id      = "${var.codedeploy_bucket_name}"
    enabled = true
    prefix  = "${var.codedeploy_bucket_name}/"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 60
      storage_class = "GLACIER"
    }
    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "codedeploy_bucket_policy" {
  bucket = "${aws_s3_bucket.codedeploy_bucket.id}"
  policy =<<POLICY
{
  "Version": "2012-10-17",
  "Id": "CodeDeployPolicy",
  "Statement": [
    {
      "Principal": "*",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::pstack-codedeploy/*"
    }
  ]
}
POLICY
}
