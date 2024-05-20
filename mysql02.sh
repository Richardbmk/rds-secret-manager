#!/bin/bash

# Better and automatic way to access the Database using
# aws cli to get the credentials from aws secret manager

# getsecretvalue() - return the value for a secret
# $1 - the secret id

getsecretvalue() {
  aws secretsmanager get-secret-value --secret-id "$1" --region 'us-east-1'| \
    jq -r .SecretString | \
    jq .
}

if [ $# -ne 1 ]; then
  echo "usage: $0 SecretName"
  exit 1
fi

secret=$(getsecretvalue "$1")

username=$(echo "$secret" | jq -r .username)
password=$(echo "$secret" | jq -r .password)
endpoint="the-db-test.cmbgw4uzua4u.us-east-1.rds.amazonaws.com"

mysql -h "$endpoint" -P 3306 -u "$username" -p"$password"