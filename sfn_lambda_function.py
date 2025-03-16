import json
import boto3

sfn_client = boto3.client("stepfunctions")

STEP_FUNCTION_ARN = "arn:aws:states:us-east-1:713881815454:stateMachine:my-step-function"

def lambda_handler(event, context):
    # Extract file details from S3 event
    s3_event = event["Records"][0]
    bucket_name = s3_event["s3"]["bucket"]["name"]
    file_key = s3_event["s3"]["object"]["key"]

    # Trigger the Step Function execution
    response = sfn_client.start_execution(
        stateMachineArn=STEP_FUNCTION_ARN,
        input=json.dumps({"bucket": bucket_name, "file": file_key})
    )

    print("Step Function started:", response["executionArn"])
    return {"status": "Step Function triggered"}
