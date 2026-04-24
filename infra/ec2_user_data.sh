#!/usr/bin/env bash
set -euo pipefail

# Ubuntu 24.04 bootstrap for EC2 architecture.
# Replace placeholder values before first launch.
REPO_URL="${REPO_URL:-https://github.com/Mr-Jerry-Haxor/ec2-deploy.git}"
BRANCH="${BRANCH:-main}"
AWS_REGION="${AWS_REGION:-us-east-1}"
USERS_TABLE_NAME="${USERS_TABLE_NAME:-music_shared_users}"
MUSIC_TABLE_NAME="${MUSIC_TABLE_NAME:-music_shared_songs}"
SUBSCRIPTIONS_TABLE_NAME="${SUBSCRIPTIONS_TABLE_NAME:-music_shared_subscriptions}"
S3_BUCKET_NAME="${S3_BUCKET_NAME:-music-shared-private-covers-REPLACE}"
CORS_ALLOW_ORIGINS="${CORS_ALLOW_ORIGINS:-}"
PRESIGNED_URL_TTL="${PRESIGNED_URL_TTL:-3600}"
EC2_APP_USER="${EC2_APP_USER:-ubuntu}"
PORT="${PORT:-8000}"
FLASK_DEBUG="${FLASK_DEBUG:-false}"
AWS_SHARED_CREDENTIALS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-}"
AWS_PROFILE="${AWS_PROFILE:-default}"

APP_ROOT="${APP_ROOT:-/opt/music-app}"
BACKEND_DIR="$APP_ROOT/backend"
FRONTEND_DIR="$APP_ROOT/frontend"

if [[ "$REPO_URL" == *"YOUR_GITHUB_USER"* ]]; then
  echo "ERROR: REPO_URL is still set to placeholder value."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y git python3 python3-venv python3-pip build-essential nginx curl

if [[ ! -d "$APP_ROOT/.git" ]]; then
  git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$APP_ROOT"
else
  cd "$APP_ROOT"
  git fetch --all --prune
  git checkout "$BRANCH"
  git pull --ff-only origin "$BRANCH"
fi

chown -R "$EC2_APP_USER:$EC2_APP_USER" "$APP_ROOT"

sudo -u "$EC2_APP_USER" python3 -m venv "$BACKEND_DIR/.venv"
sudo -u "$EC2_APP_USER" "$BACKEND_DIR/.venv/bin/pip" install --upgrade pip
sudo -u "$EC2_APP_USER" "$BACKEND_DIR/.venv/bin/pip" install -r "$BACKEND_DIR/requirements.txt"

if [[ -z "$CORS_ALLOW_ORIGINS" ]]; then
  PUBLIC_DNS="$(curl -fsS http://169.254.169.254/latest/meta-data/public-hostname || true)"
  PUBLIC_IP="$(curl -fsS http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
  HOST_VALUE="${PUBLIC_DNS:-$PUBLIC_IP}"
  if [[ -n "$HOST_VALUE" ]]; then
    CORS_ALLOW_ORIGINS="http://$HOST_VALUE"
  else
    CORS_ALLOW_ORIGINS="*"
  fi
fi

PRIMARY_ORIGIN="${CORS_ALLOW_ORIGINS%%,*}"
PRIMARY_ORIGIN="${PRIMARY_ORIGIN// /}"
if [[ -z "$PRIMARY_ORIGIN" || "$PRIMARY_ORIGIN" == "*" ]]; then
  PRIMARY_ORIGIN="http://localhost"
fi

cat >"$FRONTEND_DIR/config.js" <<EOF
window.APP_CONFIG = {
  ARCHITECTURE: "EC2",
  API_BASE_URL: "$PRIMARY_ORIGIN",
  ALLOW_HTTP_API: true,
  APP_TITLE: "MusicCloud EC2"
};
EOF

chown "$EC2_APP_USER:$EC2_APP_USER" "$FRONTEND_DIR/config.js"

cat >/etc/music-ec2.env <<EOF
AWS_REGION=$AWS_REGION
USERS_TABLE_NAME=$USERS_TABLE_NAME
MUSIC_TABLE_NAME=$MUSIC_TABLE_NAME
SUBSCRIPTIONS_TABLE_NAME=$SUBSCRIPTIONS_TABLE_NAME
S3_BUCKET_NAME=$S3_BUCKET_NAME
PRESIGNED_URL_TTL=$PRESIGNED_URL_TTL
CORS_ALLOW_ORIGINS=$CORS_ALLOW_ORIGINS
PORT=$PORT
FLASK_DEBUG=$FLASK_DEBUG
HOME=/home/$EC2_APP_USER
EOF

if [[ -n "$AWS_SHARED_CREDENTIALS_FILE" ]]; then
  cat >>/etc/music-ec2.env <<EOF
AWS_SHARED_CREDENTIALS_FILE=$AWS_SHARED_CREDENTIALS_FILE
AWS_PROFILE=$AWS_PROFILE
EOF
fi

chmod 600 /etc/music-ec2.env

cat >/etc/systemd/system/music-ec2-api.service <<EOF
[Unit]
Description=Music EC2 Flask API
After=network.target

[Service]
User=$EC2_APP_USER
WorkingDirectory=$BACKEND_DIR
EnvironmentFile=/etc/music-ec2.env
ExecStart=$BACKEND_DIR/.venv/bin/gunicorn --bind 127.0.0.1:$PORT --workers 2 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/nginx/sites-available/music-ec2.conf <<EOF
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
        proxy_pass http://127.0.0.1:$PORT/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /health {
        proxy_pass http://127.0.0.1:$PORT/health;
        proxy_set_header Host \$host;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/music-ec2.conf /etc/nginx/sites-enabled/music-ec2.conf

nginx -t
systemctl daemon-reload
systemctl enable --now music-ec2-api
systemctl enable --now nginx

echo "EC2 app bootstrap completed successfully on Ubuntu 24.04."
