#!/bin/bash
set -euxo pipefail

# Replace values before use.
REPO_URL="https://github.com/YOUR_GITHUB_USER/cloud-assignment.git"
BRANCH="master"
AWS_REGION="us-east-1"
USERS_TABLE_NAME="music_shared_users"
MUSIC_TABLE_NAME="music_shared_songs"
SUBSCRIPTIONS_TABLE_NAME="music_shared_subscriptions"
S3_BUCKET_NAME="music-shared-private-covers-UNIQUE"
CORS_ALLOW_ORIGINS="http://YOUR_EC2_PUBLIC_DNS_OR_IP"

APP_ROOT="/opt/music-app"
BACKEND_DIR="$APP_ROOT/EC2/backend"
FRONTEND_DIR="$APP_ROOT/EC2/frontend"

sudo dnf update -y
sudo dnf install -y git python3 python3-pip python3-devel gcc nginx

if [ ! -d "$APP_ROOT/.git" ]; then
  sudo git clone --branch "$BRANCH" "$REPO_URL" "$APP_ROOT"
else
  cd "$APP_ROOT"
  sudo git fetch --all
  sudo git checkout "$BRANCH"
  sudo git pull --ff-only
fi

sudo python3 -m venv "$BACKEND_DIR/.venv"
sudo "$BACKEND_DIR/.venv/bin/pip" install --upgrade pip
sudo "$BACKEND_DIR/.venv/bin/pip" install -r "$BACKEND_DIR/requirements.txt"

sudo tee /etc/music-ec2.env >/dev/null <<EOF
AWS_REGION=$AWS_REGION
USERS_TABLE_NAME=$USERS_TABLE_NAME
MUSIC_TABLE_NAME=$MUSIC_TABLE_NAME
SUBSCRIPTIONS_TABLE_NAME=$SUBSCRIPTIONS_TABLE_NAME
S3_BUCKET_NAME=$S3_BUCKET_NAME
PRESIGNED_URL_TTL=3600
CORS_ALLOW_ORIGINS=$CORS_ALLOW_ORIGINS
PORT=8000
FLASK_DEBUG=false
EOF

sudo chmod 600 /etc/music-ec2.env

sudo tee /etc/systemd/system/music-ec2-api.service >/dev/null <<EOF
[Unit]
Description=Music EC2 Flask API
After=network.target

[Service]
User=ec2-user
WorkingDirectory=$BACKEND_DIR
EnvironmentFile=/etc/music-ec2.env
ExecStart=$BACKEND_DIR/.venv/bin/gunicorn --bind 127.0.0.1:8000 --workers 2 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/nginx/conf.d/music-ec2.conf >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name _;

    root $FRONTEND_DIR;
    index login.html;

    location / {
        try_files \$uri \$uri/ /login.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8000/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /health {
        proxy_pass http://127.0.0.1:8000/health;
        proxy_set_header Host \$host;
    }
}
EOF

sudo nginx -t
sudo systemctl daemon-reload
sudo systemctl enable music-ec2-api
sudo systemctl restart music-ec2-api
sudo systemctl enable nginx
sudo systemctl restart nginx

echo "EC2 app bootstrapped."
