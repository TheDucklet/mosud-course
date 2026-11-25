-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 7)
-- NULL, трёхзначная логика и качество данных

-- Сколько NULL-значений в каждом столбце orders, products, order_reviews
SELECT z.table_name,
       z.column_name,
       z.nulls,
       z.rows_total,
       round(100.0 * z.nulls / z.rows_total, 2) AS null_share_pct
FROM (
    SELECT 'orders' AS table_name, ord_col, col AS column_name, n AS nulls, t AS rows_total
    FROM (
        SELECT 1 AS ord_col, 'order_approved_at' AS col, count(*) FILTER (WHERE order_approved_at IS NULL) AS n, count(*) AS t FROM olist.orders
        UNION ALL SELECT 2, 'order_delivered_carrier_date', count(*) FILTER (WHERE order_delivered_carrier_date IS NULL), count(*) FROM olist.orders
        UNION ALL SELECT 3, 'order_delivered_customer_date', count(*) FILTER (WHERE order_delivered_customer_date IS NULL), count(*) FROM olist.orders
        UNION ALL SELECT 4, 'order_estimated_delivery_date', count(*) FILTER (WHERE order_estimated_delivery_date IS NULL), count(*) FROM olist.orders
    ) v
    UNION ALL
    SELECT 'products', ord_col, col, n, t
    FROM (
        SELECT 1 AS ord_col, 'product_category_name' AS col, count(*) FILTER (WHERE product_category_name IS NULL) AS n, count(*) AS t FROM olist.products
        UNION ALL SELECT 2, 'product_name_lenght', count(*) FILTER (WHERE product_name_lenght IS NULL), count(*) FROM olist.products
        UNION ALL SELECT 3, 'product_description_lenght', count(*) FILTER (WHERE product_description_lenght IS NULL), count(*) FROM olist.products
        UNION ALL SELECT 4, 'product_photos_qty', count(*) FILTER (WHERE product_photos_qty IS NULL), count(*) FROM olist.products
        UNION ALL SELECT 5, 'product_weight_g', count(*) FILTER (WHERE product_weight_g IS NULL), count(*) FROM olist.products
        UNION ALL SELECT 6, 'product_length_cm', count(*) FILTER (WHERE product_length_cm IS NULL), count(*) FROM olist.products
        UNION ALL SELECT 7, 'product_height_cm', count(*) FILTER (WHERE product_height_cm IS NULL), count(*) FROM olist.products
        UNION ALL SELECT 8, 'product_width_cm', count(*) FILTER (WHERE product_width_cm IS NULL), count(*) FROM olist.products
    ) v
    UNION ALL
    SELECT 'order_reviews', ord_col, col, n, t
    FROM (
        SELECT 1 AS ord_col, 'review_score' AS col, count(*) FILTER (WHERE review_score IS NULL) AS n, count(*) AS t FROM olist.order_reviews
        UNION ALL SELECT 2, 'review_comment_title', count(*) FILTER (WHERE review_comment_title IS NULL), count(*) FROM olist.order_reviews
        UNION ALL SELECT 3, 'review_comment_message', count(*) FILTER (WHERE review_comment_message IS NULL), count(*) FROM olist.order_reviews
    ) v
) z
ORDER BY CASE z.table_name WHEN 'orders' THEN 1 WHEN 'products' THEN 2 ELSE 3 END, z.ord_col;

-- COUNT(*) против COUNT(столбец) по датам заказа: что именно не посчитано
SELECT count(*) AS count_star,
       count(order_delivered_customer_date) AS count_delivered_date,
       count(*) - count(order_delivered_customer_date) AS diff_rows,
       count(order_delivered_carrier_date) AS count_carrier_date,
       count(order_approved_at) AS count_approved_at,
       count(order_estimated_delivery_date) AS count_estimated_date,
       round(100.0 * (count(*) - count(order_delivered_customer_date)) / count(*), 2) AS no_delivered_date_pct
FROM olist.orders;

-- Трёхзначная логика на значениях: = NULL, <> NULL, IS NULL, IS NOT NULL
SELECT v.val,
       (v.val = 5) AS eq_5,
       (v.val <> 5) AS ne_5,
       (v.val = NULL) AS eq_null,
       (v.val <> NULL) AS ne_null,
       (v.val IS NULL) AS is_null_flag,
       (v.val IS NOT NULL) AS is_not_null_flag,
       coalesce((v.val = 5)::text, 'UNKNOWN') AS eq_5_3vl
FROM (VALUES (5), (3), (NULL)) AS v(val)
ORDER BY v.val NULLS LAST;

-- То же самое на живых данных заказов: сколько строк видят = NULL и <> NULL и сколько видит IS NULL
SELECT 'order_delivered_customer_date' AS column_name,
       count(*) FILTER (WHERE order_delivered_customer_date = NULL) AS eq_null_rows,
       count(*) FILTER (WHERE order_delivered_customer_date <> NULL) AS ne_null_rows,
       count(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS is_null_rows,
       count(*) FILTER (WHERE order_delivered_customer_date IS NOT NULL) AS is_not_null_rows,
       count(*) AS total_rows
FROM olist.orders
UNION ALL
SELECT 'order_approved_at',
       count(*) FILTER (WHERE order_approved_at = NULL),
       count(*) FILTER (WHERE order_approved_at <> NULL),
       count(*) FILTER (WHERE order_approved_at IS NULL),
       count(*) FILTER (WHERE order_approved_at IS NOT NULL),
       count(*)
FROM olist.orders;

-- IS DISTINCT FROM против IS NOT DISTINCT FROM: пары дат доставки, включая пары с NULL
SELECT p.pair_name,
       p.date_1,
       p.date_2,
       (p.date_1 = p.date_2) AS eq_classic,
       (p.date_1 <> p.date_2) AS ne_classic,
       (p.date_1 IS DISTINCT FROM p.date_2) AS is_distinct,
       (p.date_1 IS NOT DISTINCT FROM p.date_2) AS is_not_distinct
FROM (
    VALUES
        ('both_null', NULL::timestamp, NULL::timestamp),
        ('one_null', (SELECT min(order_delivered_customer_date) FROM olist.orders), NULL::timestamp),
        ('equal', (SELECT min(order_delivered_customer_date) FROM olist.orders), (SELECT min(order_delivered_customer_date) FROM olist.orders)),
        ('different', (SELECT min(order_delivered_customer_date) FROM olist.orders), (SELECT max(order_delivered_customer_date) FROM olist.orders))
) AS p(pair_name, date_1, date_2);

-- Сколько заказов пришлось бы потерять, если сравнивать даты доставки через = и <>: счёт пар NULL
SELECT count(*) AS orders_total,
       count(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS orders_with_null_date,
       count(*) FILTER (WHERE order_delivered_customer_date IS NOT NULL) AS orders_with_date,
       count(*) FILTER (WHERE (order_delivered_customer_date <> NULL)) AS rows_passing_ne_null,
       round(100.0 * count(*) FILTER (WHERE order_delivered_customer_date IS NULL) / count(*), 2) AS null_share_pct,
       count(*) FILTER (WHERE order_delivered_customer_date IS NOT DISTINCT FROM NULL) AS is_not_distinct_null_rows
FROM olist.orders;

-- Создаём таблицу lab.temp_ids: два реальных order_id и строка NULL
DROP TABLE IF EXISTS lab.temp_ids;
CREATE TABLE lab.temp_ids (id text);
INSERT INTO lab.temp_ids (id)
VALUES ('00010242fe8c5a6d1ba2dd792cb16214'),
       ('00018f77f2f0320c557190d7a144bdd3'),
       (NULL);
SELECT count(*) AS temp_ids_rows,
       count(*) FILTER (WHERE id IS NULL) AS temp_ids_nulls,
       count(*) FILTER (WHERE id IS NOT NULL) AS temp_ids_values
FROM lab.temp_ids;

-- Поиск заказов через NOT IN: NULL в правом наборе делает результат пустым
SELECT count(*) AS orders_found_not_in
FROM olist.orders o
WHERE o.order_id NOT IN (SELECT t.id FROM lab.temp_ids t);

-- Тот же поиск через NOT EXISTS: NULL не мешает, находятся все заказы, кроме одного
SELECT count(*) AS orders_found_not_exists
FROM olist.orders o
WHERE NOT EXISTS (SELECT 1 FROM lab.temp_ids t WHERE t.id = o.order_id);

-- Сводка по пункту 5: NOT IN без NULL, NOT IN с NULL, NOT EXISTS и разница между ними
SELECT (SELECT count(*) FROM olist.orders) AS orders_total,
       (SELECT count(*) FROM lab.temp_ids WHERE id IS NOT NULL) AS real_ids_in_temp,
       (SELECT count(*) FROM olist.orders o WHERE o.order_id NOT IN (SELECT t.id FROM lab.temp_ids t WHERE t.id IS NOT NULL)) AS not_in_without_null,
       (SELECT count(*) FROM olist.orders o WHERE o.order_id NOT IN (SELECT t.id FROM lab.temp_ids t)) AS not_in_with_null,
       (SELECT count(*) FROM olist.orders o WHERE NOT EXISTS (SELECT 1 FROM lab.temp_ids t WHERE t.id = o.order_id)) AS not_exists,
       (SELECT count(*) FROM lab.temp_ids) AS temp_rows;

-- Удаляем таблицу lab.temp_ids, чтобы повторный запуск начинался с чистого листа
DROP TABLE IF EXISTS lab.temp_ids;

-- LEFT JOIN отзывов с условием review_score >= 4 в ON: сохраняются все заказы, без хорошего отзыва — NULL-строка
SELECT count(*) AS rows_cnt,
       count(r.order_id) AS matched_rows,
       count(*) - count(r.order_id) AS left_only_rows,
       round(100.0 * count(r.order_id) / count(*), 2) AS matched_share_pct
FROM olist.orders o
LEFT JOIN olist.order_reviews r
       ON r.order_id = o.order_id
      AND r.review_score >= 4;

-- Тот же LEFT JOIN, но условие review_score >= 4 в WHERE: NULL-строки отбрасываются, JOIN превращается в INNER
SELECT count(*) AS rows_cnt,
       count(r.order_id) AS matched_rows,
       count(*) - count(r.order_id) AS left_only_rows,
       round(100.0 * count(r.order_id) / count(*), 2) AS matched_share_pct
FROM olist.orders o
LEFT JOIN olist.order_reviews r
       ON r.order_id = o.order_id
WHERE r.review_score >= 4;

-- COALESCE для текста отзыва: подставляем текст заглушку и считаем, сколько отзывов было NULL
SELECT coalesce(r.review_comment_message, '(без текста)') AS comment_text,
       r.review_score,
       count(*) AS reviews_cnt,
       count(*) FILTER (WHERE r.review_comment_message IS NULL) AS was_null,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS share_of_all_pct
FROM olist.order_reviews r
GROUP BY coalesce(r.review_comment_message, '(без текста)'), r.review_score
ORDER BY reviews_cnt DESC
LIMIT 5;

-- NULLIF для безопасного деления: все отзывов и мусорные рейтинги, которые валят деление
SELECT (SELECT count(*) FROM olist.order_reviews) AS reviews_total,
       (SELECT count(*) FROM olist.order_reviews WHERE review_score = 0) AS zero_scores,
       round((SELECT count(*) FROM olist.order_reviews)::numeric / NULLIF((SELECT count(*) FROM olist.order_reviews WHERE review_score = 0), 0), 2) AS division_with_nullif,
       round((SELECT count(*) FROM olist.order_reviews)::numeric / NULLIF((SELECT count(*) FROM olist.order_reviews WHERE review_score < 0), 0), 2) AS division_by_zero_rows,
       round((SELECT count(*) FROM olist.order_reviews WHERE review_comment_message IS NOT NULL)::numeric / NULLIF((SELECT count(*) FROM olist.order_reviews WHERE review_comment_message IS NULL), 0), 2) AS with_text_per_without_text,
       round(100.0 * (SELECT count(*) FROM olist.order_reviews WHERE review_comment_message IS NOT NULL) / (SELECT count(*) FROM olist.order_reviews), 2) AS with_text_share_pct;

-- Мини-профиль качества данных: доля заказов без даты доставки, товаров без категории, отзывов без текста
SELECT 'orders_without_delivered_date' AS metric,
       (SELECT count(*) FROM olist.orders WHERE order_delivered_customer_date IS NULL) AS bad_rows,
       (SELECT count(*) FROM olist.orders) AS total_rows,
       round(100.0 * (SELECT count(*) FROM olist.orders WHERE order_delivered_customer_date IS NULL) / (SELECT count(*) FROM olist.orders), 2) AS bad_share_pct
UNION ALL
SELECT 'products_without_category',
       (SELECT count(*) FROM olist.products WHERE product_category_name IS NULL),
       (SELECT count(*) FROM olist.products),
       round(100.0 * (SELECT count(*) FROM olist.products WHERE product_category_name IS NULL) / (SELECT count(*) FROM olist.products), 2)
UNION ALL
SELECT 'reviews_without_text',
       (SELECT count(*) FROM olist.order_reviews WHERE review_comment_message IS NULL OR btrim(review_comment_message) = ''),
       (SELECT count(*) FROM olist.order_reviews),
       round(100.0 * (SELECT count(*) FROM olist.order_reviews WHERE review_comment_message IS NULL OR btrim(review_comment_message) = '') / (SELECT count(*) FROM olist.order_reviews), 2)
UNION ALL
SELECT 'orders_without_approval',
       (SELECT count(*) FROM olist.orders WHERE order_approved_at IS NULL),
       (SELECT count(*) FROM olist.orders),
       round(100.0 * (SELECT count(*) FROM olist.orders WHERE order_approved_at IS NULL) / (SELECT count(*) FROM olist.orders), 2);

-- Отзывы без текста по статусу заказа: NULLы отдельно, пустые строки отдельно
SELECT o.order_status,
       count(*) AS reviews_cnt,
       count(*) FILTER (WHERE r.review_comment_message IS NULL) AS null_text,
       count(*) FILTER (WHERE r.review_comment_message IS NOT NULL AND btrim(r.review_comment_message) = '') AS blank_text,
       round(100.0 * count(*) FILTER (WHERE r.review_comment_message IS NULL) / count(*), 2) AS null_share_pct
FROM olist.order_reviews r
JOIN olist.orders o ON o.order_id = r.order_id
GROUP BY o.order_status
ORDER BY reviews_cnt DESC;

-- Естественный NULL против NULL-дефекта: дата доставки по статусу заказа и NULL-ширина товара
SELECT 'orders_by_status' AS block,
       o.order_status AS value_group,
       count(*) AS rows_cnt,
       count(*) FILTER (WHERE o.order_delivered_customer_date IS NULL) AS nulls_cnt,
       round(100.0 * count(*) FILTER (WHERE o.order_delivered_customer_date IS NULL) / count(*), 2) AS nulls_share_pct
FROM olist.orders o
GROUP BY o.order_status
UNION ALL
SELECT 'products_by_category',
       CASE WHEN p.product_category_name IS NULL THEN 'category_is_null' ELSE 'category_is_known' END,
       count(*),
       count(*) FILTER (WHERE p.product_width_cm IS NULL),
       round(100.0 * count(*) FILTER (WHERE p.product_width_cm IS NULL) / count(*), 2)
FROM olist.products p
GROUP BY CASE WHEN p.product_category_name IS NULL THEN 'category_is_null' ELSE 'category_is_known' END;
