{{ config(materialized='view') }}

with recent as (
  select
    end_date,
    base_currency,
    eur_rate,
    gbp_rate,
    inr_rate
  from {{ ref('stg_currency') }}
  -- adjust window_days if you want (or use var like earlier)
  where end_date >= dateadd(day, -90, current_date)
)

select
  end_date,
  base_currency,
  -- if there are duplicates per (end_date, base_currency) take avg (or max/min as you prefer)
  avg(eur_rate)  as eur_rate,
  avg(gbp_rate)  as gbp_rate,
  avg(inr_rate)  as inr_rate
from recent
group by 1,2
order by 1,2