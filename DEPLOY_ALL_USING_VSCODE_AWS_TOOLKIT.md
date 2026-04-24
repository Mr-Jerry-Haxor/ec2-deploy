# Complete Deployment Using VS Code AWS Toolkit (AWS Academy)

This guide deploys the full assignment solution using VS Code as the control center.

It supports all three required backend architectures:
- EC2 (Ubuntu 24.04)
- ECS Fargate
- API Gateway + Lambda

It also enforces these assignment constraints:
- Use branch main, not master
- Use LabRole where possible
- Use only port 80/443 for public access
- Use S3 static website hosting for ECS and Lambda frontends
- Use REST methods GET, POST, DELETE
- Keep cover-image bucket private and serve images via presigned URLs

## 1. Install and Configure VS Code Tooling

### 1.1 Install extensions
Install in VS Code:
- AWS Toolkit
- Python
- Docker

### 1.2 Configure AWS credentials for AWS Academy
If your AWS Academy lab already injects credentials, use that profile.

If not, create credentials file manually on your machine:

```powershell
# Windows PowerShell
New-Item -ItemType Directory -Force "$HOME\.aws" | Out-Null
notepad "$HOME\.aws\credentials"
```

Add:

```ini
[awsacademy]
aws_access_key_id=YOUR_ACCESS_KEY_ID
aws_secret_access_key=YOUR_SECRET_ACCESS_KEY
aws_session_token=YOUR_SESSION_TOKEN
```

Add region config:

```powershell
notepad "$HOME\.aws\config"
```

```ini
[profile awsacademy]
region = us-east-1
output = json
```

### 1.3 Select profile in AWS Toolkit
In VS Code:
1. Open AWS Explorer sidebar
2. Choose Select Credentials Profile
3. Select awsacademy
4. Confirm resources load in Explorer

## 2. Open Project and Prepare Variables

Open this workspace folder in VS Code and set shared variables in terminal:

```bash
# Linux/macOS shell style (use equivalent in PowerShell if needed)
export AWS_REGION="us-east-1"
export ACCOUNT_ID="123456789012"
export PRIVATE_BUCKET="music-shared-private-covers-${ACCOUNT_ID}-${AWS_REGION}"
export ECS_FRONTEND_BUCKET="ecsx-frontend-${ACCOUNT_ID}-${AWS_REGION}"
export LAMBDA_FRONTEND_BUCKET="lambdax-frontend-${ACCOUNT_ID}-${AWS_REGION}"
```

PowerShell equivalent:

```powershell
$env:AWS_REGION="us-east-1"
$env:ACCOUNT_ID="123456789012"
$env:PRIVATE_BUCKET="music-shared-private-covers-$($env:ACCOUNT_ID)-$($env:AWS_REGION)"
$env:ECS_FRONTEND_BUCKET="ecsx-frontend-$($env:ACCOUNT_ID)-$($env:AWS_REGION)"
$env:LAMBDA_FRONTEND_BUCKET="lambdax-frontend-$($env:ACCOUNT_ID)-$($env:AWS_REGION)"
```

## 3. Deploy Architecture 1: EC2 (Foundational)

Use this first because it creates shared DynamoDB data and uploads private S3 images.

### 3.1 Create private covers bucket

```bash
aws s3api create-bucket \
  --bucket "$PRIVATE_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

aws s3api put-public-access-block \
  --bucket "$PRIVATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

If region is us-east-1 and create-bucket rejects LocationConstraint, rerun create-bucket without that flag.

### 3.2 Launch EC2 (Ubuntu 24.04)
In AWS Console (opened from Toolkit or browser):
1. Launch instance: Ubuntu Server 24.04 LTS
2. Attach LabRole instance profile
3. Inbound rules: 22 from your IP, 80 from internet, 443 optional
4. Paste script from EC2/infra/ec2_user_data.sh into User Data
5. Edit placeholders in User Data:
   - REPO_URL = your repository URL
   - BRANCH = main
   - S3_BUCKET_NAME = your private bucket

### 3.3 Validate services
SSH and run:

```bash
sudo systemctl status music-ec2-api --no-pager
sudo systemctl status nginx --no-pager
curl -sS http://127.0.0.1:8000/health
curl -sS http://localhost/health
```

### 3.4 If User Data fails, use manual fallback
Use EC2/deployment_procedure.md section Alternative If User Data Fails.

### 3.5 Initialize shared tables and seed data

```bash
cd /opt/music-app/EC2/backend
source .venv/bin/activate

python create_aws_tables.py

export STUDENT_EMAIL_PREFIX="s3XXXXXX"
export USER_NAME_PREFIX="FirstnameLastname"
python seed_aws_users.py

python load_aws_data.py --file 2026a2_songs.json --upload-images --bucket "$PRIVATE_BUCKET"
```

## 4. Deploy Architecture 2: ECS + S3 Static Frontend

### 4.1 Build and push backend image

```bash
export ACCOUNT_ID
export AWS_REGION
export REPOSITORY="ecsx-music-api"
export IMAGE_TAG="latest"
bash ECS/infra/build_and_push.sh
```

### 4.2 Create cluster, ALB, target group, service
Use ECS and EC2 consoles with values in ECS/deployment_procedure.md.

Important:
- Task role and execution role must be LabRole ARN
- Container port must be 80
- Health path must be /api/health

### 4.3 Prepare ECS frontend bucket (S3 website)

```bash
aws s3api create-bucket \
  --bucket "$ECS_FRONTEND_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

aws s3api put-public-access-block \
  --bucket "$ECS_FRONTEND_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

aws s3 website "s3://$ECS_FRONTEND_BUCKET" --index-document login.html --error-document login.html
```

Set ECS/frontend/config.js API_BASE_URL to your ALB DNS URL.

Upload:

```bash
aws s3 sync ECS/frontend "s3://$ECS_FRONTEND_BUCKET" --delete
```

### 4.4 Public-read policy for ECS frontend bucket only

```bash
cat > /tmp/ecs_frontend_policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$ECS_FRONTEND_BUCKET/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket "$ECS_FRONTEND_BUCKET" --policy file:///tmp/ecs_frontend_policy.json
```

## 5. Deploy Architecture 3: Lambda + API Gateway + S3 Static Frontend

### 5.1 Package Lambda from VS Code terminal

```bash
export INCLUDE_DEPENDENCIES=false
bash Lambda/infra/package_lambda.sh
```

### 5.2 Deploy Lambda using AWS Toolkit
In VS Code:
1. Open Lambda source file Lambda/backend/lambda_function.py
2. Run command palette: AWS: Deploy Lambda
3. Choose existing or new function name lambdax-music-api
4. Runtime Python 3.12
5. Execution role: LabRole

If Toolkit deployment is unavailable in your lab image, deploy zip via Console upload from Lambda/infra/lambda_package.zip.

### 5.3 Configure Lambda environment variables
Set:
- AWS_REGION
- USERS_TABLE_NAME
- MUSIC_TABLE_NAME
- SUBSCRIPTIONS_TABLE_NAME
- S3_BUCKET_NAME
- PRESIGNED_URL_TTL
- CORS_ALLOW_ORIGINS

### 5.4 Create API Gateway HTTP API
Create routes from Lambda/infra/api_gateway_routes.txt and integrate all routes with this Lambda.

### 5.5 Prepare Lambda frontend bucket (S3 website)

```bash
aws s3api create-bucket \
  --bucket "$LAMBDA_FRONTEND_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

aws s3api put-public-access-block \
  --bucket "$LAMBDA_FRONTEND_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

aws s3 website "s3://$LAMBDA_FRONTEND_BUCKET" --index-document login.html --error-document login.html
```

Set Lambda/frontend/config.js API_BASE_URL to API Gateway invoke URL + /prod.

Upload:

```bash
aws s3 sync Lambda/frontend "s3://$LAMBDA_FRONTEND_BUCKET" --delete
```

Policy for this bucket only:

```bash
cat > /tmp/lambda_frontend_policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$LAMBDA_FRONTEND_BUCKET/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy --bucket "$LAMBDA_FRONTEND_BUCKET" --policy file:///tmp/lambda_frontend_policy.json
```

## 6. Credential and Permission Fallback (LabRole First)

Always test LabRole path first.

### 6.1 Verify role path

```bash
aws sts get-caller-identity
aws dynamodb list-tables --region "$AWS_REGION"
aws s3 ls "s3://$PRIVATE_BUCKET" --region "$AWS_REGION"
```

### 6.2 If AccessDenied, use credentials profile in VS Code terminal

```bash
# Use specific profile for command execution
aws dynamodb list-tables --profile awsacademy --region "$AWS_REGION"
```

For EC2 service fallback, set in /etc/music-ec2.env:
- AWS_SHARED_CREDENTIALS_FILE
- AWS_PROFILE

For ECS/Lambda fallback, inject temporary values:
- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
- AWS_SESSION_TOKEN

Do not commit credentials to source control.

## 7. Final Functional Validation Checklist

### EC2
- Root URL opens login page on port 80
- Register/login works
- Query supports at least one field rule
- Subscribe/remove updates DynamoDB

### ECS
- Frontend is S3 static website URL
- API served from ALB on 80/443
- ALB health path returns healthy
- Root ALB URL redirects to frontend login when FRONTEND_URL is set

### Lambda
- Frontend is S3 static website URL
- API invoke URL over HTTPS
- GET/POST/DELETE methods all work

### Data and security
- Private bucket remains private
- Images visible in UI through presigned URLs
- Query and Scan behaviors both demonstrable
- GSI and LSI exist in DynamoDB music table

## 8. Submission Packaging (Recommended)
Keep these folders for submission:
- EC2
- ECS
- Lambda

Include assignment and report files as needed by your group process.
