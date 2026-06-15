provider "aws" {

  region = "ap-southeast-1"

}


####################################
# Get AWS Account Information
####################################

data "aws_caller_identity" "current" {}



####################################
# S3 Bucket for CloudTrail
####################################

resource "aws_s3_bucket" "cloudtrail" {


  bucket = "security-cloudtrail-root-alert-logs"


}



####################################
# S3 Ownership
####################################

resource "aws_s3_bucket_ownership_controls" "cloudtrail" {


  bucket = aws_s3_bucket.cloudtrail.id


  rule {

    object_ownership = "BucketOwnerPreferred"

  }

}




####################################
# CloudTrail S3 Bucket Policy
####################################

resource "aws_s3_bucket_policy" "cloudtrail_policy" {


  bucket = aws_s3_bucket.cloudtrail.id



  policy = jsonencode({

    Version = "2012-10-17"


    Statement = [


      {

        Sid = "AWSCloudTrailAclCheck"


        Effect = "Allow"


        Principal = {

          Service = "cloudtrail.amazonaws.com"

        }


        Action = "s3:GetBucketAcl"


        Resource = aws_s3_bucket.cloudtrail.arn


      },


      {


        Sid = "AWSCloudTrailWrite"


        Effect = "Allow"


        Principal = {

          Service = "cloudtrail.amazonaws.com"

        }


        Action = "s3:PutObject"


        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"



        Condition = {


          StringEquals = {


            "s3:x-amz-acl" = "bucket-owner-full-control"


          }

        }

      }


    ]

  })

}




####################################
# CloudWatch Log Group
####################################

resource "aws_cloudwatch_log_group" "cloudtrail" {


  name = "/aws/cloudtrail/root-alert"


  retention_in_days = 30


}




####################################
# IAM Role CloudTrail -> CloudWatch
####################################


resource "aws_iam_role" "cloudtrail_role" {


  name = "CloudTrailToCloudWatchRole"



  assume_role_policy = jsonencode({


    Version = "2012-10-17"


    Statement = [


      {


        Effect = "Allow"


        Principal = {


          Service = "cloudtrail.amazonaws.com"


        }


        Action = "sts:AssumeRole"


      }


    ]

  })

}



####################################
# CloudTrail -> CloudWatch Policy
####################################

resource "aws_iam_role_policy" "cloudtrail_logs_policy" {


  name = "CloudTrailCloudWatchLogsPolicy"


  role = aws_iam_role.cloudtrail_role.id



  policy = jsonencode({


    Version = "2012-10-17"



    Statement = [


      {

        Effect = "Allow"



        Action = [


          "logs:CreateLogStream",


          "logs:PutLogEvents"



        ]



        Resource = "*"


      }


    ]

  })

}




####################################
# CloudTrail
####################################

resource "aws_cloudtrail" "security_trail" {


  name = "SecurityRootLoginTrail"



  s3_bucket_name = aws_s3_bucket.cloudtrail.id



  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"



  cloud_watch_logs_role_arn = aws_iam_role.cloudtrail_role.arn



  include_global_service_events = true



  is_multi_region_trail = true



  enable_log_file_validation = true



  depends_on = [

    aws_iam_role_policy.cloudtrail_logs_policy,

    aws_s3_bucket_policy.cloudtrail_policy

  ]

}




####################################
# SNS Topic
####################################

resource "aws_sns_topic" "security_alert" {


  name = "SecurityAlertTopic"


}





####################################
# SNS Email Subscription
####################################

resource "aws_sns_topic_subscription" "email" {


  topic_arn = aws_sns_topic.security_alert.arn



  protocol = "email"



  endpoint = var.email


}




####################################
# CloudWatch Metric Filter
####################################

resource "aws_cloudwatch_log_metric_filter" "root_login" {


  name = "RootAccountLoginFilter"



  log_group_name = aws_cloudwatch_log_group.cloudtrail.name



  pattern = "{ $.userIdentity.type = \"Root\" && $.eventType != \"AwsServiceEvent\" }"



  metric_transformation {


    name = "RootAccountLoginCount"


    namespace = "Security"


    value = "1"


  }


}





####################################
# CloudWatch Alarm
####################################

resource "aws_cloudwatch_metric_alarm" "root_login_alarm" {


  alarm_name = "RootAccountLoginAlert"



  alarm_description = "Alert when AWS Root Account login detected"



  namespace = "Security"



  metric_name = "RootAccountLoginCount"



  statistic = "Sum"



  period = 300



  evaluation_periods = 1



  threshold = 1



  comparison_operator = "GreaterThanOrEqualToThreshold"



  alarm_actions = [

    aws_sns_topic.security_alert.arn

  ]

}