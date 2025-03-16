# real-time-data-processing
A real-time data processing pipeline that ingests streaming data, processes it, and stores it in an analytical warehouse.


📌 High-Level Workflow:

Python code (send_data.py) → Sends real-time JSON data to AWS Kinesis Data Stream.
 
AWS Kinesis → Streams real-time data to AWS Lambda.

AWS Lambda:
    Writes raw data into Amazon S3 (Landing Zone).
    Writes structured data into AWS RDS MySQL.

AWS S3 → Stores JSON sensor data files.

Amazon EventBridge (S3 PutObject Event) → Triggers another AWS Lambda Function.

This AWS Lambda Function → Invokes AWS Step Function, which in-turn triggers AWS Glue job.

AWS Glue: Extracts, transforms, and loads (ETL) data into AWS Redshift.

AWS Redshift → Stores processed data for analytics and querying.

#Not yet implemented
Amazon QuickSight / Athena → Used for data visualization and analysis.

CI/CD with GitHub Actions → Automates deployment of Lambda, Glue, and Step Function codes.