{{ config(materialized='view') }}

{% set window_days = var('summary_window_days', 365) %}

with recent as (
  select *
  from {{ ref('stg_currency') }}
  where end_date >= dateadd(day, - {{ window_days }}, current_date)
),

agg as (
  select
    base_currency,
    count(*) as observation_count,

    avg(eur_rate)  as avg_eur_rate_30d,
    min(eur_rate)  as min_eur_rate_30d,
    max(eur_rate)  as max_eur_rate_30d,

    avg(gbp_rate)  as avg_gbp_rate_30d,
    min(gbp_rate)  as min_gbp_rate_30d,
    max(gbp_rate)  as max_gbp_rate_30d,

    avg(inr_rate)  as avg_inr_rate_30d,
    min(inr_rate)  as min_inr_rate_30d,
    max(inr_rate)  as max_inr_rate_30d
  from recent
  group by base_currency
)

select *
from agg
order by base_currency