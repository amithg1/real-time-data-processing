provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket         = "terraform-state-bucket-ag"
    key            = "state/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

resource "aws_kinesis_stream" "data_stream" {
  name             = "real-time-stream"
  shard_count      = 1
  retention_period = 24
}

# resource "aws_db_instance" "mysql_db" {
#   engine               = "mysql"
#   engine_version       = "8.0"
#   instance_class       = "db.t3.micro"
#   allocated_storage    = 20
#   identifier           = "realtime-mysql-db"
#   username            = "admin"
#   password            = "password"
#   publicly_accessible  = false
#   skip_final_snapshot  = true
# }

# resource "aws_ssm_parameter" "rds_endpoint" {
#   name  = "/myapp/rds_endpoint"
#   type  = "String"
#   value = aws_db_instance.mysql_db.endpoint
# }

resource "aws_redshift_cluster" "redshift_cluster" {
  cluster_identifier        = "redshift-cluster"
  database_name             = "analytics_db"
  master_username           = "admin"
  master_password           = "Password1"
  node_type                 = "dc2.large"
  number_of_nodes           = 2
}

resource "aws_ssm_parameter" "redshift_jdbc_url" {
  name  = "/myapp/redshift_jdbc_url"
  type  = "String"
  value = "jdbc:redshift://${aws_redshift_cluster.redshift_cluster.endpoint}:5439/dev"
}


resource "aws_lambda_function" "process_stream" {
  function_name    = "process-kinesis"
  runtime         = "python3.9"
  role            = aws_iam_role.lambda_exec.arn
  handler         = "lambda_function.lambda_handler"
  s3_bucket       = "lambda-deployment-bucket-ag"
  s3_key          = "lambda_function.zip"

  timeout = 30

  vpc_config {
    subnet_ids         = ["subnet-0e2b76d29654ee212"]
    security_group_ids = ["sg-0366d404eff703700", "sg-04d669d562d9a51b1"]
  }

  layers = [aws_lambda_layer_version.mysql_layer.arn]
}

resource "aws_lambda_layer_version" "mysql_layer" {
  layer_name          = "mysql-connector-layer"
  compatible_runtimes = ["python3.9"]
  s3_bucket           = "lambda-deployment-bucket-ag"
  s3_key              = "mysql-layer.zip"
}

resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn  = aws_kinesis_stream.data_stream.arn  # Replace with your Kinesis stream ARN
  function_name     = aws_lambda_function.process_stream.arn      # Replace with your Lambda function ARN
  starting_position = "LATEST"  # Reads only new records from the stream
  batch_size        = 100       # Number of records per batch (adjust as needed)
}


resource "aws_s3_bucket" "lambda-deployment-bucket-ag" {
  bucket = "lambda-deployment-bucket-ag"
}

resource "aws_s3_bucket_versioning" "versioning_1" {
  bucket = aws_s3_bucket.lambda-deployment-bucket-ag.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_vpc_policy" {
  name        = "LambdaVPCPolicy"
  description = "Permissions for Lambda to interact with VPC"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_vpc_policy.arn
}

resource "aws_iam_policy" "lambda_kinesis_policy" {
  name        = "LambdaKinesisPolicy"
  description = "Policy for Lambda to read from Kinesis stream"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards",
          "kinesis:ListStreams"
        ]
        Resource = "arn:aws:kinesis:us-east-1:713881815454:stream/real-time-stream"
      }
    ]
  })
}


resource "aws_iam_policy_attachment" "lambda_policy" {
  name       = "lambda_policy_attachment"
  roles      = [aws_iam_role.lambda_exec.name]
  policy_arn = aws_iam_policy.lambda_kinesis_policy.arn

}

resource "aws_s3_bucket" "processed_data" {
  bucket = "processed-data-bucket-ag"
}

resource "aws_s3_bucket_notification" "s3_event_trigger" {
  bucket = aws_s3_bucket.processed_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.invoke_step_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "sensor-data/" # Only trigger for files in this folder
  }
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.invoke_step_function.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.processed_data.arn
}


# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "LambdaInvokeStepFunctionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_s3_policy" {
  name        = "LambdaS3Policy"
  description = "Policy for Lambda to access S3"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::processed-data-bucket-ag",
          "arn:aws:s3:::processed-data-bucket-ag/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}


# IAM Policy for Lambda to Invoke Step Functions
resource "aws_iam_policy" "lambda_step_function_policy" {
  name        = "LambdaInvokeStepFunctionPolicy"
  description = "Allows Lambda to invoke Step Functions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = "arn:aws:states:us-east-1:713881815454:stateMachine:my-step-function"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_step_function_policy.arn
}

# Create Lambda Function
resource "aws_lambda_function" "invoke_step_function" {
  function_name    = "InvokeStepFunctionLambda"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  s3_bucket       = "lambda-deployment-bucket-ag"
  s3_key          = "sfn_lambda_function.zip"

  environment {
    variables = {
      STEP_FUNCTION_ARN = "arn:aws:states:us-east-1:713881815454:stateMachine:my-step-function"
    }
  }
}


resource "aws_s3_bucket_versioning" "versioning_2" {
  bucket = aws_s3_bucket.processed_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "glue_role" {
  name = "AWSGlueServiceRole1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "glue_s3_access" {
  name       = "GlueS3Access"
  roles      = [aws_iam_role.glue_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_policy" "glue_ssm_access" {
  name        = "GlueSSMAccessPolicy"
  description = "Allows Glue to read parameters from SSM"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "ssm:GetParameter",
        Resource = "arn:aws:ssm:us-east-1:713881815454:parameter/myapp/rds_endpoint"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_ssm_attachment" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_ssm_access.arn
}


resource "aws_glue_job" "example" {
  name     = "sensor-glue-job"
  role_arn = aws_iam_role.glue_role.arn
  command {
    script_location = "s3://glue-assets-ag/scripts/glue_etl_real-time.py"
    python_version  = "3"
  }
  glue_version = "3.0"
}

resource "aws_s3_bucket" "glue-assets-ag" {
  bucket = "glue-assets-ag"
}

resource "aws_s3_bucket_versioning" "versioning_3" {
  bucket = aws_s3_bucket.glue-assets-ag.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "step_function_role" {
  name = "StepFunctionExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "step_function_policy" {
  name       = "StepFunctionPolicy"
  roles      = [aws_iam_role.step_function_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
}

resource "aws_sfn_state_machine" "example" {
  name       = "my-step-function"
  role_arn   = aws_iam_role.step_function_role.arn
  definition = file("step_function.json")
}
