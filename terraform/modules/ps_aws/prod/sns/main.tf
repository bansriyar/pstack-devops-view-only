variable "sns_topics_list" {}
variable "sns_topics_list_count" {}

resource "aws_sns_topic" "sns_topic" {
  count = "${sns_topics_list_count}"
  name = "${element(var.sns_topics_list, count.index)}"
}

output "sns_topic_arns"{
  value = ["${aws_sns_topic.sns_topic.*.arn}"]
}
