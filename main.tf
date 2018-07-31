provider "aws" {
  region  = "us-west-2"
}

resource "aws_iam_role" "example" {
  name = "${var.deploy_name}-codebuild-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "example" {
  role = "${aws_iam_role.example.name}"

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Resource": [
                "*"
            ],
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ]
        },
        {
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::codepipeline-us-west-2-*"
            ],
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:GetObjectVersion"
            ]
        },
        {
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::terraform-state-*"
            ],
            "Action": [
                "s3:GetObject",
                "s3:GetObjectVersion"
            ]
        },
        {
            "Effect": "Allow",
            "Resource": [
                "*"
            ],
            "Action": [
                "cloudwatch:*"
            ]
        }
    ]
}
POLICY
}


resource "aws_codebuild_project" "project" {
  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/golang:1.10"
    type         = "LINUX_CONTAINER"
  }

  name          = "${var.deploy_name}-github-project"

  source {
    type            = "GITHUB"
    location        = "${var.github_repo}"
    git_clone_depth = "25"

    buildspec = <<SPEC
version: 0.2
phases:
  install:
    commands:
      - cd /tmp && curl -o terraform.zip https://releases.hashicorp.com/terraform/${var.terraform_version}/terraform_${var.terraform_version}_linux_amd64.zip && echo "${var.terraform_sha256} terraform.zip" | sha256sum -c --quiet && unzip terraform.zip && mv terraform /usr/bin
  build:
    commands:
      - cd $CODEBUILD_SRC_DIR
      - env
      - git status
      - git log
      - cat README.md
      - terraform init
      - errorcode=$(terraform plan -detailed-exitcode > /dev/null 2>&1; echo $?)
      - echo $errorcode
      - aws cloudwatch put-metric-data --metric-name TerraformPlanResponseCode --namespace BuildPipeline --value $errorcode --dimensions ProjectName=${var.project_friendly_name}
SPEC
  }

  service_role = "${aws_iam_role.example.arn}"
}

resource "aws_cloudwatch_metric_alarm" "plan_failure_alarm" {
  alarm_name          = "${var.deploy_name}-plan-failure-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "TerraformPlanResponseCode"
  namespace           = "BuildPipeline"
  period              = "${var.check_frequency * 60}"
  statistic           = "Maximum"
  threshold           = "1"
  datapoints_to_alarm = "2"
  treat_missing_data  = "breaching"
}

resource "aws_iam_role" "iam_lambda_role" {
  name = "${var.deploy_name}-iam-lambda-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.deploy_name}-iam-lambda-policy"
  role = "${aws_iam_role.iam_lambda_role.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "codebuild:StartBuild"
      ],
      "Effect": "Allow",
      "Resource": "${aws_codebuild_project.project.id}"
    }
  ]
}
EOF
}


resource "aws_lambda_function" "exec_lambda" {
  filename         = "lambda_function_payload.zip"
  function_name    = "${var.deploy_name}-lambda-executor"
  role             = "${aws_iam_role.iam_lambda_role.arn}"
  handler          = "lambda_function.lambda_handler"
  source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  runtime          = "python3.6"
}

resource "aws_cloudwatch_event_rule" "cron_rule" {
    name = "every-X-minutes"
    description = "Fires every X minutes"
    schedule_expression = "rate(${var.check_frequency} minutes)"
}

resource "aws_cloudwatch_event_target" "event_lambda_target" {
    rule = "${aws_cloudwatch_event_rule.cron_rule.name}"
    target_id = "exec_lambda"
    arn = "${aws_lambda_function.exec_lambda.arn}"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.exec_lambda.function_name}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.cron_rule.arn}"
}
