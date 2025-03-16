import boto3
import json
import time

kinesis_client = boto3.client("kinesis", region_name="us-east-1")

def send_data():
    data = {
        "id": int(time.time()),
        "temperature": 25.3,
        "humidity": 70
    }
    response = kinesis_client.put_record(
        StreamName="real-time-stream",
        Data=json.dumps(data),
        PartitionKey="partitionKey"
    )
    print("Sent:", response)

send_data()
