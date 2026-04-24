# EC2 Deployment Procedure (Ubuntu 24.04 + AWS Academy)

This is the first deployment and should be completed before ECS/Lambda. It initializes shared DynamoDB tables and the private S3 covers bucket reused by all architectures.

## Mandatory Assignment Rules Covered

- Entire solution is deployed in AWS.
- Elastic Beanstalk is not used.
- Public access is on standard ports 80/443 only.
- IAM role creation is not required; use pre-created LabRole.
- Private S3 objects are accessed with presigned URLs.
- DynamoDB uses both Query and Scan in API logic.
- DynamoDB schema includes GSI and LSI.

## 0. Required Inputs

Prepare these values first:

- AWS region, for example `us-east-1`
- AWS account ID
- GitHub repository URL
- Git branch name `main`
- Unique private bucket name, for example `music-shared-private-covers-<account>-<region>`
- Your student email prefix, for example `s3XXXXXX`
- Your username prefix, for example `FirstnameLastname`

## 1. Create the Private Covers Bucket

Run from your local machine (AWS CLI configured):

```bash
# Set your variables once for this shell session.
export AWS_REGION="us-east-1"
export ACCOUNT_ID="123456789012"
export PRIVATE_BUCKET="music-shared-private-covers-${ACCOUNT_ID}-${AWS_REGION}"

# Create private bucket for song covers.
aws s3api create-bucket \
  --bucket "$PRIVATE_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

# Keep bucket private (required).
aws s3api put-public-access-block \
  --bucket "$PRIVATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

For `us-east-1`, create-bucket may require no `LocationConstraint`. If AWS CLI returns that error, rerun create-bucket without that flag.

## 2. Launch EC2 (Ubuntu 24.04)

Use Console steps:

1. Open EC2 -> Launch instance.
2. Name: `ec2a-music-app`.
3. AMI: `Ubuntu Server 24.04 LTS`.
4. Instance type: `t3.small` (recommended minimum).
5. Key pair: select your existing key pair.
6. Network/security group inbound rules:
   - SSH `22` from your IP only
   - HTTP `80` from `0.0.0.0/0`
   - HTTPS `443` from `0.0.0.0/0` (optional but recommended)
7. IAM instance profile: attach pre-created `LabRole`.
8. Advanced details -> User data: paste the updated script from `EC2/infra/ec2_user_data.sh` and replace placeholders.

User data values you must set before launch:

- `REPO_URL` to your GitHub repo
- `BRANCH` to `main`
- `S3_BUCKET_NAME` to your private bucket
- Optional: `CORS_ALLOW_ORIGINS` (if omitted, script auto-detects instance public host)

## 3. Validate User Data Bootstrap

SSH to EC2 and run:

```bash
# Cloud-init logs show user-data execution output.
sudo tail -n 200 /var/log/cloud-init-output.log

# Verify backend and nginx are healthy.
sudo systemctl status music-ec2-api --no-pager
sudo systemctl status nginx --no-pager

# Verify local API health.
curl -sS http://127.0.0.1:8000/health


#add public ip to the config.js
sudo nano  /opt/music-app/frontend/config.js

#like -  API_BASE_URL: "http://3.87.45.164",
```

Then test from browser:

- `http://<EC2_PUBLIC_DNS>/`
- `http://<EC2_PUBLIC_DNS>/login.html`

## 4. Alternative If User Data Fails

If user-data does not complete, run manual commands on EC2:

```bash
# 1) Install base packages on Ubuntu 24.04.
sudo apt-get update -y
sudo apt-get install -y git python3 python3-venv python3-pip build-essential nginx

# 2) Clone your repository and switch to main branch.
sudo mkdir -p /opt/music-app
sudo chown -R ubuntu:ubuntu /opt/music-app
git clone --branch main --single-branch https://github.com/Mr-Jerry-Haxor/ec2-deploy.git /opt/music-app

# 3) Create Python environment and install dependencies.
cd /opt/music-app/EC2/backend
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 4) Create app environment file used by systemd.
sudo tee /etc/music-ec2.env >/dev/null <<'EOF'
AWS_REGION=us-east-1
USERS_TABLE_NAME=music_shared_users
MUSIC_TABLE_NAME=music_shared_songs
SUBSCRIPTIONS_TABLE_NAME=music_shared_subscriptions
S3_BUCKET_NAME=<YOUR_PRIVATE_BUCKET>
PRESIGNED_URL_TTL=3600
CORS_ALLOW_ORIGINS=http://<EC2_PUBLIC_DNS_OR_IP>
PORT=8000
FLASK_DEBUG=false
HOME=/home/ubuntu
EOF

# 5) Start services (same config files shipped in user-data script).
sudo cp /opt/music-app/EC2/infra/nginx.conf /etc/nginx/sites-available/music-ec2.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/music-ec2.conf /etc/nginx/sites-enabled/music-ec2.conf
sudo nginx -t
sudo systemctl restart nginx
```

Create the systemd service if needed:

```bash
sudo tee /etc/systemd/system/music-ec2-api.service >/dev/null <<'EOF'
[Unit]
Description=Music EC2 Flask API
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/opt/music-app/EC2/backend
EnvironmentFile=/etc/music-ec2.env
ExecStart=/opt/music-app/EC2/backend/.venv/bin/gunicorn --bind 127.0.0.1:8000 --workers 2 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now music-ec2-api
```

## 5. Initialize DynamoDB Tables and Data

On EC2:

```bash
cd /opt/music-app/EC2/backend
source .venv/bin/activate

# Create required tables with LSI and GSI.
python create_aws_tables.py

# Seed assignment-formatted login users (10 users).
# Example output emails: s3XXXXXX0@student.rmit.edu.au ... s3XXXXXX9@student.rmit.edu.au
export STUDENT_EMAIL_PREFIX="s3XXXXXX"
export USER_NAME_PREFIX="FirstnameLastname"
python seed_aws_users.py

# Load songs and upload image files to private S3.
python load_aws_data.py \
  --file 2026a2_songs.json \
  --upload-images \
  --bucket "$PRIVATE_BUCKET"
```

## 6. Runtime Verification Checklist

Run on EC2:

```bash
# Health endpoint through nginx proxy.
curl -sS http://localhost/health

# API route checks.
curl -sS -X POST http://localhost/api/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"s3XXXXXX0@student.rmit.edu.au","password":"012345"}'
```

Browser checks:

1. Open `http://<EC2_PUBLIC_DNS>/`.
2. Confirm login page loads at root URL.
3. Login with seeded account.
4. Query songs and subscribe.
5. Remove subscription.
6. Logout and confirm redirect to login.

## 7. Credential Fallback If LabRole Cannot Access S3/DynamoDB

Use this only when role-based access fails with AccessDenied.

### 7.1 Verify role path first

```bash
# Should return identity and allow listing resources.
aws sts get-caller-identity
aws dynamodb list-tables --region "$AWS_REGION"
aws s3 ls "s3://$PRIVATE_BUCKET" --region "$AWS_REGION"
```

### 7.2 Configure shared credentials file

Create `/home/ubuntu/.aws/credentials` on EC2:

```bash
mkdir -p /home/ubuntu/.aws
chmod 700 /home/ubuntu/.aws

cat >/home/ubuntu/.aws/credentials <<'EOF'
[default]
aws_access_key_id=YOUR_ACCESS_KEY_ID
aws_secret_access_key=YOUR_SECRET_ACCESS_KEY
aws_session_token=YOUR_SESSION_TOKEN
EOF

chmod 600 /home/ubuntu/.aws/credentials
chown -R ubuntu:ubuntu /home/ubuntu/.aws
```

Then tell the backend service to use that file:

```bash
echo 'AWS_SHARED_CREDENTIALS_FILE=/home/ubuntu/.aws/credentials' | sudo tee -a /etc/music-ec2.env
echo 'AWS_PROFILE=default' | sudo tee -a /etc/music-ec2.env
sudo systemctl restart music-ec2-api
```

## 8. Values Reused by ECS and Lambda

Keep these final values for next deployments:

- Region
- Table names
- Private bucket name
- CORS origin used by EC2
- Seed user pattern prefix
