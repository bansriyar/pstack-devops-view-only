
# Setup entire DNS process

# External Definitions

variable "vpc_id" {}
variable "external_domain" { }
variable "internal_domain" { }
variable "main_site_a" { default = "www.somedomain.com" }
variable "main_site_web_api_a" { default = "web-api.somedomain.com" }
variable "rsearch_api_a" { default = "api.somedomain.com" }

resource "aws_route53_zone" "external" {
  #disabled as it's external
  # vpc_id = "${var.vpc_id}"
  name = "${var.external_domain}"
}

resource "aws_route53_zone" "internal" {
  vpc_id = "${var.vpc_id}"
  name = "${var.internal_domain}"
}

#resource "aws_route53_zone_association" "secondary" {
#  zone_id = "${aws_route53_zone.internal.zone_id}"
#  vpc_id  = "${var.vpc_id}"
#}

# Add MX Records
resource "aws_route53_record" "root_mx" {
    zone_id = "${aws_route53_zone.external.zone_id}"
    name = "${var.external_domain}"
    type = "MX"
    ttl = "3600"
    records = ["1 ASPMX.L.GOOGLE.COM.", "5 ALT1.ASPMX.L.GOOGLE.COM.",
      "5 ALT2.ASPMX.L.GOOGLE.COM.", "10 ASPMX2.GOOGLEMAIL.COM.", "10 ASPMX3.GOOGLEMAIL.COM."]
}

output "route53_external_zone_id" {
  value = "${aws_route53_zone.external.zone_id}"
}

output "route53_internal_zone_id" {
  value = "${aws_route53_zone.internal.zone_id}"
}
