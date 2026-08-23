#!/usr/bin/env python3
"""Apply Hetzner-aligned S3 lifecycle rules using the rclone hetzner remote.

Does not expire current objects. Only:
  - noncurrent versions after 90 days
  - aborted multipart fragments after 7 days
  - leftover delete markers
"""
from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import hmac
import json
import subprocess
import sys
import urllib.error
import urllib.request

REMOTE = "hetzner"
DEFAULT_NONCURRENT_DAYS = 90
MULTIPART_ABORT_DAYS = 7


def lifecycle_xml(noncurrent_days: int) -> str:
    return f"""\
<?xml version="1.0" encoding="UTF-8"?>
<LifecycleConfiguration>
  <Rule>
    <ID>noncurrent-and-multipart</ID>
    <Filter></Filter>
    <Status>Enabled</Status>
    <NoncurrentVersionExpiration>
      <NoncurrentDays>{noncurrent_days}</NoncurrentDays>
    </NoncurrentVersionExpiration>
    <AbortIncompleteMultipartUpload>
      <DaysAfterInitiation>{MULTIPART_ABORT_DAYS}</DaysAfterInitiation>
    </AbortIncompleteMultipartUpload>
  </Rule>
  <Rule>
    <ID>expired-delete-markers</ID>
    <Filter></Filter>
    <Status>Enabled</Status>
    <Expiration>
      <ExpiredObjectDeleteMarker>true</ExpiredObjectDeleteMarker>
    </Expiration>
  </Rule>
</LifecycleConfiguration>
"""


def rclone_dump() -> dict:
    out = subprocess.check_output(["rclone", "config", "dump"], text=True)
    return json.loads(out)


def sign(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def signing_key(secret: str, datestamp: str, region: str) -> bytes:
    k_date = sign(("AWS4" + secret).encode("utf-8"), datestamp)
    k_region = hmac.new(k_date, region.encode("utf-8"), hashlib.sha256).digest()
    k_service = hmac.new(k_region, b"s3", hashlib.sha256).digest()
    return hmac.new(k_service, b"aws4_request", hashlib.sha256).digest()


def put_lifecycle(
    bucket: str,
    access_key: str,
    secret_key: str,
    endpoint: str,
    region: str,
    noncurrent_days: int,
) -> None:
    # Virtual-hosted-style: bucket.endpoint — Hetzner rclone provider uses this.
    vhost = f"{bucket}.{endpoint}"
    body = lifecycle_xml(noncurrent_days).encode("utf-8")
    payload_hash = hashlib.sha256(body).hexdigest()
    content_md5_b64 = base64.b64encode(hashlib.md5(body).digest()).decode("ascii")

    now = dt.datetime.now(dt.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    canonical_uri = "/"
    canonical_query = "lifecycle="
    canonical_headers = (
        f"content-md5:{content_md5_b64}\n"
        f"host:{vhost}\n"
        f"x-amz-content-sha256:{payload_hash}\n"
        f"x-amz-date:{amz_date}\n"
    )
    signed_headers = "content-md5;host;x-amz-content-sha256;x-amz-date"
    canonical_request = "\n".join(
        [
            "PUT",
            canonical_uri,
            canonical_query,
            canonical_headers,
            signed_headers,
            payload_hash,
        ]
    )
    scope = f"{datestamp}/{region}/s3/aws4_request"
    string_to_sign = "\n".join(
        [
            "AWS4-HMAC-SHA256",
            amz_date,
            scope,
            hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
        ]
    )
    sig = hmac.new(signing_key(secret_key, datestamp, region), string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()
    auth = (
        f"AWS4-HMAC-SHA256 Credential={access_key}/{scope}, "
        f"SignedHeaders={signed_headers}, Signature={sig}"
    )
    req = urllib.request.Request(
        f"https://{vhost}/?lifecycle",
        data=body,
        method="PUT",
        headers={
            "Host": vhost,
            "Content-Type": "application/xml",
            "Content-MD5": content_md5_b64,
            "Content-Length": str(len(body)),
            "x-amz-content-sha256": payload_hash,
            "x-amz-date": amz_date,
            "Authorization": auth,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            if resp.status not in (200, 204):
                raise RuntimeError(f"HTTP {resp.status}: {resp.read()[:500]!r}")
    except urllib.error.HTTPError as exc:
        detail = exc.read()[:800].decode("utf-8", "replace")
        raise RuntimeError(f"HTTP {exc.code}: {detail}") from exc


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("bucket")
    parser.add_argument("--days", type=int, default=DEFAULT_NONCURRENT_DAYS)
    args = parser.parse_args()
    if args.days <= 0:
        print("--days must be a positive integer", file=sys.stderr)
        return 1

    cfg = rclone_dump().get(REMOTE)
    if not cfg:
        print(f"rclone remote {REMOTE!r} not found", file=sys.stderr)
        return 1

    access_key = cfg.get("access_key_id")
    secret_key = cfg.get("secret_access_key")
    endpoint = (cfg.get("endpoint") or "").removeprefix("https://").removeprefix("http://")
    region = cfg.get("region") or "us-east-1"
    if not access_key or not secret_key or not endpoint:
        print("incomplete rclone hetzner credentials", file=sys.stderr)
        return 1

    put_lifecycle(args.bucket, access_key, secret_key, endpoint, region, args.days)
    return 0


if __name__ == "__main__":
    sys.exit(main())
