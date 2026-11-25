-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 11)
-- Представления, CTE и рекурсивные запросы

-- подготовка: рабочая схема lab
CREATE SCHEMA IF NOT EXISTS lab;

-- пункт 4: таблица-иерархия BR -> штат -> город (пересоздаётся целиком, чтобы скрипт был повторяемым)
DROP TABLE IF EXISTS lab.geo_tree_cyclic CASCADE;
DROP TABLE IF EXISTS lab.geo_tree CASCADE;
CREATE TABLE lab.geo_tree (
    node_id text PRIMARY KEY,
    parent_id text REFERENCES lab.geo_tree(node_id),
    node_type text NOT NULL CHECK (node_type IN ('country', 'state', 'city')),
    node_name text NOT NULL
);

-- пункт 4: корень иерархии — страна BR
INSERT INTO lab.geo_tree (node_id, parent_id, node_type, node_name)
VALUES ('BR', NULL, 'country', 'Brazil');

-- пункт 4: уровень 2 — 27 штатов из olist.customers, код штата вида ST:SP
INSERT INTO lab.geo_tree (node_id, parent_id, node_type, node_name)
SELECT
    'ST:' || c.customer_state,
    'BR',
    'state',
    c.customer_state
FROM olist.customers AS c
WHERE c.customer_state IS NOT NULL
GROUP BY c.customer_state;

-- пункт 4: уровень 3 — до 20 городов на штат по числу клиентов, код города вида CTY:<штат>:<город>
INSERT INTO lab.geo_tree (node_id, parent_id, node_type, node_name)
SELECT
    'CTY:' || t.customer_state || ':' || t.customer_city,
    'ST:' || t.customer_state,
    'city',
    t.customer_city
FROM (
    SELECT
        c.customer_state,
        c.customer_city,
        row_number() OVER (PARTITION BY c.customer_state ORDER BY count(*) DESC, c.customer_city) AS city_rank
    FROM olist.customers AS c
    WHERE c.customer_state IS NOT NULL
      AND c.customer_city IS NOT NULL
    GROUP BY c.customer_state, c.customer_city
) AS t
WHERE t.city_rank <= 20;

-- пункт 4: контроль иерархии — число узлов по уровням и проверка, что у каждого города родитель-штат
SELECT
    g.node_type,
    count(*) AS nodes,
    count(*) FILTER (WHERE g.parent_id IS NULL) AS roots,
    count(*) FILTER (WHERE p.node_type = 'state') AS children_of_state
FROM lab.geo_tree AS g
LEFT JOIN lab.geo_tree AS p ON p.node_id = g.parent_id
GROUP BY g.node_type
ORDER BY g.node_type;

-- пункт 1: обычное представление v_order_summary — одна строка на заказ: штат клиента, число позиций, сумма price + freight
DROP VIEW IF EXISTS lab.v_order_summary CASCADE;
CREATE VIEW lab.v_order_summary AS
SELECT
    o.order_id,
    c.customer_state,
    count(oi.order_item_id) AS items_count,
    coalesce(sum(oi.price + oi.freight_value), 0) AS total_value
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
LEFT JOIN olist.order_items AS oi ON oi.order_id = o.order_id
GROUP BY o.order_id, c.customer_state;

-- пункт 1: контроль представления — строк ровно столько же, сколько заказов
SELECT
    (SELECT count(*) FROM lab.v_order_summary) AS view_rows,
    (SELECT count(*) FROM olist.orders) AS order_rows,
    (SELECT round(avg(items_count), 2) FROM lab.v_order_summary) AS avg_items;

-- пункт 2: материализованное представление mv_monthly_state_sales — месяц заказа, штат, число заказов, сумма; хранится физически
DROP MATERIALIZED VIEW IF EXISTS lab.mv_monthly_state_sales CASCADE;
CREATE MATERIALIZED VIEW lab.mv_monthly_state_sales AS
SELECT
    date_trunc('month', o.order_purchase_timestamp)::date AS month,
    c.customer_state,
    count(*) AS orders_count,
    sum(s.total_value) AS sales_value
FROM olist.orders AS o
JOIN olist.customers AS c ON c.customer_id = o.customer_id
JOIN (
    SELECT
        oi.order_id,
        sum(oi.price + oi.freight_value) AS total_value
    FROM olist.order_items AS oi
    GROUP BY oi.order_id
) AS s ON s.order_id = o.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY date_trunc('month', o.order_purchase_timestamp)::date, c.customer_state
WITH DATA;

-- пункт 2: индексы материализованного представления (имени нет во view — заводим разово)
CREATE INDEX IF NOT EXISTS mv_monthly_state_sales_state_idx ON lab.mv_monthly_state_sales (customer_state);
CREATE UNIQUE INDEX IF NOT EXISTS mv_monthly_state_sales_key_idx ON lab.mv_monthly_state_sales (month, customer_state);

-- пункт 2: REFRESH материализованного представления — единственный способ обновить его данные
REFRESH MATERIALIZED VIEW lab.mv_monthly_state_sales;

-- пункт 2: контроль материализованного представления — число месяцев, штатов и общая сумма
SELECT
    count(*) AS rows_total,
    count(DISTINCT month) AS months,
    count(DISTINCT customer_state) AS states,
    round(sum(sales_value), 2) AS sales_total
FROM lab.mv_monthly_state_sales;

-- пункт 3: сложный аналитический запрос «топ городов с отставанием от лидера штата» декомпозирован на 4 именованных CTE
WITH order_totals AS (
    SELECT
        oi.order_id,
        sum(oi.price + oi.freight_value) AS order_value,
        count(*) AS items_count
    FROM olist.order_items AS oi
    GROUP BY oi.order_id
),
city_metrics AS (
    SELECT
        c.customer_state,
        c.customer_city,
        count(DISTINCT o.order_id) AS orders_count,
        sum(t.order_value) AS revenue,
        sum(t.items_count) AS items_count,
        avg(t.order_value) AS avg_order_value
    FROM olist.orders AS o
    JOIN olist.customers AS c ON c.customer_id = o.customer_id
    JOIN order_totals AS t ON t.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state, c.customer_city
),
city_ranked AS (
    SELECT
        m.*,
        row_number() OVER (
            PARTITION BY m.customer_state
            ORDER BY m.revenue DESC, m.customer_city
        ) AS revenue_rank,
        sum(m.revenue) OVER (PARTITION BY m.customer_state) AS state_revenue,
        first_value(m.revenue) OVER (
            PARTITION BY m.customer_state
            ORDER BY m.revenue DESC, m.customer_city
        ) AS leader_revenue
    FROM city_metrics AS m
),
state_summary AS (
    SELECT
        r.customer_state,
        count(*) AS cities_in_state,
        max(r.state_revenue) AS state_revenue,
        max(r.leader_revenue) AS leader_revenue,
        max(r.revenue) FILTER (WHERE r.revenue_rank = 1) AS leader_revenue_check
    FROM city_ranked AS r
    GROUP BY r.customer_state
)
SELECT
    r.customer_state,
    r.revenue_rank,
    r.customer_city,
    r.orders_count,
    round(r.revenue, 2) AS revenue,
    round(100 * r.revenue / NULLIF(r.state_revenue, 0), 1) AS share_of_state_pct,
    round(100 * (s.leader_revenue - r.revenue) / NULLIF(s.leader_revenue, 0), 1) AS gap_to_leader_pct,
    s.cities_in_state
FROM city_ranked AS r
JOIN state_summary AS s ON s.customer_state = r.customer_state
WHERE r.revenue_rank <= 3
  AND r.customer_state IN ('GO', 'SP', 'RJ')
ORDER BY s.state_revenue DESC, r.customer_state, r.revenue_rank;

-- пункт 5 (вариант 10, корень ST:GO): всё поддерево штата GO — глубина, узел, путь, имя
WITH RECURSIVE geo_subtree AS (
    SELECT
        g.node_id,
        g.parent_id,
        g.node_name,
        g.node_type,
        0 AS depth,
        g.node_name::text AS path
    FROM lab.geo_tree AS g
    WHERE g.node_id = 'ST:GO'
    UNION ALL
    SELECT
        c.node_id,
        c.parent_id,
        c.node_name,
        c.node_type,
        p.depth + 1,
        p.path || ' > ' || c.node_name
    FROM lab.geo_tree AS c
    JOIN geo_subtree AS p ON c.parent_id = p.node_id
)
SELECT depth, node_id, path, node_name
FROM geo_subtree
ORDER BY path;

-- пункт 5: размеры поддеревьев всех 27 штатов — контроль для варианта GO
SELECT
    'ST:' || s.customer_state AS state_node,
    (
        WITH RECURSIVE d AS (
            SELECT g.node_id
            FROM lab.geo_tree AS g
            WHERE g.node_id = 'ST:' || s.customer_state
            UNION ALL
            SELECT c.node_id
            FROM lab.geo_tree AS c
            JOIN d ON c.parent_id = d.node_id
        )
        SELECT count(*) - 1
        FROM d
    ) AS descendants
FROM (SELECT DISTINCT customer_state FROM olist.customers) AS s
ORDER BY descendants DESC, state_node;

-- пункт 6: обратная рекурсия от города CTY:GO:goiania вверх по предкам до корня Brazil
WITH RECURSIVE geo_ancestors AS (
    SELECT
        g.node_id,
        g.parent_id,
        g.node_name,
        g.node_type,
        0 AS depth
    FROM lab.geo_tree AS g
    WHERE g.node_id = 'CTY:GO:goiania'
    UNION ALL
    SELECT
        p.node_id,
        p.parent_id,
        p.node_name,
        p.node_type,
        c.depth + 1
    FROM lab.geo_tree AS p
    JOIN geo_ancestors AS c ON c.parent_id = p.node_id
)
SELECT depth, node_id, node_name, node_type
FROM geo_ancestors
ORDER BY depth;

-- пункт 7: число потомков каждого штата — отдельно городов и всех потомков через рекурсивный обход от каждого штата
WITH RECURSIVE state_nodes AS (
    SELECT g.node_id, g.node_name
    FROM lab.geo_tree AS g
    WHERE g.node_type = 'state'
),
geo_reach AS (
    SELECT s.node_id AS ancestor_id, s.node_id AS descendant_id, 0 AS hops
    FROM state_nodes AS s
    UNION ALL
    SELECT r.ancestor_id, c.node_id, r.hops + 1
    FROM geo_reach AS r
    JOIN lab.geo_tree AS c ON c.parent_id = r.descendant_id
)
SELECT
    r.ancestor_id AS state_node,
    count(*) AS descendants_total,
    count(*) FILTER (WHERE g.node_type = 'city') AS cities_in_subtree,
    count(*) FILTER (WHERE g.node_type = 'state') AS subtree_nodes_of_type_state,
    max(r.hops) AS max_depth
FROM geo_reach AS r
JOIN lab.geo_tree AS g ON g.node_id = r.descendant_id
WHERE r.hops > 0
GROUP BY r.ancestor_id
ORDER BY descendants_total DESC, state_node
LIMIT 10;

-- пункт 8 (*): копия дерева с искусственным циклом — корень иерархии BR получил родителя CTY:GO:goiania, то есть город снова ведёт к корню
DROP TABLE IF EXISTS lab.geo_tree_cyclic CASCADE;
CREATE TABLE lab.geo_tree_cyclic (
    node_id text PRIMARY KEY,
    parent_id text REFERENCES lab.geo_tree_cyclic(node_id),
    node_type text NOT NULL CHECK (node_type IN ('country', 'state', 'city')),
    node_name text NOT NULL
);
INSERT INTO lab.geo_tree_cyclic (node_id, parent_id, node_type, node_name)
SELECT g.node_id, g.parent_id, g.node_type, g.node_name
FROM lab.geo_tree AS g;
UPDATE lab.geo_tree_cyclic
SET parent_id = 'CTY:GO:goiania'
WHERE node_id = 'BR';

-- пункт 8 (*): защита клаузой CYCLE ... SET is_cycle USING path — обход от BR останавливается, когда узел в пути повторяется
WITH RECURSIVE cyclic_subtree AS (
    SELECT
        g.node_id,
        g.parent_id,
        g.node_name,
        g.node_type,
        0 AS depth
    FROM lab.geo_tree_cyclic AS g
    WHERE g.node_id = 'BR'
    UNION ALL
    SELECT
        c.node_id,
        c.parent_id,
        c.node_name,
        c.node_type,
        p.depth + 1
    FROM lab.geo_tree_cyclic AS c
    JOIN cyclic_subtree AS p ON c.parent_id = p.node_id
)
CYCLE node_id SET is_cycle USING path
SELECT depth, node_id, node_name, is_cycle
FROM cyclic_subtree
ORDER BY depth, node_id;

-- пункт 8 (*): защита глубинным предохранителем — обход того же цикла без CYCLE, но с условием depth < 100 против зависания
WITH RECURSIVE guarded_subtree AS (
    SELECT
        g.node_id,
        g.parent_id,
        g.node_name,
        0 AS depth
    FROM lab.geo_tree_cyclic AS g
    WHERE g.node_id = 'BR'
    UNION ALL
    SELECT
        c.node_id,
        c.parent_id,
        c.node_name,
        p.depth + 1
    FROM lab.geo_tree_cyclic AS c
    JOIN guarded_subtree AS p ON c.parent_id = p.node_id
    WHERE p.depth < 100
)
SELECT
    count(*) AS rows_until_guard,
    count(DISTINCT node_id) AS distinct_nodes,
    max(depth) AS max_depth,
    count(*) FILTER (WHERE node_id = 'BR') AS br_visits
FROM guarded_subtree;
