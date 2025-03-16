import json
import boto3
import pymysql
import base64
from datetime import datetime

# AWS S3 Configuration
s3_client = boto3.client("s3")
s3_bucket_name = "processed-data-bucket-ag"

rds_host = "mysql-database-1.cmf042mmsqvq.us-east-1.rds.amazonaws.com"
db_user = "admin"
db_pass = "password"
db_name = "sensor_data"

conn = pymysql.connect(host=rds_host, user=db_user, password=db_pass, database=db_name)

def lambda_handler(event, context):
    for record in event["Records"]:
        payload = json.loads(record["kinesis"]["data"])
        
        with conn.cursor() as cursor:
            cursor.execute(
                "INSERT INTO sensor_readings (id, temperature, humidity) VALUES (%s, %s, %s)",
                (payload["id"], payload["temperature"], payload["humidity"])
            )
        conn.commit()

        # Generate a unique filename with timestamp
        timestamp = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        s3_file_key = f"sensor_data/{timestamp}_{payload['id']}.json"
        
        # Convert payload to JSON and upload to S3
        s3_client.put_object(
            Bucket=s3_bucket_name,
            Key=s3_file_key,
            Body=json.dumps(payload)
        )
    return {"status": "success"}
