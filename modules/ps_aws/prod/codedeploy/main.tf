variable "codedeploy_app" {}
variable "codedeploy_iam_role_arn" {}
variable "codedeploy_group" {}
variable "ec2_tag_filter_name" {}
variable "codedeploy_deployment_config_name" {}

resource "aws_codedeploy_app" "codedeploy_app" {
  name = "${var.codedeploy_app}"
}

resource "aws_codedeploy_deployment_config" "codedeploy_deployment_config" {
  deployment_config_name = "${var.codedeploy_deployment_config_name}"

  minimum_healthy_hosts {
    type  = "HOST_COUNT"
    value = 1
  }
}

resource "aws_codedeploy_deployment_group" "codedeploy_group" {
  app_name              = "${aws_codedeploy_app.codedeploy_app.name}"
  deployment_group_name = "${var.codedeploy_group}"
  service_role_arn      = "${var.codedeploy_iam_role_arn}"
  deployment_config_name = "${var.codedeploy_deployment_config_name}"

  ec2_tag_filter {
    key   = "CodeDeploy"
    type  = "KEY_AND_VALUE"
    value = "${var.ec2_tag_filter_name}"
  }

#  trigger_configuration {
#    trigger_events     = ["DeploymentFailure"]
#    trigger_name       = "rsearch-web-trigger"
#    trigger_target_arn = "rsearch-web-topic-arn"
#  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

#  alarm_configuration {
#    alarms  = ["pstack-alarm-name"]
#    enabled = true
#  }
}
