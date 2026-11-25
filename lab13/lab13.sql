-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 14)
-- EXPLAIN ANALYZE и оптимизация запросов

-- Пункт 1: контроль исходного состояния — в схеме olist есть только первичные ключи
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'olist'
ORDER BY indexname;

-- Пункт 1/2: исходная неудачная форма — заказы клиентов соединяются с сырой geolocation по префиксу, география размножает позиции заказов, самый дорогой участок плана
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.customer_state,
       c.customer_city,
       g.geolocation_lat AS lat,
       g.geolocation_lng AS lng,
       count(*) AS items_cnt,
       round(sum(oi.price), 2) AS revenue
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi ON oi.order_id = o.order_id
JOIN olist.geolocation AS g ON g.geolocation_zip_code_prefix = c.customer_zip_code_prefix
GROUP BY c.customer_state, c.customer_city, g.geolocation_lat, g.geolocation_lng;

-- Пункт 2/3: разбор исходного результата — фактическое число строк, число городов и коэффициент размножения против заявленного числа позиций
SELECT count(*) AS rows_returned,
       count(DISTINCT st) AS distinct_cities,
       count(DISTINCT st || '/' || lat || '/' || lng) AS distinct_groups,
       round(count(*)::numeric / count(DISTINCT st), 1) AS rows_per_city,
       count(DISTINCT items_cnt) AS sample_measure
FROM (
    SELECT c.customer_state || '/' || c.customer_city AS st,
           g.geolocation_lat AS lat,
           g.geolocation_lng AS lng,
           count(*) AS items_cnt
    FROM olist.customers AS c
    JOIN olist.orders AS o ON o.customer_id = c.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.geolocation AS g ON g.geolocation_zip_code_prefix = c.customer_zip_code_prefix
    GROUP BY c.customer_state, c.customer_city, g.geolocation_lat, g.geolocation_lng
) AS src;

-- Пункт 4/6: новая форма — география предварительно свёрнута до одной строки на префикс (avg координат), соединение становится 1:N, тот же бизнес-результат считается один раз на заказ
EXPLAIN (ANALYZE, BUFFERS)
WITH geo_once AS (
    SELECT geolocation_zip_code_prefix AS zip_prefix,
           avg(geolocation_lat) AS lat_avg,
           avg(geolocation_lng) AS lng_avg
    FROM olist.geolocation
    GROUP BY geolocation_zip_code_prefix
)
SELECT c.customer_state,
       c.customer_city,
       g.lat_avg AS lat,
       g.lng_avg AS lng,
       count(*) AS items_cnt,
       round(sum(oi.price), 2) AS revenue
FROM olist.customers AS c
JOIN olist.orders AS o ON o.customer_id = c.customer_id
JOIN olist.order_items AS oi ON oi.order_id = o.order_id
JOIN geo_once AS g ON g.zip_prefix = c.customer_zip_code_prefix
GROUP BY c.customer_state, c.customer_city, g.lat_avg, g.lng_avg;

-- Пункт 5а: префиксы клиентов без единого наблюдения в geolocation — их отбрасывает INNER JOIN в обеих формах, потеря одинакова
SELECT c.customer_zip_code_prefix AS zip_prefix,
       min(c.customer_city) AS city,
       min(c.customer_state) AS state,
       count(DISTINCT c.customer_id) AS customers
FROM olist.customers AS c
WHERE NOT EXISTS (SELECT 1 FROM olist.geolocation AS g
                  WHERE g.geolocation_zip_code_prefix = c.customer_zip_code_prefix)
GROUP BY c.customer_zip_code_prefix
ORDER BY customers DESC, zip_prefix
LIMIT 10;

-- Пункт 5б: полная сводка по потерям — сколько префиксов, городов и клиентов не доходит до географии
SELECT count(DISTINCT zip_prefix) AS prefixes_without_geo,
       count(DISTINCT st) AS cities_affected,
       count(DISTINCT cust) AS customers_affected,
       count(*) AS rows_represented
FROM (
    SELECT c.customer_zip_code_prefix AS zip_prefix,
           c.customer_state || '/' || c.customer_city AS st,
           c.customer_id AS cust
    FROM olist.customers AS c
    WHERE NOT EXISTS (SELECT 1 FROM olist.geolocation AS g
                      WHERE g.geolocation_zip_code_prefix = c.customer_zip_code_prefix)
) AS lost;

-- Пункт 5в: EXCEPT-проверка в обе стороны по бизнес-ключу (штат, город, префикс) и контроль сумм
WITH items AS (
    SELECT c.customer_state AS st, c.customer_city AS city,
           c.customer_zip_code_prefix AS p,
           count(*)::bigint AS items_cnt, sum(oi.price) AS revenue
    FROM olist.customers AS c
    JOIN olist.orders AS o ON o.customer_id = c.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    GROUP BY c.customer_state, c.customer_city, c.customer_zip_code_prefix
),
geo AS (
    SELECT geolocation_zip_code_prefix AS zp, count(*)::bigint AS geo_rows
    FROM olist.geolocation
    GROUP BY geolocation_zip_code_prefix
),
orig AS (
    SELECT items.st AS st, items.city AS city, items.p AS p,
           (items.items_cnt * geo.geo_rows)::bigint AS items_cnt,
           (items.revenue * geo.geo_rows) AS revenue
    FROM items
    JOIN geo ON geo.zp = items.p
),
opt AS (
    SELECT items.st AS st, items.city AS city, items.p AS p,
           items.items_cnt AS items_cnt, items.revenue AS revenue
    FROM items
    JOIN geo ON geo.zp = items.p
)
SELECT (SELECT count(*) FROM (SELECT st, city, p FROM orig EXCEPT SELECT st, city, p FROM opt) AS a) AS keys_orig_minus_opt,
       (SELECT count(*) FROM (SELECT st, city, p FROM opt EXCEPT SELECT st, city, p FROM orig) AS b) AS keys_opt_minus_orig,
       (SELECT count(*) FROM orig) AS rows_orig_duplicated,
       (SELECT count(*) FROM opt) AS rows_opt_without_duplication,
       (SELECT sum(items_cnt) FROM orig) AS items_orig,
       (SELECT sum(items_cnt) FROM opt) AS items_opt,
       (SELECT sum(revenue) FROM orig) AS revenue_orig,
       (SELECT sum(revenue) FROM opt) AS revenue_opt;

-- Пункт 5г: EXCEPT-проверка в обе стороны по мерке «число позиций» после свёртки исходной формы до DISTINCT
WITH items AS (
    SELECT c.customer_state AS st, c.customer_city AS city,
           c.customer_zip_code_prefix AS p, count(*)::bigint AS items_cnt
    FROM olist.customers AS c
    JOIN olist.orders AS o ON o.customer_id = c.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    GROUP BY c.customer_state, c.customer_city, c.customer_zip_code_prefix
),
geo AS (
    SELECT geolocation_zip_code_prefix AS zp, count(*)::bigint AS geo_rows
    FROM olist.geolocation
    GROUP BY geolocation_zip_code_prefix
),
orig AS (
    SELECT (items.items_cnt * geo.geo_rows)::bigint AS items_cnt, items.st AS st, items.city AS city, items.p AS p
    FROM items
    JOIN geo ON geo.zp = items.p
),
opt AS (
    SELECT items.items_cnt AS items_cnt, items.st AS st, items.city AS city, items.p AS p
    FROM items
    JOIN geo ON geo.zp = items.p
)
SELECT (SELECT count(*) FROM (SELECT DISTINCT items_cnt, st, city, p FROM orig
                              EXCEPT SELECT items_cnt, st, city, p FROM opt) AS a) AS folds_orig_minus_opt,
       (SELECT count(*) FROM (SELECT items_cnt, st, city, p FROM opt
                              EXCEPT SELECT DISTINCT items_cnt, st, city, p FROM orig) AS b) AS folds_opt_minus_orig,
       (SELECT round(avg(items_cnt), 1) FROM orig) AS avg_dup_items_per_row,
       (SELECT round(avg(items_cnt), 1) FROM opt) AS avg_real_items_per_row;

-- Пункт 6/7: мощности промежуточных отношений — реляционная алгебра на числах: сырая география, свёрнутая география, позиции заказов
WITH geo_once AS (
    SELECT geolocation_zip_code_prefix AS zip_prefix,
           avg(geolocation_lat) AS lat_avg,
           avg(geolocation_lng) AS lng_avg
    FROM olist.geolocation
    GROUP BY geolocation_zip_code_prefix
),
lines AS (
    SELECT c.customer_state AS st, c.customer_city AS city,
           c.customer_zip_code_prefix AS p
    FROM olist.customers AS c
    JOIN olist.orders AS o ON o.customer_id = c.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
)
SELECT 'geolocation (сырая)' AS relation, count(*)::bigint AS rows FROM olist.geolocation
UNION ALL
SELECT 'geo_once (1 строка на префикс)', count(*) FROM geo_once
UNION ALL
SELECT 'customers', count(*) FROM olist.customers
UNION ALL
SELECT 'order_items (заказы × позиции)', count(*) FROM lines
UNION ALL
SELECT 'исходная форма: join с георастром', count(*) FROM lines AS l
    JOIN olist.geolocation AS g ON g.geolocation_zip_code_prefix = l.p
UNION ALL
SELECT 'оптимизированная форма: join с geo_once', count(*) FROM lines AS l
    JOIN geo_once AS g ON g.zip_prefix = l.p;
