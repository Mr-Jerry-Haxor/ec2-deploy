#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/YOUR_GITHUB_USER/cloud-assignment.git}"
BRANCH="${BRANCH:-main}"

AWS_REGION="${AWS_REGION:-us-east-1}"
USERS_TABLE_NAME="${USERS_TABLE_NAME:-music_shared_users}"
MUSIC_TABLE_NAME="${MUSIC_TABLE_NAME:-music_shared_songs}"
SUBSCRIPTIONS_TABLE_NAME="${SUBSCRIPTIONS_TABLE_NAME:-music_shared_subscriptions}"

S3_BUCKET_NAME="${S3_BUCKET_NAME:-music-shared-private-covers-REPLACE}"

CORS_ALLOW_ORIGINS="${CORS_ALLOW_ORIGINS:-}"
PRESIGNED_URL_TTL="${PRESIGNED_URL_TTL:-3600}"

EC2_APP_USER="ubuntu"
PORT="${PORT:-8000}"
FLASK_DEBUG="${FLASK_DEBUG:-false}"

APP_ROOT="/opt/music-app"
BACKEND_DIR="$APP_ROOT/backend"
FRONTEND_DIR="$APP_ROOT/frontend"

export DEBIAN_FRONTEND=noninteractive

echo "Installing dependencies..."
apt-get update -y
apt-get install -y git python3 python3-venv python3-pip build-essential nginx curl

echo "Cloning repo..."
rm -rf "$APP_ROOT"
git clone --branch "$BRANCH" "$REPO_URL" "$APP_ROOT"

# Validate structure
if [[ ! -d "$BACKEND_DIR" ]]; then
  echo "ERROR: backend folder not found. Repo structure mismatch."
  ls -R "$APP_ROOT"
  exit 1
fi

chown -R "$EC2_APP_USER:$EC2_APP_USER" "$APP_ROOT"

echo "Setting up Python environment..."
sudo -u "$EC2_APP_USER" python3 -m venv "$BACKEND_DIR/.venv"
sudo -u "$EC2_APP_USER" "$BACKEND_DIR/.venv/bin/pip" install --upgrade pip
sudo -u "$EC2_APP_USER" "$BACKEND_DIR/.venv/bin/pip" install -r "$BACKEND_DIR/requirements.txt"

echo "Configuring frontend..."
PUBLIC_IP=$(curl -fsS http://169.254.169.254/latest/meta-data/public-ipv4 || true)
API_BASE_URL="http://$PUBLIC_IP"

mkdir -p "$FRONTEND_DIR"

cat >"$FRONTEND_DIR/config.js" <<EOF
window.APP_CONFIG = {
  ARCHITECTURE: "EC2",
  API_BASE_URL: "$API_BASE_URL",
  APP_TITLE: "MusicCloud EC2"
};
EOF

chown "$EC2_APP_USER:$EC2_APP_USER" "$FRONTEND_DIR/config.js"

echo "Writing environment file..."
cat >/etc/music-ec2.env <<EOF
AWS_REGION=$AWS_REGION
USERS_TABLE_NAME=$USERS_TABLE_NAME
MUSIC_TABLE_NAME=$MUSIC_TABLE_NAME
SUBSCRIPTIONS_TABLE_NAME=$SUBSCRIPTIONS_TABLE_NAME
S3_BUCKET_NAME=$S3_BUCKET_NAME
PRESIGNED_URL_TTL=$PRESIGNED_URL_TTL
PORT=$PORT
FLASK_DEBUG=$FLASK_DEBUG
EOF

chmod 600 /etc/music-ec2.env

echo "Creating systemd service..."
cat >/etc/systemd/system/music-ec2-api.service <<EOF
[Unit]
Description=Music EC2 API
After=network.target

[Service]
User=ubuntu
WorkingDirectory=$BACKEND_DIR
EnvironmentFile=/etc/music-ec2.env
ExecStart=$BACKEND_DIR/.venv/bin/gunicorn --bind 127.0.0.1:$PORT --workers 2 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "Configuring nginx..."
cat >/etc/nginx/sites-available/music-ec2.conf <<EOF
server {
    listen 80;
    server_name _;

    root $FRONTEND_DIR;
    index login.html;

    location / {
        try_files \$uri \$uri/ /login.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:$PORT/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /health {
        proxy_pass http://127.0.0.1:$PORT/health;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/music-ec2.conf /etc/nginx/sites-enabled/music-ec2.conf

echo "Starting services..."
systemctl daemon-reload
systemctl enable music-ec2-api
systemctl enable nginx

nginx -t
systemctl restart nginx

echo "Bootstrap completed successfully."