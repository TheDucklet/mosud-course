-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 5)
-- Кванторы, EXISTS и реляционное деление

-- Входные данные варианта: строки и категории по штатам AL, SE, BA в доставленных заказах
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
),
delivered_items AS (
    SELECT o.order_id,
           o.customer_id,
           c.customer_state,
           p.product_category_name AS category
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
      AND p.product_category_name IS NOT NULL
),
state_category AS (
    SELECT DISTINCT category, customer_state FROM delivered_items
),
divider AS (
    SELECT count(*) AS states_total FROM target_states
)
SELECT (SELECT states_total FROM divider) AS states_total,
       (SELECT count(*) FROM delivered_items) AS delivered_items,
       (SELECT count(DISTINCT order_id) FROM delivered_items) AS delivered_orders,
       (SELECT count(DISTINCT category) FROM delivered_items) AS categories_in_s,
       (SELECT count(*) FROM state_category) AS category_state_pairs,
       (SELECT count(*) FROM olist.products WHERE product_category_name IS NULL) AS products_without_category;

-- Пункт 2: категории, встречавшиеся в каждом штате из S, через двойной NOT EXISTS (реляционное деление)
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
),
delivered_items AS (
    SELECT o.order_id,
           o.customer_id,
           c.customer_state,
           p.product_category_name AS category
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
      AND p.product_category_name IS NOT NULL
),
categories_in_s AS (
    SELECT DISTINCT category FROM delivered_items
)
SELECT ci.category
FROM categories_in_s AS ci
WHERE NOT EXISTS (
    SELECT 1
    FROM target_states AS ts
    WHERE NOT EXISTS (
        SELECT 1
        FROM delivered_items AS di
        WHERE di.category = ci.category
          AND di.customer_state = ts.state
    )
)
ORDER BY ci.category;

-- Пункт 2 (продолжение): та же выборка с числом штатов и заказов у каждой категории
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
),
delivered_items AS (
    SELECT o.order_id,
           o.customer_id,
           c.customer_state,
           p.product_category_name AS category
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
      AND p.product_category_name IS NOT NULL
),
categories_in_s AS (
    SELECT DISTINCT category FROM delivered_items
)
SELECT ci.category,
       (SELECT count(DISTINCT di.customer_state) FROM delivered_items AS di WHERE di.category = ci.category) AS states_covered,
       (SELECT count(DISTINCT di.order_id) FROM delivered_items AS di WHERE di.category = ci.category) AS orders_in_s,
       coalesce((SELECT t.product_category_name_english
                 FROM olist.product_category_name_translation AS t
                 WHERE t.product_category_name = ci.category), ci.category) AS category_english
FROM categories_in_s AS ci
WHERE NOT EXISTS (
    SELECT 1
    FROM target_states AS ts
    WHERE NOT EXISTS (
        SELECT 1
        FROM delivered_items AS di
        WHERE di.category = ci.category
          AND di.customer_state = ts.state
    )
)
ORDER BY ci.category;

-- Пункт 3: то же условие через GROUP BY / HAVING count(DISTINCT customer_state) = мощности делителя
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
),
delivered_items AS (
    SELECT o.order_id,
           o.customer_id,
           c.customer_state,
           p.product_category_name AS category
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
      AND p.product_category_name IS NOT NULL
)
SELECT di.category
FROM delivered_items AS di
GROUP BY di.category
HAVING count(DISTINCT di.customer_state) = (SELECT count(*) FROM target_states)
ORDER BY di.category;

-- Пункт 4: то же условие через EXCEPT (категории из S минус категории, для которых нет штата) и NOT EXISTS
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
),
delivered_items AS (
    SELECT o.order_id,
           o.customer_id,
           c.customer_state,
           p.product_category_name AS category
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
      AND p.product_category_name IS NOT NULL
),
categories_in_s AS (
    SELECT DISTINCT category FROM delivered_items
),
states_of_category AS (
    SELECT DISTINCT category, customer_state FROM delivered_items
),
missing_pairs AS (
    SELECT ci.category, ts.state
    FROM categories_in_s AS ci
    CROSS JOIN target_states AS ts
    EXCEPT
    SELECT category, customer_state
    FROM states_of_category
),
gaps_with_not_exists AS (
    SELECT ci.category
    FROM categories_in_s AS ci
    WHERE NOT EXISTS (
        SELECT 1
        FROM missing_pairs AS mp
        WHERE mp.category = ci.category
    )
)
SELECT category
FROM categories_in_s
EXCEPT
SELECT category
FROM gaps_with_not_exists
ORDER BY category;

-- Пункт 5: доказательство эквивалентности трёх реализаций через EXCEPT в обе стороны
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
),
divider_size AS (
    SELECT count(*) AS states_total FROM target_states
),
delivered_items AS (
    SELECT o.order_id,
           o.customer_id,
           c.customer_state,
           p.product_category_name AS category
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
      AND p.product_category_name IS NOT NULL
),
categories_in_s AS (
    SELECT DISTINCT category FROM delivered_items
),
by_not_exists AS (
    SELECT ci.category
    FROM categories_in_s AS ci
    WHERE NOT EXISTS (
        SELECT 1
        FROM target_states AS ts
        WHERE NOT EXISTS (
            SELECT 1
            FROM delivered_items AS di
            WHERE di.category = ci.category
              AND di.customer_state = ts.state
        )
    )
),
by_having AS (
    SELECT di.category
    FROM delivered_items AS di
    GROUP BY di.category
    HAVING count(DISTINCT di.customer_state) = (SELECT states_total FROM divider_size)
),
states_of_category AS (
    SELECT DISTINCT category, customer_state FROM delivered_items
),
missing_pairs AS (
    SELECT ci.category, ts.state
    FROM categories_in_s AS ci
    CROSS JOIN target_states AS ts
    EXCEPT
    SELECT category, customer_state
    FROM states_of_category
),
by_except AS (
    SELECT category FROM categories_in_s
    EXCEPT
    SELECT category FROM missing_pairs
),
checks(label, failed_rows) AS (
    SELECT 'not_exists minus having', count(*) FROM (SELECT category FROM by_not_exists EXCEPT SELECT category FROM by_having) AS d
    UNION ALL
    SELECT 'having minus not_exists', count(*) FROM (SELECT category FROM by_having EXCEPT SELECT category FROM by_not_exists) AS d
    UNION ALL
    SELECT 'not_exists minus except', count(*) FROM (SELECT category FROM by_not_exists EXCEPT SELECT category FROM by_except) AS d
    UNION ALL
    SELECT 'except minus not_exists', count(*) FROM (SELECT category FROM by_except EXCEPT SELECT category FROM by_not_exists) AS d
    UNION ALL
    SELECT 'having minus except', count(*) FROM (SELECT category FROM by_having EXCEPT SELECT category FROM by_except) AS d
    UNION ALL
    SELECT 'except minus having', count(*) FROM (SELECT category FROM by_except EXCEPT SELECT category FROM by_having) AS d
),
sizes(label, result_rows) AS (
    SELECT 'not_exists', count(*) FROM by_not_exists
    UNION ALL
    SELECT 'having', count(*) FROM by_having
    UNION ALL
    SELECT 'except', count(*) FROM by_except
)
SELECT * FROM sizes
UNION ALL
SELECT * FROM checks;

-- Пункт 6: диагностика по категории with_most_orders_in_s (категория -> штат -> заказы, итог и доля)
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
),
delivered_items AS (
    SELECT o.order_id,
           o.customer_id,
           c.customer_state,
           p.product_category_name AS category
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
      AND p.product_category_name IS NOT NULL
),
category_totals AS (
    SELECT category, count(DISTINCT order_id) AS orders_total
    FROM delivered_items
    GROUP BY category
),
diagnostic_category AS (
    SELECT category, orders_total
    FROM category_totals
    ORDER BY orders_total DESC, category
    LIMIT 1
),
state_rows AS (
    SELECT ts.state,
           (SELECT count(DISTINCT di.order_id) FROM delivered_items AS di
             WHERE di.category = dc.category AND di.customer_state = ts.state) AS orders_cnt
    FROM diagnostic_category AS dc
    CROSS JOIN target_states AS ts
)
SELECT dc.category,
       dc.orders_total AS category_orders_total,
       sr.state,
       sr.orders_cnt,
       count(DISTINCT oi.seller_id) AS sellers_cnt,
       round(100.0 * sr.orders_cnt / dc.orders_total, 1) AS share_percent
FROM diagnostic_category AS dc
JOIN state_rows AS sr ON true
JOIN delivered_items AS di ON di.category = dc.category AND di.customer_state = sr.state
JOIN olist.order_items AS oi ON oi.order_id = di.order_id
JOIN olist.products AS p ON p.product_id = oi.product_id AND p.product_category_name = dc.category
GROUP BY dc.category, dc.orders_total, sr.state, sr.orders_cnt
ORDER BY sr.orders_cnt DESC, sr.state;

-- Пункт 6 (продолжение): та же таблица целиком одним запросом GROUPING SETS (наглядная форма пункт/итог)
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
),
delivered_items AS (
    SELECT o.order_id,
           c.customer_state,
           p.product_category_name AS category
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
      AND p.product_category_name IS NOT NULL
),
diagnostic_category AS (
    SELECT category, count(DISTINCT order_id) AS orders_total
    FROM delivered_items
    GROUP BY category
    ORDER BY orders_total DESC, category
    LIMIT 1
)
SELECT coalesce(di.customer_state, 'ИТОГО') AS state,
       count(DISTINCT di.order_id) AS orders_cnt,
       count(DISTINCT di.order_id) FILTER (WHERE di.customer_state = 'AL') AS al_cnt,
       count(DISTINCT di.order_id) FILTER (WHERE di.customer_state = 'SE') AS se_cnt,
       count(DISTINCT di.order_id) FILTER (WHERE di.customer_state = 'BA') AS ba_cnt
FROM delivered_items AS di
JOIN diagnostic_category AS dc ON dc.category = di.category
GROUP BY GROUPING SETS ((di.customer_state), ())
ORDER BY state;

-- Пункт 7: поведение при пустом target_states — все три реализации в одном результате
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
    WHERE false
),
divider_size AS (
    SELECT count(*) AS states_total FROM target_states
),
delivered_items AS (
    SELECT o.order_id,
           c.customer_state,
           p.product_category_name AS category
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    JOIN olist.products AS p ON p.product_id = oi.product_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
      AND p.product_category_name IS NOT NULL
),
catalogue AS (
    SELECT DISTINCT product_category_name AS category
    FROM olist.products
    WHERE product_category_name IS NOT NULL
),
by_not_exists AS (
    SELECT ci.category
    FROM catalogue AS ci
    WHERE NOT EXISTS (
        SELECT 1
        FROM target_states AS ts
        WHERE NOT EXISTS (
            SELECT 1
            FROM delivered_items AS di
            WHERE di.category = ci.category
              AND di.customer_state = ts.state
        )
    )
),
by_having AS (
    SELECT di.category
    FROM delivered_items AS di
    GROUP BY di.category
    HAVING count(DISTINCT di.customer_state) = (SELECT states_total FROM divider_size)
),
by_except AS (
    SELECT category FROM catalogue
    EXCEPT
    SELECT di.category
    FROM delivered_items AS di
    CROSS JOIN target_states AS ts
    WHERE NOT EXISTS (
        SELECT 1
        FROM delivered_items AS d2
        WHERE d2.category = di.category
          AND d2.customer_state = ts.state
    )
),
catalogue_translated AS (
    SELECT DISTINCT coalesce(t.product_category_name_english, p.product_category_name) AS category_english
    FROM olist.products AS p
    LEFT JOIN olist.product_category_name_translation AS t
           ON t.product_category_name = p.product_category_name
    WHERE p.product_category_name IS NOT NULL
)
SELECT 'divider_size' AS metric, (SELECT states_total FROM divider_size) AS value
UNION ALL SELECT 'rows_in_delivered_items', (SELECT count(*) FROM delivered_items)
UNION ALL SELECT 'result_not_exists', (SELECT count(*) FROM by_not_exists)
UNION ALL SELECT 'result_having', (SELECT count(*) FROM by_having)
UNION ALL SELECT 'result_except', (SELECT count(*) FROM by_except)
UNION ALL SELECT 'catalogue_categories', (SELECT count(*) FROM catalogue)
UNION ALL SELECT 'catalogue_categories_translated', (SELECT count(*) FROM catalogue_translated);

-- Пункт 8 (дополнительно): продавцы, которые продавали покупателям каждого из трёх штатов (три реализации)
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
),
sales AS (
    SELECT oi.seller_id,
           c.customer_state,
           o.order_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
),
candidates AS (
    SELECT DISTINCT seller_id FROM sales
),
by_not_exists AS (
    SELECT cand.seller_id
    FROM candidates AS cand
    WHERE NOT EXISTS (
        SELECT 1
        FROM target_states AS ts
        WHERE NOT EXISTS (
            SELECT 1
            FROM sales AS s
            WHERE s.seller_id = cand.seller_id
              AND s.customer_state = ts.state
        )
    )
),
by_having AS (
    SELECT s.seller_id
    FROM sales AS s
    GROUP BY s.seller_id
    HAVING count(DISTINCT s.customer_state) = (SELECT count(*) FROM target_states)
),
by_except AS (
    SELECT seller_id FROM candidates
    EXCEPT
    SELECT cand.seller_id
    FROM candidates AS cand
    CROSS JOIN target_states AS ts
    WHERE NOT EXISTS (
        SELECT 1
        FROM sales AS s
        WHERE s.seller_id = cand.seller_id
          AND s.customer_state = ts.state
    )
)
SELECT 'not_exists' AS implementation, count(*) AS sellers_cnt FROM by_not_exists
UNION ALL SELECT 'having', count(*) FROM by_having
UNION ALL SELECT 'except', count(*) FROM by_except
UNION ALL SELECT 'candidates', (SELECT count(*) FROM candidates)
UNION ALL SELECT 'not_exists minus having', (SELECT count(*) FROM (SELECT seller_id FROM by_not_exists EXCEPT SELECT seller_id FROM by_having) AS d)
UNION ALL SELECT 'having minus not_exists', (SELECT count(*) FROM (SELECT seller_id FROM by_having EXCEPT SELECT seller_id FROM by_not_exists) AS d);

-- Пункт 8 (продолжение): те же продавцы с разбивкой проданных заказов по штатам S
WITH target_states AS (
    SELECT state
    FROM (VALUES ('AL'), ('SE'), ('BA')) AS s(state)
),
sales AS (
    SELECT oi.seller_id,
           c.customer_state,
           o.order_id
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN olist.order_items AS oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND c.customer_state IN (SELECT state FROM target_states)
),
qualified AS (
    SELECT s.seller_id
    FROM sales AS s
    GROUP BY s.seller_id
    HAVING count(DISTINCT s.customer_state) = (SELECT count(*) FROM target_states)
)
SELECT q.seller_id,
       sl.seller_city,
       count(DISTINCT s.order_id) FILTER (WHERE s.customer_state = 'AL') AS al_orders,
       count(DISTINCT s.order_id) FILTER (WHERE s.customer_state = 'SE') AS se_orders,
       count(DISTINCT s.order_id) FILTER (WHERE s.customer_state = 'BA') AS ba_orders,
       count(DISTINCT s.order_id) AS orders_in_s
FROM qualified AS q
JOIN olist.sellers AS sl ON sl.seller_id = q.seller_id
JOIN sales AS s ON s.seller_id = q.seller_id
GROUP BY q.seller_id, sl.seller_city
ORDER BY orders_in_s DESC, q.seller_id;
