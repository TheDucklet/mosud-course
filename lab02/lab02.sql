-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 2)
-- Множества и мультимножества в SQL

-- исходное отношение: отношения olist.customers и olist.orders, связь 1:N по customer_id, отбираются только delivered-заказы
SELECT
    'olist.customers (customer_id, customer_state)' AS rel_1,
    'olist.orders (order_id, customer_id, order_status)' AS rel_2,
    'orders.customer_id -> customers.customer_id, кратность 1:N' AS join_rule;

-- пункт 1: множество A = product_id, купленные клиентами штата MA в delivered-заказах; проверка мощности (count(*) и count(DISTINCT product_id))
SELECT
    count(*) AS cnt_star,
    count(DISTINCT product_id) AS cnt_distinct,
    count(*) - count(DISTINCT product_id) AS duplicated_rows
FROM (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'MA'
      AND o.order_status = 'delivered'
) AS a;

-- пункт 1: множество B = product_id, купленные клиентами штата PI в delivered-заказах; проверка мощности (count(*) и count(DISTINCT product_id))
SELECT
    count(*) AS cnt_star,
    count(DISTINCT product_id) AS cnt_distinct,
    count(*) - count(DISTINCT product_id) AS duplicated_rows
FROM (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'PI'
      AND o.order_status = 'delivered'
) AS b;

-- пункт 1: мощности A, B, A ∪ B, A ∩ B, A − B, B − A в одном результате для сопоставления
WITH a AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'MA'
      AND o.order_status = 'delivered'
),
b AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'PI'
      AND o.order_status = 'delivered'
)
SELECT 'A (MA)' AS set_name, count(*) AS cardinality FROM a
UNION ALL
SELECT 'B (PI)', count(*) FROM b
UNION ALL
SELECT 'A UNION B', count(*) FROM (SELECT product_id FROM a UNION SELECT product_id FROM b) AS u
UNION ALL
SELECT 'A INTERSECT B', count(*) FROM (SELECT product_id FROM a INTERSECT SELECT product_id FROM b) AS i
UNION ALL
SELECT 'A EXCEPT B', count(*) FROM (SELECT product_id FROM a EXCEPT SELECT product_id FROM b) AS ab
UNION ALL
SELECT 'B EXCEPT A', count(*) FROM (SELECT product_id FROM b EXCEPT SELECT product_id FROM a) AS ba
ORDER BY cardinality DESC, set_name;

-- пункт 2: A ∪ B через UNION (устраняет дубликаты) и через UNION ALL (сохраняет их); разница = |A ∩ B|
WITH a AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'MA'
      AND o.order_status = 'delivered'
),
b AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'PI'
      AND o.order_status = 'delivered'
)
SELECT 'UNION (множество)' AS operation, count(*) AS rows_cnt FROM (SELECT product_id FROM a UNION SELECT product_id FROM b) AS u
UNION ALL
SELECT 'UNION ALL (мультимножество)', count(*) FROM (SELECT product_id FROM a UNION ALL SELECT product_id FROM b) AS ua;

-- пункт 3: A ∩ B через INTERSECT — товары, купленные и в MA, и в PI
SELECT count(*) AS cnt_intersect, count(DISTINCT product_id) AS cnt_distinct
FROM (
    SELECT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'MA'
      AND o.order_status = 'delivered'
    INTERSECT
    SELECT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'PI'
      AND o.order_status = 'delivered'
) AS i;

-- пункт 4: A − B и B − A через EXCEPT, мощности и примеры товаров в каждом направлении
WITH a AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'MA'
      AND o.order_status = 'delivered'
),
b AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'PI'
      AND o.order_status = 'delivered'
)
SELECT 'A EXCEPT B' AS operation, count(*) AS rows_cnt, min(product_id) AS example_id
FROM (SELECT product_id FROM a EXCEPT SELECT product_id FROM b) AS ab
UNION ALL
SELECT 'B EXCEPT A', count(*), min(product_id)
FROM (SELECT product_id FROM b EXCEPT SELECT product_id FROM a) AS ba;

-- пункт 5: коммутативность — (A ∪ B) = (B ∪ A) и (A ∩ B) = (B ∩ A); пустая разность в обе стороны подтверждает равенство
WITH a AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'MA'
      AND o.order_status = 'delivered'
),
b AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'PI'
      AND o.order_status = 'delivered'
),
ab AS (SELECT product_id FROM a UNION SELECT product_id FROM b),
ba AS (SELECT product_id FROM b UNION SELECT product_id FROM a),
abi AS (SELECT product_id FROM a INTERSECT SELECT product_id FROM b),
bai AS (SELECT product_id FROM b INTERSECT SELECT product_id FROM a)
SELECT '|A ∪ B|' AS quantity, (SELECT count(*) FROM ab) AS direct_op, (SELECT count(*) FROM ba) AS reversed_op
UNION ALL
SELECT '|B ∪ A| (reversed)', (SELECT count(*) FROM ba), (SELECT count(*) FROM ab)
UNION ALL
SELECT '|(A ∪ B) − (B ∪ A)|', (SELECT count(*) FROM (SELECT product_id FROM ab EXCEPT SELECT product_id FROM ba) AS x), (SELECT count(*) FROM (SELECT product_id FROM ba EXCEPT SELECT product_id FROM ab) AS y)
UNION ALL
SELECT '|(A ∩ B) − (B ∩ A)|', (SELECT count(*) FROM (SELECT product_id FROM abi EXCEPT SELECT product_id FROM bai) AS x), (SELECT count(*) FROM (SELECT product_id FROM bai EXCEPT SELECT product_id FROM abi) AS y);

-- пункт 6: разность некоммутативна — |A − B| ≠ |B − A| и множества различны
WITH a AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'MA'
      AND o.order_status = 'delivered'
),
b AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'PI'
      AND o.order_status = 'delivered'
),
ab AS (SELECT product_id FROM a EXCEPT SELECT product_id FROM b),
ba AS (SELECT product_id FROM b EXCEPT SELECT product_id FROM a)
SELECT
    (SELECT count(*) FROM ab) AS size_a_minus_b,
    (SELECT count(*) FROM ba) AS size_b_minus_a,
    (SELECT count(*) FROM (SELECT product_id FROM ab INTERSECT SELECT product_id FROM ba) AS x) AS size_intersection,
    (SELECT count(*) FROM (SELECT product_id FROM ab EXCEPT SELECT product_id FROM ba) AS x) AS size_sym_diff_one_side,
    (SELECT count(*) FROM (SELECT product_id FROM ba EXCEPT SELECT product_id FROM ab) AS y) AS size_sym_diff_other_side;

-- пункт 7: пересечение без INTERSECT через EXISTS; эквивалентность проверяется разностью в обе стороны
WITH a AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'MA'
      AND o.order_status = 'delivered'
),
b AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'PI'
      AND o.order_status = 'delivered'
),
via_intersect AS (SELECT product_id FROM a INTERSECT SELECT product_id FROM b),
via_exists AS (
    SELECT a.product_id
    FROM a
    WHERE EXISTS (SELECT 1 FROM b WHERE b.product_id = a.product_id)
)
SELECT '|INTERSECT|' AS quantity, (SELECT count(*) FROM via_intersect) AS axis, (SELECT count(*) FROM via_exists) AS other,
       (SELECT count(*) FROM (SELECT product_id FROM via_intersect EXCEPT SELECT product_id FROM via_exists) AS x) AS diff_cnt
UNION ALL
SELECT '|EXISTS|', (SELECT count(*) FROM via_exists), (SELECT count(*) FROM via_intersect),
       (SELECT count(*) FROM (SELECT product_id FROM via_exists EXCEPT SELECT product_id FROM via_intersect) AS y);

-- пункт 8: намеренно без DISTINCT — UNION ALL вместо UNION даёт дубликаты (одно и то же product_id встречается в каждой стороне)
WITH a AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'MA'
      AND o.order_status = 'delivered'
),
b AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'PI'
      AND o.order_status = 'delivered'
)
SELECT 'UNION, повторных вхождений один раз' AS variant,
       count(*) AS rows_cnt,
       count(DISTINCT product_id) AS distinct_cnt
FROM (SELECT product_id FROM a UNION SELECT product_id FROM b) AS u
UNION ALL
SELECT 'UNION ALL, повторные вхождения оставлены',
       count(*),
       count(DISTINCT product_id)
FROM (SELECT product_id FROM a UNION ALL SELECT product_id FROM b) AS ua
UNION ALL
SELECT 'UNION ALL: множество дублируемых product_id',
       count(DISTINCT product_id),
       sum(cnt) - count(*) AS duplicates_over_product
FROM (
    SELECT product_id, count(*) AS cnt
    FROM (SELECT product_id FROM a UNION ALL SELECT product_id FROM b) AS inner_ua
    GROUP BY product_id
) AS g;

-- пункт 9: установить, какие операции возвращают множество, а какие — мультимножество, и проверить это на данных
WITH a AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'MA'
      AND o.order_status = 'delivered'
),
b AS (
    SELECT DISTINCT oi.product_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE c.customer_state = 'PI'
      AND o.order_status = 'delivered'
)
SELECT
    'SELECT (проекция), в т.ч. без DISTINCT — мультимножество' AS operation,
    (SELECT count(*) FROM (SELECT oi.product_id FROM olist.order_items AS oi) AS raw) AS rows_cnt,
    (SELECT count(DISTINCT oi.product_id) FROM olist.order_items AS oi) AS distinct_cnt
UNION ALL
SELECT 'UNION — множество',
    (SELECT count(*) FROM (SELECT product_id FROM a UNION SELECT product_id FROM b) AS u),
    (SELECT count(*) FROM (SELECT product_id FROM a UNION SELECT product_id FROM b) AS u2)
UNION ALL
SELECT 'UNION ALL — мультимножество',
    (SELECT count(*) FROM (SELECT product_id FROM a UNION ALL SELECT product_id FROM b) AS x),
    (SELECT count(DISTINCT product_id) FROM (SELECT product_id FROM a UNION ALL SELECT product_id FROM b) AS x2)
UNION ALL
SELECT 'INTERSECT / EXCEPT — множество (дубликаты удаляются)',
    (SELECT count(*) FROM (SELECT product_id FROM a INTERSECT SELECT product_id FROM b) AS i),
    (SELECT count(DISTINCT product_id) FROM (SELECT product_id FROM a EXCEPT SELECT product_id FROM b) AS e);

-- контрольное обращение: комментарий об операциях, возвращающих множество и мультимножество
SELECT
    1 AS item,
    'UNION, INTERSECT, EXCEPT возвращают множество' AS returns_set,
    'UNION ALL, INTERSECT ALL, EXCEPT ALL, SELECT сохраняют кратность' AS returns_multiset;
