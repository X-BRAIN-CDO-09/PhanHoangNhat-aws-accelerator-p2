output "sns_topic" {

 value = aws_sns_topic.security_alert.arn

}


output "cloudtrail_name" {

 value = aws_cloudtrail.security_trail.name

}