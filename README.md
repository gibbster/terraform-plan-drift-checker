# Terraform state checker

Despite setting up a beautiful CI/CD pipeline that builds your infrastructure from terraform, do you ever wonder if some sneaky guy went behind your back and updated something directly in the AWS console (or via the CLI, etc.)? 

Besides ignoring all your hard work in setting up the pipeline, this can be troublesome for two reasons:
 1. The next time the pipeline runs, terraform will merrily revert the change that was done in the console. That might reintroduce a bug that an ops guy fixed at 2am, causing frustration all round.
 2. If changes are happening outside of the regular pipeline, it means that the real state and the intended state will start to drift. At worst, things will break and people will give up on this silly IaC idea.

This tool is intended to fix this. It works by regularly running terraform plan in a codebuild container and reporting the terraform plan status to a custom cloudwatch metric. A cloudwatch alarm listens to this metric, going to ALARM state if it's nonzero for 2 periods (out of 3).

TODO: proper documentation
