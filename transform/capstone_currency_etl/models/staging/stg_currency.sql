{{ config(
    materialized='incremental',
    unique_key=['base_currency','end_date']
) }}

{% set lookback_days = var('stg_currency_lookback_days', 1) | int %}

--Exchange-rate APIs:
-- sometimes publish revised data
-- sometimes return missing data for a past date
-- can have temporary glitches
-- your ingestion may also have gaps
-- Lookback fixes all these cases automatically.

with raw_rows as (
  select
    case
      when typeof(value) = 'VARIANT' then value
      when typeof(raw_data) = 'VARIANT' then raw_data
      when raw_data is not null then parse_json(raw_data)
      else null
    end as payload
  from {{ source('RAW_CURRENCY','CAPSTONE_CURRENCY_RAW_TABLE') }}
  where coalesce(value, raw_data) is not null
),

parsed as (
  select
    payload:"end_date"::string               as end_date_str,
    payload:"privacy"::string                as privacy,
    payload:"timestamp"::string              as api_timestamp,
    coalesce(payload:"source"::string, payload:"base"::string) as base_currency,
    payload:"quotes"                                      as quotes_obj,
    payload                                               as payload_variant
  from raw_rows
  where payload is not null
),

outer_flatten as (
  select
    f.key::string as date_key,
    f.value as date_obj,
    p.base_currency,
    p.privacy,
    p.api_timestamp
  from parsed p,
  lateral flatten(input => p.quotes_obj) f
),

inner_flatten as (
  select
    try_to_date(outer_f.date_key, 'YYYY-MM-DD') as end_date,
    upper(coalesce(outer_f.base_currency, 'USD')) as base_currency,
    f.key::string as quote_key,
    try_cast(to_varchar(f.value) as float) as rate,
    outer_f.privacy,
    outer_f.api_timestamp
  from outer_flatten outer_f,
  lateral flatten(input => outer_f.date_obj) f
),

-- normalize and keep only well-formed rows
normalized as (
  select
    end_date,
    base_currency,
    regexp_replace(upper(quote_key), concat('^', upper(base_currency)), '') as target_currency,
    rate,
    api_timestamp
  from inner_flatten
  where end_date is not null
    and rate is not null
),

-- deterministically dedupe by choosing latest api_timestamp per triple
deduped as (
  select
    end_date,
    base_currency,
    target_currency,
    rate
  from (
    select
      *,
      row_number() over (
        partition by base_currency, end_date, target_currency
        order by try_to_timestamp(api_timestamp) desc nulls last
      ) as rn
    from normalized
  ) t
  where rn = 1
),

-- pivot the deduped set
pivoted as (
  select
    base_currency,
    end_date,
    max(case when target_currency = 'EUR' then rate end) as eur_rate,
    max(case when target_currency = 'GBP' then rate end) as gbp_rate,
    max(case when target_currency = 'INR' then rate end) as inr_rate
  from deduped
  group by base_currency, end_date
)

select
  dateadd(day, -1, end_date) as start_date,
  end_date,
  base_currency,
  eur_rate,
  gbp_rate,
  inr_rate,
  current_timestamp() as loaded_at
from pivoted
{% if is_incremental() %}
  -- process new dates plus a short lookback to capture corrections
  where end_date >= dateadd(day, -{{ lookback_days }}, (select coalesce(max(end_date), '1900-01-01'::date) from {{ this }}))
{% endif %}