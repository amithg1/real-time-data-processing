import sys
import boto3
import json
from awsglue.transforms import * # type: ignore
from awsglue.utils import getResolvedOptions # type: ignore
from pyspark.context import SparkContext # type: ignore
from awsglue.context import GlueContext # type: ignore
from awsglue.job import Job # type: ignore

args = getResolvedOptions(sys.argv, ["JOB_NAME"])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

# Fetch Redshift JDBC URL from AWS SSM Parameter Store
ssm_client = boto3.client("ssm", region_name="us-east-1")
parameter = ssm_client.get_parameter(Name="/myapp/redshift_jdbc_url", WithDecryption=True)
jdbc_url = parameter["Parameter"]["Value"]

# Read latest JSON file from S3
s3_client = boto3.client("s3")
bucket_name = "processed-data-bucket-ag"
objects = s3_client.list_objects_v2(Bucket=bucket_name, Prefix="sensor_data/")["Contents"]
latest_file = max(objects, key=lambda x: x["LastModified"])["Key"]

response = s3_client.get_object(Bucket=bucket_name, Key=latest_file)
data = json.loads(response["Body"].read())

# Read data from S3
df = spark.read.json(data)

# Transform
df_transformed = df.withColumnRenamed("id", "sensor_id")

# Load into Redshift
df_transformed.write \
    .format("jdbc") \
    .option("url", jdbc_url) \
    .option("dbtable", "sensor_analytics") \
    .option("user", "admin") \
    .option("password", "Password1") \
    .mode("append") \
    .save()

job.commit()
