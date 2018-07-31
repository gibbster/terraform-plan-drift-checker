import boto3

def lambda_handler(event, context):
    client = boto3.client('codebuild')
    response = client.start_build(projectName='codebuild-tf-plan-github-project')
    return 'Hello from Lambda'
