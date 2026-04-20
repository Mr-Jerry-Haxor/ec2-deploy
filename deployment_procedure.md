# EC2 Deployment Procedure (First and Foundational)

This is the first deployment to run. It creates the shared DynamoDB tables and shared private S3 image bucket data used later by ECS and Lambda.

## 1. Create IAM Role for EC2
1. Open AWS Console -> IAM -> Roles -> Create role.
2. Trusted entity: EC2.
3. Attach policies:
   - AmazonDynamoDBFullAccess
   - AmazonS3FullAccess (or least-privilege to the private covers bucket)
   - CloudWatchAgentServerPolicy (optional)
4. Name role `ec2a-music-role`.

## 2. Create Private S3 Bucket for Covers
1. AWS Console -> S3 -> Create bucket.
2. Name: `music-shared-private-covers-<account>-<region>`.
3. Keep Block Public Access enabled.
4. Do not enable static website hosting.

## 3. Launch EC2 Instance
1. AWS Console -> EC2 -> Launch instance.
2. Name: `ec2a-music-app`.
3. AMI: Amazon Linux 2023.
4. Type: t3.small (recommended minimum).
5. Attach IAM role: `ec2a-music-role`.
6. Security group inbound:
   - SSH 22 from your IP
   - HTTP 80 from 0.0.0.0/0
7. In Advanced details -> User data, paste and customize `infra/ec2_user_data.sh`.
8. Launch instance.

## 4. Verify Base Service
1. SSH into EC2.
2. Check service status:
   - `sudo systemctl status music-ec2-api`
   - `sudo systemctl status nginx`
3. Check health endpoint:
   - `curl http://localhost:8000/health`
   - `curl http://<ec2-public-dns>/health`
  
4. install the git and run the ec2userdata manually
   - `git clone <repo url> EC2`

## 5. Create Shared DynamoDB Tables from EC2
1. SSH into EC2.
2. Navigate to backend folder:
   - `cd /opt/music-app/EC2/backend`
3. Activate venv:
   - `source .venv/bin/activate`
4. Run table creation:
   - `python create_aws_tables.py`

## 6. Load Shared Data from EC2
1. Seed users:
   - `python seed_aws_users.py`
2. Load songs and upload covers to private S3:
   - `python load_aws_data.py --upload-images --bucket music-shared-private-covers-<account>-<region>`

## 7. Final Validation
1. Open browser: `http://<ec2-public-dns>/login.html`
2. Register a new user.
3. Login and reach `main.html`.
4. Confirm song query and subscription actions work.
5. Confirm direct unauthenticated access to `main.html` redirects to login.

## 8. Outputs to Reuse in ECS/Lambda
Record and keep these values:
- AWS region
- Table names
- Private S3 bucket name
- CORS frontend origin(s)

These values are reused in ECS and Lambda deployments.
