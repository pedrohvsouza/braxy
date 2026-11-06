#!/bin/sh
# LocalStack ready hook: create the private Braxy bucket (idempotent).
awslocal s3api create-bucket --bucket braxy >/dev/null 2>&1 || true
echo "[braxy] s3 bucket ready"
