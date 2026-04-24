# EC2 Folder

This folder contains a full EC2-native deployment that serves frontend and backend from the same instance.

## Assignment Constraints Covered
- AWS-only deployment path.
- No Elastic Beanstalk usage.
- Public access on standard ports `80`/`443`.
- IAM constraint handled using pre-created `LabRole`.
- Secure private S3 object access using presigned URLs.
- RESTful methods (`GET`, `POST`, `DELETE`) mapped to DynamoDB operations.
- Branch convention uses `main`.
- EC2 bootstrap targets Ubuntu 24.04.

## Contents
- `backend/`
  - `app.py` Flask API (AWS DynamoDB + private S3 presigned URLs)
  - `create_aws_tables.py` creates shared DynamoDB tables
  - `seed_aws_users.py` inserts initial users
  - `load_aws_data.py` loads songs and uploads cover images to private S3
  - `2026a2_songs.json` source dataset
- `frontend/`
  - `login.html`, `register.html`, `main.html`, `styles.css`, `config.js`
- `infra/`
  - `ec2_user_data.sh` bootstrap script
  - `nginx.conf` reverse-proxy and static hosting template
- `architecture_details.md`
- `deployment_procedure.md`

## Why This Deployment Comes First
EC2 is the foundational deployment because it initializes shared data resources (DynamoDB + private S3 object set) that the ECS and Lambda folders can reuse.

## Deployment Notes
- Use `deployment_procedure.md` for detailed command-by-command instructions.
- `infra/ec2_user_data.sh` is written for Ubuntu 24.04 and defaults to branch `main`.
- A manual fallback path is documented if user-data does not fully execute.
- Credential-file fallback is documented when LabRole permissions are insufficient.

## Required Configuration
Edit `frontend/config.js` and set:
- `API_BASE_URL`
- `ALLOW_HTTP_API` (true for plain HTTP; false when TLS is enabled)

## Quick Start
1. Deploy EC2 using `deployment_procedure.md`.
2. Run table and data scripts from EC2 backend directory.
3. Access app via EC2 public DNS.
