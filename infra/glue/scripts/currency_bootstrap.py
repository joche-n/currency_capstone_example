#!/usr/bin/env python3
"""
currency_raw_ingest_monthly.py — Glue Python Shell

Fetch raw JSON from exchangerate.host/timeframe and store each chunk as-is into S3,
guaranteeing that each chunk is *contained within a single month*.

Output path:
  s3://<S3_OUTPUT>/year=YYYY/month=MM/timeframe_<START>_to_<END>.json

default_arguments = {
  "--S3_OUTPUT"         = "s3://<your-bucket>/raw/"
  "--START_DATE"        = "2025-05-01"
  "--END_DATE"          = "TODAY"
  "--CURRENCIES"        = "USD,GBP,EUR,INR"
  "--ACCESS_KEY"        = "d855d8f59a9b9282283cd86ed533397c"
  "--MAX_DAYS_PER_CALL" = "365"
  "--TempDir"           = "s3://<your-bucket>/temp/"
}

Behavior:
 - Splits the requested date range into month-aligned chunks.
 - Also enforces MAX_DAYS_PER_CALL as an upper bound for chunk size.
 - Retries transient HTTP/parse errors.
 - Fails the job if the API returns an error object or success=false.
"""
import os
import sys
import time
import json
import tempfile
import logging
from datetime import datetime, timedelta, date
from typing import List, Dict, Optional

import boto3
import requests

# ---------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------
print("currency_raw_ingest_monthly.py STARTING - timestamp:", time.time(), "pid:", os.getpid(), flush=True)
logger = logging.getLogger("currency_raw_ingest_monthly")
logger.setLevel(logging.INFO)
fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", "%Y-%m-%dT%H:%M:%S")
sh = logging.StreamHandler(sys.stdout)
sh.setFormatter(fmt)
logger.addHandler(sh)
logger.propagate = False

# ---------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------
API_URL = "https://api.exchangerate.host/timeframe"
DEFAULT_MAX_DAYS = 365
RETRY_COUNT = 3
RETRY_DELAY = 1.5

# ---------------------------------------------------------------------
# CLI parser (accepts --KEY value and --KEY=value)
# ---------------------------------------------------------------------
def parse_cli_args(argv: List[str]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    i = 1
    while i < len(argv):
        token = argv[i]
        if not token.startswith("--"):
            i += 1
            continue
        key = token.lstrip("-")
        if "=" in key:
            k, v = key.split("=", 1)
            out[k.upper()] = v
            i += 1
            continue
        # next token may be a value
        if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
            out[key.upper()] = argv[i + 1]
            i += 2
        else:
            out[key.upper()] = ""
            i += 1
    return out

# ---------------------------------------------------------------------
# Date helpers: month-end and chunk splitter (month aligned + max_days)
# ---------------------------------------------------------------------
def month_end(d: date) -> date:
    """Return last day of the month for date d."""
    # get first day of next month, then -1 day
    if d.month == 12:
        first_next = date(d.year + 1, 1, 1)
    else:
        first_next = date(d.year, d.month + 1, 1)
    return first_next - timedelta(days=1)

def split_into_month_aligned_chunks(start_date: date, end_date: date, max_days: int) -> List[Dict]:
    """
    Return list of dicts {start_date, end_date} where:
      - each chunk lies within a single calendar month
      - no chunk has more than max_days days
    """
    chunks: List[Dict] = []
    cur = start_date
    while cur <= end_date:
        me = month_end(cur)
        # no chunk crosses month boundary: top candidate is month end
        candidate_end = min(me, end_date)
        # also enforce max_days
        max_by_days = cur + timedelta(days=max_days - 1)
        chunk_end = min(candidate_end, max_by_days)
        chunks.append({"start_date": cur.isoformat(), "end_date": chunk_end.isoformat()})
        cur = chunk_end + timedelta(days=1)
    return chunks

# ---------------------------------------------------------------------
# API call + validation
# ---------------------------------------------------------------------
def call_timeframe(start_date: str, end_date: str, currencies: List[str], access_key: Optional[str]) -> dict:
    params = {"start_date": start_date, "end_date": end_date, "currencies": ",".join(currencies)}
    if access_key:
        params["access_key"] = access_key

    last_exc = None
    for attempt in range(1, RETRY_COUNT + 1):
        try:
            logger.info("HTTP GET %s [%s -> %s] (attempt %d)", API_URL, start_date, end_date, attempt)
            r = requests.get(API_URL, params=params, timeout=30)
            logger.info("HTTP status %s for %s -> %s", r.status_code, start_date, end_date)

            # parse JSON body
            try:
                body = r.json()
            except Exception as je:
                logger.error("Failed to parse JSON body: %s. Text prefix: %s", je, (r.text or "")[:1000])
                raise RuntimeError("Non-JSON response from API")

            # API-level error detection (exchangerate.host sometimes returns success=false with HTTP 200)
            if isinstance(body, dict):
                if body.get("success") is False:
                    logger.error("API returned success=false for chunk %s->%s: %s", start_date, end_date, body.get("error"))
                    raise RuntimeError(f"API returned success=false: {body.get('error')}")
                if "error" in body and body.get("error"):
                    logger.error("API returned error object for chunk %s->%s: %s", start_date, end_date, body.get("error"))
                    raise RuntimeError(f"API error: {body.get('error')}")

            if r.status_code >= 400:
                logger.error("HTTP %s for %s->%s: %s", r.status_code, start_date, end_date, (r.text or "")[:1000])
                r.raise_for_status()

            return body
        except Exception as e:
            last_exc = e
            logger.warning("Attempt %d failed for %s->%s: %s", attempt, start_date, end_date, e)
            time.sleep(RETRY_DELAY)
    logger.error("All retries exhausted for %s -> %s. Last error: %s", start_date, end_date, last_exc)
    raise RuntimeError(f"Failed to fetch timeframe {start_date}->{end_date}: {last_exc}")

# ---------------------------------------------------------------------
# Upload helper
# ---------------------------------------------------------------------
def upload_json_to_s3(obj: dict, s3_uri: str):
    if not s3_uri.startswith("s3://"):
        raise ValueError("S3 path must start with s3://")
    if "/currency-script/" in s3_uri or s3_uri.endswith("currency.py"):
        raise RuntimeError("Refusing to upload to script path")

    _, _, rest = s3_uri.partition("s3://")
    bucket, _, key = rest.partition("/")
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        with open(tmp.name, "w") as f:
            json.dump(obj, f, ensure_ascii=False)
        boto3.client("s3").upload_file(tmp.name, bucket, key)
        logger.info("Uploaded raw JSON -> s3://%s/%s", bucket, key)
    finally:
        try:
            os.remove(tmp.name)
        except Exception:
            pass

# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------
def main():
    args = parse_cli_args(sys.argv)
    logger.info("Parsed CLI args: %s", args)

    today_iso = date.today().isoformat()
    # Accept 'TODAY' for END_DATE, and default to today if missing
    def normalize_date_val(val: Optional[str]) -> Optional[str]:
        if val is None:
            return None
        v = val.strip()
        if v == "":
            return None
        if v.upper() == "TODAY":
            return date.today().isoformat()
        return v

    start_date = normalize_date_val(args.get("START_DATE")) or today_iso
    end_date = normalize_date_val(args.get("END_DATE")) or today_iso
    currencies = [c.strip().upper() for c in (args.get("CURRENCIES") or "USD,EUR,INR").split(",") if c.strip()]
    s3_output = args.get("S3_OUTPUT")
    access_key = args.get("ACCESS_KEY")
    max_days = int(args.get("MAX_DAYS_PER_CALL") or DEFAULT_MAX_DAYS)

    if not s3_output:
        logger.error("Missing --S3_OUTPUT s3://bucket/prefix")
        raise SystemExit(2)

    # parse dates
    try:
        sdate = datetime.fromisoformat(start_date).date()
        edate = datetime.fromisoformat(end_date).date()
    except Exception as e:
        logger.exception("Invalid START_DATE/END_DATE: %s", e)
        raise

    if sdate > edate:
        logger.info("START_DATE > END_DATE; swapping")
        sdate, edate = edate, sdate

    # split into month-aligned + max_days chunks
    chunks = split_into_month_aligned_chunks(sdate, edate, max_days)
    logger.info("Split into %d month-aligned chunk(s) for %s -> %s", len(chunks), sdate, edate)

    any_uploaded = False
    for chunk in chunks:
        logger.info("Fetching chunk: %s", chunk)
        data = call_timeframe(chunk["start_date"], chunk["end_date"], currencies, access_key)

        # Validate that the response contains rates/quotes
        if not isinstance(data, dict):
            logger.warning("Unexpected data type for chunk %s: %s. Skipping.", chunk, type(data).__name__)
            continue

        # prefer 'rates' (exchangerate.host) but accept 'quotes'
        if ("rates" not in data or not data.get("rates")) and ("quotes" not in data or not data.get("quotes")):
            logger.warning("No 'rates' or 'quotes' in response for chunk %s; top keys: %s. Skipping.", chunk, list(data.keys()))
            continue

        # Determine partition from chunk's START date (guaranteed inside single month)
        start_dt = datetime.fromisoformat(chunk["start_date"])
        year_str = f"{start_dt.year:04d}"
        month_str = f"{start_dt.month:02d}"
        filename = f"timeframe_{chunk['start_date']}_to_{chunk['end_date']}.json"
        s3_key_prefix = f"{s3_output.rstrip('/')}/year={year_str}/month={month_str}"
        s3_target = f"{s3_key_prefix}/{filename}"

        upload_json_to_s3(data, s3_target)
        any_uploaded = True

    if not any_uploaded:
        logger.error("No chunks uploaded (no valid data). Failing job.")
        raise RuntimeError("No raw JSON uploaded; check API key and parameters")

    logger.info("All month-aligned chunks uploaded successfully.")

# ---------------------------------------------------------------------
if __name__ == "__main__":
    try:
        main()
        logger.info("Job finished successfully.")
    except Exception as e:
        logger.exception("Job failed: %s", e)
        sys.exit(1)