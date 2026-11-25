-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 6)
-- Подзапросы и логика предикатов

-- Подготовка: удаляем прошлую таблицу расходов, если она осталась от предыдущего запуска
DROP TABLE IF EXISTS lab.l06_buyer_spend;

-- Подготовка (один раз на весь скрипт): считаем по каждому покупателю число заказов, суммы платежей и число платёжных строк
CREATE TABLE lab.l06_buyer_spend AS
SELECT c.customer_unique_id,
       min(c.customer_city) AS customer_city,
       count(DISTINCT o.order_id) AS orders_cnt,
       sum(p.pay_amount) AS spend,
       sum(p.pay_rows) AS pay_rows
FROM olist.customers c
JOIN olist.orders o ON o.customer_id = c.customer_id
JOIN LATERAL (
    SELECT count(*) AS pay_rows, sum(op.payment_value) AS pay_amount
    FROM olist.order_payments op
    WHERE op.order_id = o.order_id
) p ON true
GROUP BY c.customer_unique_id;

-- Подготовка: индекс по customer_unique_id, чтобы эталонный запрос агрегата оставался быстрым
CREATE INDEX l06_buyer_spend_hash_ix ON lab.l06_buyer_spend (customer_unique_id);

-- Подготовка: частичный индекс по расходам только повторных покупателей — под среднее и рейтинг
CREATE INDEX l06_buyer_spend_repeat_ix ON lab.l06_buyer_spend (spend) WHERE orders_cnt > 1;

-- Подготовка: собираем статистику по таблице расходов, чтобы планы запросов были адекватными
ANALYZE lab.l06_buyer_spend;

-- Подготовка: проверяем таблицу расходов — сколько в ней покупателей и не потерялись ли строки платежей
SELECT count(*) AS buyers_total,
       sum(orders_cnt) AS orders_total,
       sum(pay_rows) AS payment_rows_total,
       (SELECT count(*) FROM olist.order_payments) AS payment_rows_in_source,
       (SELECT count(*) FROM olist.orders) AS orders_in_source,
       (SELECT count(*) FROM olist.customers) AS customer_rows,
       (SELECT count(DISTINCT customer_unique_id) FROM olist.customers) AS distinct_unique_ids,
       (SELECT count(*) FROM (
            SELECT customer_unique_id
            FROM olist.customers
            GROUP BY customer_unique_id
            HAVING count(DISTINCT customer_city) > 1
        ) m) AS buyers_with_several_cities
FROM lab.l06_buyer_spend;

-- Сводная характеристика покупателей: всего и повторных, разбивка по числу заказов, средние расходы
WITH buyer_spend AS (
    SELECT customer_unique_id,
           orders_cnt,
           spend,
           pay_rows,
           (row_number() OVER (ORDER BY customer_unique_id))::int AS buyer_num
    FROM lab.l06_buyer_spend
)
SELECT (SELECT count(*) FROM buyer_spend) AS buyers_total,
       count(*) AS repeat_buyers,
       (SELECT count(*) FROM buyer_spend) - count(*) AS single_order_buyers,
       count(*) FILTER (WHERE orders_cnt = 2) AS buyers_2_orders,
       count(*) FILTER (WHERE orders_cnt >= 4) AS buyers_4plus_orders,
       max(orders_cnt) AS max_orders,
       sum(orders_cnt) AS repeat_orders,
       round(avg(spend)::numeric, 2) AS avg_spend,
       round(min(spend)::numeric, 2) AS min_spend,
       round(max(spend)::numeric, 2) AS max_spend,
       round(avg(pay_rows)::numeric, 2) AS avg_payment_rows
FROM buyer_spend
WHERE orders_cnt > 1;

-- Сколько покупателей с расщеплёнными платежами (несколько строк payment на заказ) и как это влияет на агрегацию
WITH buyer_spend AS (
    SELECT customer_unique_id, orders_cnt, spend, pay_rows
    FROM lab.l06_buyer_spend
)
SELECT count(*) AS buyers_total,
       count(*) FILTER (WHERE pay_rows > orders_cnt) AS buyers_with_split_payments,
       count(*) FILTER (WHERE orders_cnt > 1 AND pay_rows > orders_cnt) AS repeat_with_split_payments,
       max(pay_rows) AS max_payment_rows_per_buyer,
       sum(pay_rows) AS payment_rows_total,
       (SELECT count(*) FROM olist.order_payments) AS payment_rows_in_source,
       round(100.0 * sum(pay_rows) / (SELECT count(*) FROM olist.order_payments), 1) AS share_of_payment_rows_pct
FROM buyer_spend;

-- Основное решение: повторные покупатели с расходами выше среднего среди повторных (скалярный подзапрос + коррелированный EXISTS)
WITH buyer_spend AS (
    SELECT customer_unique_id, orders_cnt, spend, pay_rows
    FROM lab.l06_buyer_spend
),
found AS (
    SELECT bs.customer_unique_id,
           bs.orders_cnt,
           bs.spend
    FROM buyer_spend bs
    WHERE bs.orders_cnt > 1
      AND bs.spend > (SELECT avg(b2.spend) FROM buyer_spend b2 WHERE b2.orders_cnt > 1)
      AND EXISTS (
            SELECT 1
            FROM olist.customers c
            JOIN olist.orders o ON o.customer_id = c.customer_id
            WHERE c.customer_unique_id = bs.customer_unique_id
      )
)
SELECT (row_number() OVER (ORDER BY f.spend DESC, f.customer_unique_id))::int AS place,
       f.customer_unique_id AS buyer_hash,
       f.orders_cnt,
       round(f.spend::numeric, 2) AS spend_total
FROM found f
ORDER BY f.spend DESC, f.customer_unique_id
LIMIT 20;

-- Основное решение: только ключевые числа — сколько покупателей найдено и каким получилось среднее
WITH buyer_spend AS (
    SELECT customer_unique_id, orders_cnt, spend
    FROM lab.l06_buyer_spend
),
found AS (
    SELECT bs.customer_unique_id,
           bs.orders_cnt,
           bs.spend
    FROM buyer_spend bs
    WHERE bs.orders_cnt > 1
      AND bs.spend > (SELECT avg(b2.spend) FROM buyer_spend b2 WHERE b2.orders_cnt > 1)
      AND EXISTS (
            SELECT 1
            FROM olist.customers c
            JOIN olist.orders o ON o.customer_id = c.customer_id
            WHERE c.customer_unique_id = bs.customer_unique_id
      )
)
SELECT (SELECT count(*) FROM buyer_spend WHERE orders_cnt > 1) AS repeat_buyers,
       (SELECT round(avg(spend)::numeric, 2) FROM buyer_spend WHERE orders_cnt > 1) AS avg_spend_repeat,
       count(*) AS above_average_buyers,
       sum(orders_cnt) AS orders_of_found,
       round(sum(spend)::numeric, 2) AS spend_of_found,
       round(100.0 * sum(spend) / (SELECT sum(spend) FROM buyer_spend WHERE orders_cnt > 1), 1) AS share_of_repeat_spend_pct
FROM found;

-- Альтернативное решение: предагрегация в CTE и соединение с CTE среднего, без подзапросов в WHERE
WITH buyer_spend AS (
    SELECT customer_unique_id, orders_cnt, spend
    FROM lab.l06_buyer_spend
),
avg_line AS (
    SELECT avg(spend) AS avg_spend
    FROM buyer_spend
    WHERE orders_cnt > 1
),
found AS (
    SELECT bs.customer_unique_id,
           bs.orders_cnt,
           bs.spend
    FROM buyer_spend bs
    JOIN avg_line a ON true
    WHERE bs.orders_cnt > 1
      AND bs.spend > a.avg_spend
)
SELECT (row_number() OVER (ORDER BY f.spend DESC, f.customer_unique_id))::int AS place,
       f.customer_unique_id AS buyer_hash,
       f.orders_cnt,
       round(f.spend::numeric, 2) AS spend_total
FROM found f
ORDER BY f.spend DESC, f.customer_unique_id
LIMIT 20;

-- Сверка основного и альтернативного решений: мощности наборов и расхождения EXCEPT в обе стороны
WITH buyer_spend AS (
    SELECT customer_unique_id, orders_cnt, spend
    FROM lab.l06_buyer_spend
),
main_res AS (
    SELECT bs.customer_unique_id AS buyer_hash
    FROM buyer_spend bs
    WHERE bs.orders_cnt > 1
      AND bs.spend > (SELECT avg(b2.spend) FROM buyer_spend b2 WHERE b2.orders_cnt > 1)
      AND EXISTS (
            SELECT 1
            FROM olist.customers c
            JOIN olist.orders o ON o.customer_id = c.customer_id
            WHERE c.customer_unique_id = bs.customer_unique_id
      )
),
alt_res AS (
    SELECT bs.customer_unique_id AS buyer_hash
    FROM buyer_spend bs
    CROSS JOIN (SELECT avg(b2.spend) AS avg_spend FROM buyer_spend b2 WHERE b2.orders_cnt > 1) a
    WHERE bs.orders_cnt > 1
      AND bs.spend > a.avg_spend
)
SELECT 'rows_main' AS check_name, count(*) AS value FROM main_res
UNION ALL
SELECT 'rows_alt', count(*) FROM alt_res
UNION ALL
SELECT 'main_except_alt', count(*) FROM (SELECT buyer_hash FROM main_res EXCEPT SELECT buyer_hash FROM alt_res) d1
UNION ALL
SELECT 'alt_except_main', count(*) FROM (SELECT buyer_hash FROM alt_res EXCEPT SELECT buyer_hash FROM main_res) d2
UNION ALL
SELECT 'repeat_buyers', count(*) FROM buyer_spend WHERE orders_cnt > 1
UNION ALL
SELECT 'avg_spend_repeat_x1000', round(1000 * avg(spend)) FROM buyer_spend WHERE orders_cnt > 1;

-- Квантор ANY: для покупателей из словаря сравнение расходов с «хотя бы одним» другим повторным покупателем и эквивалент через max
WITH buyer_spend AS (
    SELECT customer_unique_id, orders_cnt, spend
    FROM lab.l06_buyer_spend
),
numbered AS (
    SELECT (row_number() OVER (ORDER BY customer_unique_id))::int AS buyer_num,
           customer_unique_id,
           orders_cnt,
           spend
    FROM buyer_spend
),
pairs AS (
    SELECT s.buyer_num,
           s.spend AS spend,
           o.spend AS other_spend,
           o.orders_cnt AS other_orders_cnt
    FROM numbered s
    JOIN (VALUES (1,1),(1,2),(1,3),(1,5),(1,7),(1,11),(1,13),(1,17),(1,19),(1,23),(2,1),(2,2),(2,3),(2,5),(2,7),(2,11),(2,13),(2,17),(2,19),(2,23),(3,1),(3,2),(3,3),(3,5),(3,7),(3,11),(3,13),(3,17),(3,19),(3,23),(5,1),(5,2),(5,3),(5,5),(5,7),(5,11),(5,13),(5,17),(5,19),(5,23),(7,1),(7,2),(7,3),(7,5),(7,7),(7,11),(7,13),(7,17),(7,19),(7,23),(11,1),(11,2),(11,3),(11,5),(11,7),(11,11),(11,13),(11,17),(11,19),(11,23),(13,1),(13,2),(13,3),(13,5),(13,7),(13,11),(13,13),(13,17),(13,19),(13,23),(17,1),(17,2),(17,3),(17,5),(17,7),(17,11),(17,13),(17,17),(17,19),(17,23),(19,1),(19,2),(19,3),(19,5),(19,7),(19,11),(19,13),(19,17),(19,19),(19,23),(23,1),(23,2),(23,3),(23,5),(23,7),(23,11),(23,13),(23,17),(23,19),(23,23)) AS d(buyer_num, other_num)
             ON d.buyer_num = s.buyer_num
    JOIN numbered o ON o.buyer_num = d.other_num
)
SELECT p.buyer_num,
       round(max(p.spend)::numeric, 2) AS spend_total,
       count(*) AS checked_others,
       bool_or(p.other_orders_cnt > 1 AND p.spend > p.other_spend) AS gt_any_repeat,
       bool_and(NOT (p.other_orders_cnt > 1) OR p.spend <= p.other_spend) AS gt_max_repeat,
       bool_or(p.other_orders_cnt > 1 AND p.spend < p.other_spend) AS lt_any_repeat,
       bool_and(NOT (p.other_orders_cnt > 1) OR p.spend >= p.other_spend) AS lt_min_repeat
FROM pairs p
GROUP BY p.buyer_num
ORDER BY p.buyer_num;

-- Квантор ALL: сколько покупателей тратят больше ВСЕХ, меньше ВСЕХ и сколько попадают в промежуток, сверка ALL с max/min
WITH buyer_spend AS (
    SELECT customer_unique_id, orders_cnt, spend
    FROM lab.l06_buyer_spend
),
numbered AS (
    SELECT (row_number() OVER (ORDER BY customer_unique_id))::int AS buyer_num,
           customer_unique_id,
           orders_cnt,
           spend
    FROM buyer_spend
),
sample AS (
    SELECT n.buyer_num, n.spend
    FROM numbered n
    JOIN (VALUES (1),(2),(3),(5),(7),(11),(13),(17),(19),(23)) AS d(buyer_num) ON d.buyer_num = n.buyer_num
),
checked AS (
    SELECT s.buyer_num,
           s.spend,
           bool_or(s.spend > a.spend) AS gt_some,
           count(*) AS others_cnt
    FROM sample s
    CROSS JOIN (SELECT spend FROM buyer_spend WHERE orders_cnt > 1) a
    GROUP BY s.buyer_num, s.spend
)
SELECT c.buyer_num,
       round(c.spend::numeric, 2) AS spend_total,
       c.others_cnt AS repeat_buyers,
       c.gt_some AS gt_any,
       NOT c.gt_some AS gt_all,
       c.spend > th.max_spend AS gt_max,
       c.spend < th.min_spend AS lt_min,
       c.spend BETWEEN th.min_spend AND th.max_spend AS between_min_max
FROM checked c
CROSS JOIN (SELECT min(spend) AS min_spend, max(spend) AS max_spend FROM buyer_spend WHERE orders_cnt > 1) th
ORDER BY c.buyer_num;

-- IN против EXISTS и NOT IN против NOT EXISTS на одном предикате: покупатель из города sao paulo
WITH sp_buyers AS (
    SELECT DISTINCT customer_unique_id
    FROM lab.l06_buyer_spend
    WHERE customer_city = 'sao paulo'
)
SELECT 'in' AS formulation, count(*) AS rows_found
FROM olist.customers c
WHERE c.customer_unique_id IN (SELECT b.customer_unique_id FROM sp_buyers b)
UNION ALL
SELECT 'exists', count(*)
FROM olist.customers c
WHERE EXISTS (SELECT 1 FROM sp_buyers b WHERE b.customer_unique_id = c.customer_unique_id)
UNION ALL
SELECT 'not_in', count(*)
FROM olist.customers c
WHERE c.customer_unique_id NOT IN (SELECT b.customer_unique_id FROM sp_buyers b)
UNION ALL
SELECT 'not_exists', count(*)
FROM olist.customers c
WHERE NOT EXISTS (SELECT 1 FROM sp_buyers b WHERE b.customer_unique_id = c.customer_unique_id);

-- Ловушка NOT IN: в подзапрос добавлена строка NULL — NOT IN возвращает пусто, NOT EXISTS остаётся верным
WITH sp_buyers AS (
    SELECT DISTINCT customer_unique_id
    FROM lab.l06_buyer_spend
    WHERE customer_city = 'sao paulo'
    UNION ALL
    SELECT NULL::text
)
SELECT 'not_in_with_null' AS formulation, count(*) AS rows_found
FROM olist.customers c
WHERE c.customer_unique_id NOT IN (SELECT b.customer_unique_id FROM sp_buyers b)
UNION ALL
SELECT 'not_exists_with_null', count(*)
FROM olist.customers c
WHERE NOT EXISTS (SELECT 1 FROM sp_buyers b WHERE b.customer_unique_id = c.customer_unique_id);

-- Итоговая сводка: ключевые числа всех решений в одном результате с метками
WITH buyer_spend AS (
    SELECT customer_unique_id, orders_cnt, spend
    FROM lab.l06_buyer_spend
),
main_res AS (
    SELECT bs.customer_unique_id AS buyer_hash
    FROM buyer_spend bs
    WHERE bs.orders_cnt > 1
      AND bs.spend > (SELECT avg(b2.spend) FROM buyer_spend b2 WHERE b2.orders_cnt > 1)
      AND EXISTS (
            SELECT 1
            FROM olist.customers c
            JOIN olist.orders o ON o.customer_id = c.customer_id
            WHERE c.customer_unique_id = bs.customer_unique_id
      )
),
alt_res AS (
    SELECT bs.customer_unique_id AS buyer_hash
    FROM buyer_spend bs
    CROSS JOIN (SELECT avg(b2.spend) AS avg_spend FROM buyer_spend b2 WHERE b2.orders_cnt > 1) a
    WHERE bs.orders_cnt > 1
      AND bs.spend > a.avg_spend
),
threshold AS (
    SELECT avg(spend) AS avg_spend,
           min(spend) AS min_spend,
           max(spend) AS max_spend
    FROM buyer_spend
    WHERE orders_cnt > 1
),
results AS (
    SELECT 'buyers_total' AS metric, (SELECT count(*) FROM buyer_spend)::numeric AS value
    UNION ALL SELECT 'repeat_buyers', (SELECT count(*) FROM buyer_spend WHERE orders_cnt > 1)
    UNION ALL SELECT 'avg_spend_repeat', (SELECT round(avg_spend::numeric, 2) FROM threshold)
    UNION ALL SELECT 'result_main', (SELECT count(*) FROM main_res)
    UNION ALL SELECT 'result_alt', (SELECT count(*) FROM alt_res)
    UNION ALL SELECT 'diff_main_alt', (SELECT count(*) FROM (SELECT buyer_hash FROM main_res EXCEPT SELECT buyer_hash FROM alt_res) d)
    UNION ALL SELECT 'avg_spend_all_buyers', (SELECT round(avg(spend)::numeric, 2) FROM buyer_spend)
    UNION ALL SELECT 'median_spend_repeat', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY spend)::numeric, 2) FROM buyer_spend WHERE orders_cnt > 1)
    UNION ALL SELECT 'share_of_repeat_spend_pct', (SELECT round(100.0 * sum(spend) FILTER (WHERE spend > t.avg_spend) / sum(spend), 1) FROM buyer_spend, threshold t WHERE orders_cnt > 1)
)
SELECT metric,
       value::text AS value_text,
       CASE WHEN value = round(value) THEN value::bigint::text END AS value_int,
       round(value::numeric, 2) AS value_num
FROM results
ORDER BY metric;

-- Убираем таблицу расходов, чтобы повторный запуск начинался с чистого листа
DROP TABLE IF EXISTS lab.l06_buyer_spend;
