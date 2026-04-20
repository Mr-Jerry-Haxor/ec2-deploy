# EC2 Architecture Details

## Purpose
This architecture runs both frontend and backend directly on a single EC2 instance using Nginx (static + reverse proxy) and Gunicorn (Flask API).

## Diagram
```mermaid
flowchart LR
  U[User Browser] --> EC2[EC2 Instance:80]
  EC2 --> NG[Nginx static + reverse proxy]
  NG --> API[Gunicorn Flask API :8000]
  API --> DDB[(DynamoDB)]
  API --> S3[(Private S3 Music Covers)]
```

## Resource Naming Strategy
Use an `ec2a-` prefix for EC2 compute resources and `shared-` prefix for data resources:
- EC2 instance name: `ec2a-music-app`
- Security group: `ec2a-music-sg`
- IAM role: `ec2a-music-role`
- Shared DynamoDB tables:
  - `music_shared_users`
  - `music_shared_songs`
  - `music_shared_subscriptions`
- Shared private S3 bucket: `music-shared-private-covers-<account>-<region>`

## Connectivity Model
- Frontend URL: `http://<ec2-public-dns>/login.html`
- API URL: `http://<ec2-public-dns>/api/*`
- Both are served from the same EC2 host, so CORS can be narrowed to that host.

## Security Model
- EC2 IAM role provides DynamoDB + S3 access.
- Frontend stores login state only in `sessionStorage`.
- `main.html` performs an immediate redirect to `login.html` when no authenticated session exists.
- Nginx exposes only port 80 publicly; Gunicorn remains private on loopback port 8000.
