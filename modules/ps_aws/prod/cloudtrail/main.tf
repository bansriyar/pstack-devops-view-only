
# Setup entire DNS process

# External Definitions

variable "vpc_id" {}
variable "iam_user_name" {}
variable "cloudtrail_bucket_name" {}
variable "cloudtrail_log" {}


# S3 bucket for Cloudtrail
resource "aws_s3_bucket" "cloudtrail_bucket" {
  bucket = "${var.cloudtrail_bucket_name}"
  acl    = "private"

  versioning {
    enabled = true
  }
  lifecycle_rule {
    id      = "${var.cloudtrail_bucket_name}"
    enabled = true
    prefix  = "${var.cloudtrail_bucket_name}/"
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

resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = "${aws_s3_bucket.cloudtrail_bucket.id}"
  policy =<<POLICY
{
      "Version": "2012-10-17",
      "Statement": [
          {
              "Sid": "AWSCloudTrailAclCheck20150319",
              "Effect": "Allow",
              "Principal": {"Service": "cloudtrail.amazonaws.com"},
              "Action": "s3:GetBucketAcl",
              "Resource": "arn:aws:s3:::pstack-cloudtrail"
          },
          {
              "Sid": "AWSCloudTrailWrite20150319",
              "Effect": "Allow",
              "Principal": {"Service": "cloudtrail.amazonaws.com"},
              "Action": "s3:PutObject",
              "Resource": "arn:aws:s3:::pstack-cloudtrail/*",
              "Condition": {"StringEquals": {"s3:x-amz-acl": "bucket-owner-full-control"}}
          }
      ]
}
POLICY
}

resource "aws_cloudtrail" "ps_cloudtrail" {
  name                          = "${var.cloudtrail_log}"
  s3_bucket_name                = "${var.cloudtrail_bucket_name}"
  s3_key_prefix                 = "prefix"
  include_global_service_events = false
}
