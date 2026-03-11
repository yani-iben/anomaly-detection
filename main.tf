# 1. Provider Configuration
provider "aws" {
  region = "us-east-1"
}

# 2. S3 Bucket for Data
resource "aws_s3_bucket" "data_bucket" {
  bucket = "ds5220-project1-data-917795609593"
  force_destroy = true # Allows 'terraform destroy' to work even if files exist
}

# 3. SNS Topic for Notifications
resource "aws_sns_topic" "s3_notifier" {
  name = "ds5220-dp1-sns"
}

# 4. SNS Topic Policy (Allows S3 to publish to the topic)
resource "aws_sns_topic_policy" "default" {
  arn    = aws_sns_topic.s3_notifier.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    resources = [aws_sns_topic.s3_notifier.arn]
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.data_bucket.arn]
    }
  }
}

# 5. S3 Bucket Notification (Triggers SNS on upload)
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.data_bucket.id

  topic {
    topic_arn     = aws_sns_topic.s3_notifier.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "raw/"
  }
}

# 6. EC2 Instance (The "Brain")
resource "aws_instance" "app_server" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS
  instance_type = "t2.micro"
  key_name      = "your-key-name" # Replace with your .pem key name

  vpc_security_group_ids = [aws_security_group.app_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = "DS5220-Anomaly-Detector"
  }
}

# 7. Security Group (Allows Port 8000 and SSH)
resource "aws_security_group" "app_sg" {
  name = "ds5220-sg"

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 8. IAM Role for EC2 (Full S3 Access)
resource "aws_iam_role" "ec2_role" {
  name = "ds5220-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ds5220-ec2-profile"
  role = aws_iam_role.ec2_role.name
}