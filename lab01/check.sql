-- ФИО: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: Общий (Практика 1)


-- проверка количества строк
SELECT 'customers' AS table_name, count(*) AS row_count FROM olist.customers
UNION ALL SELECT 'geolocation', count(*) FROM olist.geolocation
UNION ALL SELECT 'orders', count(*) FROM olist.orders
UNION ALL SELECT 'order_items', count(*) FROM olist.order_items
UNION ALL SELECT 'order_payments', count(*) FROM olist.order_payments
UNION ALL SELECT 'order_reviews', count(*) FROM olist.order_reviews
UNION ALL SELECT 'products', count(*) FROM olist.products
UNION ALL SELECT 'sellers', count(*) FROM olist.sellers
UNION ALL SELECT 'product_category_name_translation', count(*) FROM olist.product_category_name_translation
ORDER BY table_name;

-- поиск орфанов (значений не пристроенных никуда)
SELECT count(*) AS orphan_items_without_order
FROM olist.order_items oi
LEFT JOIN olist.orders o ON o.order_id = oi.order_id
WHERE o.order_id IS NULL;

SELECT count(*) AS orphan_payments_without_order
FROM olist.order_payments op
LEFT JOIN olist.orders o ON o.order_id = op.order_id
WHERE o.order_id IS NULL;

SELECT count(*) AS orphan_reviews_without_order
FROM olist.order_reviews ord
LEFT JOIN olist.orders o ON o.order_id = ord.order_id
WHERE o.order_id IS NULL;

SELECT count(*) AS orphan_orders_without_customer
FROM olist.orders o
LEFT JOIN olist.customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;

-- проверка на нулл
SELECT 'customers' AS table_name, count(*) AS null_keys FROM olist.customers WHERE customer_id IS NULL
UNION ALL SELECT 'orders', count(*) FROM olist.orders WHERE order_id IS NULL OR customer_id IS NULL
UNION ALL SELECT 'order_items', count(*) FROM olist.order_items WHERE order_id IS NULL OR order_item_id IS NULL OR product_id IS NULL OR seller_id IS NULL
UNION ALL SELECT 'order_payments', count(*) FROM olist.order_payments WHERE order_id IS NULL OR payment_sequential IS NULL
UNION ALL SELECT 'order_reviews', count(*) FROM olist.order_reviews WHERE review_id IS NULL OR order_id IS NULL
UNION ALL SELECT 'products', count(*) FROM olist.products WHERE product_id IS NULL
UNION ALL SELECT 'sellers', count(*) FROM olist.sellers WHERE seller_id IS NULL;