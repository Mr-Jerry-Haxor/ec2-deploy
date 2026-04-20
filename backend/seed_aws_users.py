import os
from datetime import datetime, timezone

import boto3

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DYNAMODB_ENDPOINT_URL = os.getenv("DYNAMODB_ENDPOINT_URL", "").strip()
USERS_TABLE_NAME = os.getenv("USERS_TABLE_NAME", "music_shared_users")

SEED_USERS = [
    {"email": "alex@example.com", "username": "Alex", "password": "pass123"},
    {"email": "bella@example.com", "username": "Bella", "password": "pass123"},
    {"email": "chris@example.com", "username": "Chris", "password": "pass123"},
    {"email": "diana@example.com", "username": "Diana", "password": "pass123"},
    {"email": "ethan@example.com", "username": "Ethan", "password": "pass123"},
    {"email": "fiona@example.com", "username": "Fiona", "password": "pass123"},
    {"email": "george@example.com", "username": "George", "password": "pass123"},
    {"email": "hana@example.com", "username": "Hana", "password": "pass123"},
    {"email": "isaac@example.com", "username": "Isaac", "password": "pass123"},
    {"email": "julia@example.com", "username": "Julia", "password": "pass123"},
]


def _resource_kwargs():
    kwargs = {"region_name": AWS_REGION}
    if DYNAMODB_ENDPOINT_URL:
        kwargs["endpoint_url"] = DYNAMODB_ENDPOINT_URL
    return kwargs


def _now_iso():
    return datetime.now(timezone.utc).isoformat()


def main():
    dynamodb = boto3.resource("dynamodb", **_resource_kwargs())
    users_table = dynamodb.Table(USERS_TABLE_NAME)

    for user in SEED_USERS:
        users_table.put_item(
            Item={
                "email": user["email"],
                "username": user["username"],
                "user_name": user["username"],
                "password": user["password"],
                "created_at": _now_iso(),
            }
        )

    print(f"Inserted {len(SEED_USERS)} users into {USERS_TABLE_NAME}")


if __name__ == "__main__":
    main()
