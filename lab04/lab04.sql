-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 4)
-- Соединения отношений и сложные JOIN

-- пункт 1–2: исходные отношения «паспорта заказа» и их размеры (мощность и число ключей)
SELECT 'olist.orders' AS relation_name, count(*) AS rows_cnt, count(DISTINCT order_id) AS key_cnt, 'order_id (PK)' AS relation_key FROM olist.orders
UNION ALL
SELECT 'olist.customers', count(*), count(DISTINCT customer_id), 'customer_id (PK)' FROM olist.customers
UNION ALL
SELECT 'olist.order_items', count(*), count(DISTINCT order_id), 'order_id + order_item_id (PK)' FROM olist.order_items
UNION ALL
SELECT 'olist.order_payments', count(*), count(DISTINCT order_id), 'order_id + payment_sequential (PK)' FROM olist.order_payments
UNION ALL
SELECT 'olist.order_reviews', count(*), count(DISTINCT order_id), 'review_id (PK), order_id не уникален' FROM olist.order_reviews
UNION ALL
SELECT 'olist.sellers', count(*), count(DISTINCT seller_id), 'seller_id (PK)' FROM olist.sellers;

-- пункт 2: фактическая кратность всех пар, участвующих в «паспорте заказа» (1:1, 1:N, M:N)
WITH per_order AS (
    SELECT
        order_id,
        count(*) AS item_rows,
        count(DISTINCT seller_id) AS sellers_cnt
    FROM olist.order_items
    GROUP BY order_id
)
SELECT
    'orders -> customers' AS join_pair,
    'N:1' AS expected_kind,
    (SELECT count(*) FROM olist.orders) AS left_rows,
    (SELECT count(*) FROM olist.orders o JOIN olist.customers c ON c.customer_id = o.customer_id) AS joined_rows
UNION ALL
SELECT 'orders -> order_items', '1:N', (SELECT count(*) FROM olist.orders), (SELECT count(*) FROM olist.order_items)
UNION ALL
SELECT 'orders -> order_payments', '1:N', (SELECT count(*) FROM olist.orders), (SELECT count(*) FROM olist.order_payments)
UNION ALL
SELECT 'orders -> order_reviews', '1:N', (SELECT count(*) FROM olist.orders), (SELECT count(*) FROM olist.order_reviews)
UNION ALL
SELECT 'orders -> sellers (через order_items)', 'M:N (развязка order_items)', (SELECT count(*) FROM olist.orders), (SELECT count(*) FROM per_order WHERE sellers_cnt > 1)
UNION ALL
SELECT 'sellers -> orders (через order_items)', 'M:N (развязка order_items)', (SELECT count(*) FROM olist.sellers), (SELECT count(*) FROM per_order);

-- пункт 2: заказы, у которых по несколько продавцов и по несколько оплат (источник размножения строк)
SELECT
    'заказов с >1 продавцом' AS quantity,
    (SELECT count(*) FROM (SELECT order_id FROM olist.order_items GROUP BY order_id HAVING count(DISTINCT seller_id) > 1) AS s) AS cnt
UNION ALL
SELECT 'заказов с >1 позицией', (SELECT count(*) FROM (SELECT order_id FROM olist.order_items GROUP BY order_id HAVING count(*) > 1) AS s)
UNION ALL
SELECT 'заказов с >1 оплатой', (SELECT count(*) FROM (SELECT order_id FROM olist.order_payments GROUP BY order_id HAVING count(*) > 1) AS s)
UNION ALL
SELECT 'заказов с >1 отзывом', (SELECT count(*) FROM (SELECT order_id FROM olist.order_reviews GROUP BY order_id HAVING count(*) > 1) AS s);

-- пункт 1: главный запрос — «паспорт заказа» с заранее агрегированными позициями, оплатами и отзывом
WITH items AS (
    SELECT
        order_id,
        count(*) AS items_cnt,
        count(DISTINCT seller_id) AS sellers_cnt,
        sum(price) AS items_sum,
        sum(freight_value) AS freight_sum
    FROM olist.order_items
    GROUP BY order_id
),
payments AS (
    SELECT
        order_id,
        count(*) AS payments_cnt,
        sum(payment_value) AS payments_sum
    FROM olist.order_payments
    GROUP BY order_id
),
reviews AS (
    SELECT
        order_id,
        min(review_score) AS review_score,
        max(review_creation_date) AS review_date
    FROM olist.order_reviews
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp::date AS purchase_date,
    c.customer_state,
    c.customer_city,
    i.items_cnt,
    i.sellers_cnt,
    round(i.items_sum, 2) AS items_sum,
    round(p.payments_sum, 2) AS payments_sum,
    r.review_score
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
JOIN items AS i ON i.order_id = o.order_id
LEFT JOIN payments AS p ON p.order_id = o.order_id
LEFT JOIN reviews AS r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
ORDER BY o.order_purchase_timestamp DESC
LIMIT 20;

-- пункт 2: контроль — в паспорте суммы позиций и оплат совпадают с агрегатами по тем же заказам
WITH items AS (
    SELECT order_id, sum(price) AS items_sum
    FROM olist.order_items
    GROUP BY order_id
),
payments AS (
    SELECT order_id, sum(payment_value) AS payments_sum
    FROM olist.order_payments
    GROUP BY order_id
)
SELECT
    'заказов в паспорте' AS quantity,
    count(*) AS cnt
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
JOIN items AS i ON i.order_id = o.order_id
LEFT JOIN payments AS p ON p.order_id = o.order_id
WHERE o.order_status = 'delivered'
UNION ALL
SELECT 'строк на один заказ (max)', max(rows_per_order)::bigint
FROM (
    SELECT count(*) AS rows_per_order
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN items AS i ON i.order_id = o.order_id
    LEFT JOIN payments AS p ON p.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
) AS per_order
UNION ALL
SELECT 'сумма позиций в паспорте, руб.', round(sum(i.items_sum), 2)::bigint
FROM olist.orders AS o
JOIN items AS i ON i.order_id = o.order_id
WHERE o.order_status = 'delivered'
UNION ALL
SELECT 'сумма позиций по items (те же заказы), руб.', round(sum(i.items_sum), 2)::bigint
FROM olist.orders AS o
JOIN items AS i ON i.order_id = o.order_id
WHERE o.order_status = 'delivered'
UNION ALL
SELECT 'сумма оплат в паспорте, руб.', round(sum(p.payments_sum), 2)::bigint
FROM olist.orders AS o
JOIN items AS i ON i.order_id = o.order_id
LEFT JOIN payments AS p ON p.order_id = o.order_id
WHERE o.order_status = 'delivered'
UNION ALL
SELECT 'сумма оплат по payments (те же заказы), руб.', round(sum(p.payments_sum), 2)::bigint
FROM olist.orders AS o
JOIN items AS i ON i.order_id = o.order_id
LEFT JOIN payments AS p ON p.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- пункт 3: LEFT JOIN сохраняет заказы без позиций — строк больше, чем во внутреннем соединении
SELECT
    'orders JOIN order_items (inner)' AS join_kind,
    count(*) AS rows_cnt,
    count(DISTINCT o.order_id) AS orders_cnt
FROM olist.orders AS o
JOIN olist.order_items AS i ON i.order_id = o.order_id
UNION ALL
SELECT 'orders LEFT JOIN order_items', count(*), count(DISTINCT o.order_id)
FROM olist.orders AS o
LEFT JOIN olist.order_items AS i ON i.order_id = o.order_id
UNION ALL
SELECT 'заказы, у которых позиций нет', count(*), count(*)
FROM olist.orders AS o
LEFT JOIN olist.order_items AS i ON i.order_id = o.order_id
WHERE i.order_id IS NULL;

-- пункт 4: анти-соединение — заказы без оплат, без отзывов и без позиций через NOT EXISTS
SELECT
    'заказов без оплаты' AS missing_kind,
    count(*) AS orders_cnt
FROM olist.orders AS o
WHERE NOT EXISTS (SELECT 1 FROM olist.order_payments AS p WHERE p.order_id = o.order_id)
UNION ALL
SELECT 'заказов без отзыва', count(*)
FROM olist.orders AS o
WHERE NOT EXISTS (SELECT 1 FROM olist.order_reviews AS r WHERE r.order_id = o.order_id)
UNION ALL
SELECT 'заказов без позиций', count(*)
FROM olist.orders AS o
WHERE NOT EXISTS (SELECT 1 FROM olist.order_items AS i WHERE i.order_id = o.order_id);

-- пункт 4: пример заказа без отзыва — «паспорт» заполнен его внешней частью через LEFT JOIN
SELECT
    o.order_id,
    o.order_status,
    c.customer_state,
    count(i.order_item_id) AS items_cnt,
    count(p.order_id) AS payments_cnt,
    r.review_score
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
LEFT JOIN olist.order_items AS i ON i.order_id = o.order_id
LEFT JOIN olist.order_payments AS p ON p.order_id = o.order_id
LEFT JOIN olist.order_reviews AS r ON r.order_id = o.order_id
WHERE NOT EXISTS (SELECT 1 FROM olist.order_reviews AS rr WHERE rr.order_id = o.order_id)
  AND o.order_status = 'delivered'
GROUP BY o.order_id, o.order_status, c.customer_state, r.review_score
ORDER BY o.order_id
LIMIT 5;

-- пункт 5 (неверный запрос): наивное соединение позиций, оплат и отзывов размножает строки и раздувает суммы
SELECT
    'три таблицы напрямую' AS query_variant,
    'items_price' AS measure,
    round(sum(i.price), 2) AS value
FROM olist.order_items AS i
JOIN olist.order_payments AS p ON p.order_id = i.order_id
JOIN olist.order_reviews AS r ON r.order_id = i.order_id
UNION ALL
SELECT 'три таблицы напрямую', 'факт items_price', round((SELECT sum(price) FROM olist.order_items), 2)
UNION ALL
SELECT 'три таблицы напрямую', 'payment_value', round(sum(p.payment_value), 2)
FROM olist.order_items AS i
JOIN olist.order_payments AS p ON p.order_id = i.order_id
JOIN olist.order_reviews AS r ON r.order_id = i.order_id
UNION ALL
SELECT 'три таблицы напрямую', 'факт payment_value', round((SELECT sum(payment_value) FROM olist.order_payments), 2)
UNION ALL
SELECT 'три таблицы напрямую', 'строк результата', count(*)::numeric(18, 2)
FROM olist.order_items AS i
JOIN olist.order_payments AS p ON p.order_id = i.order_id
JOIN olist.order_reviews AS r ON r.order_id = i.order_id
UNION ALL
SELECT 'три таблицы напрямую', 'факт строк (items)', (SELECT count(*) FROM olist.order_items)::numeric(18, 2);

-- пункт 5: во сколько раз раздуваются строки и суммы на одном конкретном заказе (позиции × оплаты × отзывы)
WITH plan AS (
    SELECT
        i.order_id,
        count(*) AS items_cnt,
        sum(i.price) AS real_price,
        count(DISTINCT p.payment_sequential) AS payments_cnt,
        count(DISTINCT r.review_id) AS reviews_cnt
    FROM olist.order_items AS i
    JOIN olist.order_payments AS p ON p.order_id = i.order_id
    JOIN olist.order_reviews AS r ON r.order_id = i.order_id
    GROUP BY i.order_id
)
SELECT
    order_id,
    items_cnt,
    payments_cnt,
    reviews_cnt,
    items_cnt * payments_cnt * reviews_cnt AS naive_rows,
    round(real_price, 2) AS real_price,
    round(real_price * payments_cnt * reviews_cnt, 2) AS naive_price
FROM plan
ORDER BY naive_rows DESC, order_id
LIMIT 5;

-- пункт 6 (исправление): правильная сумма плюс контроль — предварительная агрегация даёт ровно факт
WITH items AS (
    SELECT order_id, sum(price) AS items_sum FROM olist.order_items GROUP BY order_id
),
payments AS (
    SELECT order_id, sum(payment_value) AS payments_sum FROM olist.order_payments GROUP BY order_id
),
reviews AS (
    SELECT order_id, count(*) AS reviews_cnt FROM olist.order_reviews GROUP BY order_id
)
SELECT
    'сумма позиций' AS measure,
    round(sum(i.items_sum), 2) AS preaggregated,
    round((SELECT sum(price) FROM olist.order_items), 2) AS fact
FROM items AS i
UNION ALL
SELECT 'сумма оплат', round(sum(p.payments_sum), 2), round((SELECT sum(payment_value) FROM olist.order_payments), 2)
FROM payments AS p
UNION ALL
SELECT 'строк после соединения агрегатов (ровно по одной на заказ)', count(*)::numeric(18, 2), (SELECT count(DISTINCT order_id) FROM olist.order_items)::numeric(18, 2)
FROM items AS i
LEFT JOIN payments AS p ON p.order_id = i.order_id
LEFT JOIN reviews AS r ON r.order_id = i.order_id;

-- пункт 6 (исправление): второй способ — соединение с агрегатом по каждой таблице в подзапросе и проверка остатка
SELECT
    'заказов' AS quantity,
    count(*) AS cnt
FROM olist.orders AS o
LEFT JOIN (SELECT order_id, sum(price) AS items_sum FROM olist.order_items GROUP BY order_id) AS i ON i.order_id = o.order_id
LEFT JOIN (SELECT order_id, sum(payment_value) AS pay_sum FROM olist.order_payments GROUP BY order_id) AS p ON p.order_id = o.order_id
UNION ALL
SELECT 'строк в результате (ровно по одной на заказ)', count(*)
FROM olist.orders AS o
LEFT JOIN (SELECT order_id, sum(price) AS items_sum FROM olist.order_items GROUP BY order_id) AS i ON i.order_id = o.order_id
LEFT JOIN (SELECT order_id, sum(payment_value) AS pay_sum FROM olist.order_payments GROUP BY order_id) AS p ON p.order_id = o.order_id
UNION ALL
SELECT 'заказов с расхождением items_sum vs pay_sum > 1', count(*)
FROM olist.orders AS o
LEFT JOIN (SELECT order_id, sum(price) AS items_sum FROM olist.order_items GROUP BY order_id) AS i ON i.order_id = o.order_id
LEFT JOIN (SELECT order_id, sum(payment_value) AS pay_sum FROM olist.order_payments GROUP BY order_id) AS p ON p.order_id = o.order_id
WHERE abs(coalesce(i.items_sum, 0) - coalesce(p.pay_sum, 0)) > 1;

-- пункт 7: состав всех соединений главного запроса — развенчанное M:N через order_items и 1:N по оплатам и отзывам
SELECT
    'orders ⋈ customers' AS join_step,
    'N:1' AS ratio,
    count(*) AS rows_after_step
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
UNION ALL
SELECT 'после ⋈ order_items (не агрегированного)', 'M:N', count(*)
FROM olist.orders AS o
JOIN olist.order_items AS i ON i.order_id = o.order_id
UNION ALL
SELECT 'после ⋈ payments (не агрегированного)', 'M:N', count(*)
FROM olist.order_items AS i
JOIN olist.order_payments AS p ON p.order_id = i.order_id
UNION ALL
SELECT 'после ⋈ reviews (не агрегированного)', 'M:N', count(*)
FROM olist.order_items AS i
JOIN olist.order_payments AS p ON p.order_id = i.order_id
JOIN olist.order_reviews AS r ON r.order_id = i.order_id
UNION ALL
SELECT 'главный запрос (агрегаты заранее)', '1:1 по заказу', count(*)
FROM olist.orders AS o
JOIN (SELECT order_id FROM olist.order_items GROUP BY order_id) AS i ON i.order_id = o.order_id;
