{% macro refresh_external_table(database, schema, table, complete=false) -%}
  {% set stmt = "ALTER EXTERNAL TABLE " ~ database ~ "." ~ schema ~ "." ~ table ~ " REFRESH" %}
  {% if complete %} {% set stmt = stmt ~ " COMPLETE" %} {% endif %}
  {{ run_query(stmt) }}
{%- endmacro %}