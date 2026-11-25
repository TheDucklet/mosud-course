-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 9)
-- Функциональные зависимости и нормализация: перемещения между складами

-- создать схему lab, если её ещё нет
CREATE SCHEMA IF NOT EXISTS lab;

-- удалить исходное плоское отношение прошлого запуска
DROP TABLE IF EXISTS lab.nf_transfer_flat CASCADE;

-- удалить нормализованные отношения в порядке, обратном зависимостям
DROP TABLE IF EXISTS lab.nf_transfer_item CASCADE;

-- удалить шапки перемещений прошлого запуска
DROP TABLE IF EXISTS lab.nf_transfer CASCADE;

-- удалить справочник товаров прошлого запуска
DROP TABLE IF EXISTS lab.nf_transfer_product CASCADE;

-- удалить справочник складов прошлого запуска
DROP TABLE IF EXISTS lab.nf_transfer_warehouse CASCADE;

-- исходное ненормализованное отношение: все справочные значения продублированы в строках
CREATE TABLE lab.nf_transfer_flat (
    transfer_id integer NOT NULL,
    source_wh varchar(12) NOT NULL,
    source_city varchar(80) NOT NULL,
    dest_wh varchar(12) NOT NULL,
    dest_city varchar(80) NOT NULL,
    product_id text NOT NULL,
    category_name varchar(80) NOT NULL,
    qty integer NOT NULL,
    created_at timestamp NOT NULL,
    CONSTRAINT pk_nf_transfer_flat PRIMARY KEY (transfer_id, product_id),
    CONSTRAINT ck_nf_transfer_flat_qty CHECK (qty > 0),
    CONSTRAINT ck_nf_transfer_flat_warehouses CHECK (source_wh <> dest_wh)
);

-- строки плоского отношения: 4 перемещения, у одного из них две позиции
INSERT INTO lab.nf_transfer_flat (transfer_id, source_wh, source_city, dest_wh, dest_city, product_id, category_name, qty, created_at)
SELECT v.transfer_id, v.src, wsrc.city, v.dst, wdst.city, p.product_id, p.category_name, v.qty, v.created_at::timestamp
FROM (VALUES
        (1, 'WH-SP01', 'WH-RJ01', 1, 3, '2018-01-10 09:00'),
        (2, 'WH-RJ01', 'WH-POA1', 1, 2, '2018-01-12 14:30'),
        (2, 'WH-RJ01', 'WH-POA1', 2, 1, '2018-01-12 14:30'),
        (3, 'WH-SP01', 'WH-CWB1', 1, 5, '2018-02-01 11:15'),
        (4, 'WH-POA1', 'WH-SP01', 3, 4, '2018-02-20 08:45')
     ) AS v (transfer_id, src, dst, product_slot, qty, created_at)
JOIN (VALUES ('WH-SP01', 'sao paulo'), ('WH-SP02', 'sao paulo'),
             ('WH-RJ01', 'rio de janeiro'), ('WH-CWB1', 'curitiba'),
             ('WH-POA1', 'porto alegre')) AS wsrc (wh, city) ON wsrc.wh = v.src
JOIN (VALUES ('WH-SP01', 'sao paulo'), ('WH-SP02', 'sao paulo'),
             ('WH-RJ01', 'rio de janeiro'), ('WH-CWB1', 'curitiba'),
             ('WH-POA1', 'porto alegre')) AS wdst (wh, city) ON wdst.wh = v.dst
CROSS JOIN LATERAL (
    SELECT oi.product_id, coalesce(pr.product_category_name, 'sem_categoria') AS category_name
    FROM olist.order_items AS oi
    JOIN olist.products AS pr ON pr.product_id = oi.product_id
    WHERE pr.product_category_name = 'beleza_saude'
    GROUP BY oi.product_id, pr.product_category_name
    ORDER BY count(*) DESC, oi.product_id
    OFFSET v.product_slot - 1
    LIMIT 1
) AS p;

-- избыточность плоского отношения: сколько раз город склада повторён в строках
SELECT wh AS warehouse, city, count(*) AS city_copies_in_flat
FROM (
    SELECT source_wh AS wh, source_city AS city FROM lab.nf_transfer_flat
    UNION ALL
    SELECT dest_wh, dest_city FROM lab.nf_transfer_flat
) AS f
GROUP BY wh, city
ORDER BY wh;

-- избыточность плоского отношения: сколько раз продублирована категория товара
SELECT product_id, category_name, count(*) AS rows_in_flat
FROM lab.nf_transfer_flat
GROUP BY product_id, category_name
ORDER BY product_id;

-- 1НФ: справочник складов — город хранится один раз на склад
CREATE TABLE lab.nf_transfer_warehouse (
    wh_code varchar(12) NOT NULL,
    city varchar(80) NOT NULL,
    CONSTRAINT pk_nf_transfer_warehouse PRIMARY KEY (wh_code),
    CONSTRAINT ck_nf_transfer_warehouse_code CHECK (wh_code ~ '^WH-[A-Z0-9]+$')
);

-- 1НФ: справочник товаров — категория хранится один раз на товар, FK на olist.products
CREATE TABLE lab.nf_transfer_product (
    product_id text NOT NULL,
    category_name varchar(80) NOT NULL,
    CONSTRAINT pk_nf_transfer_product PRIMARY KEY (product_id),
    CONSTRAINT fk_nf_transfer_product_olist FOREIGN KEY (product_id) REFERENCES olist.products (product_id) ON DELETE RESTRICT
);

-- 2НФ: шапка перемещения — источник, назначение и дата зависят только от transfer_id
CREATE TABLE lab.nf_transfer (
    transfer_id integer NOT NULL,
    source_wh varchar(12) NOT NULL,
    dest_wh varchar(12) NOT NULL,
    created_at timestamp NOT NULL,
    CONSTRAINT pk_nf_transfer PRIMARY KEY (transfer_id),
    CONSTRAINT uq_nf_transfer_route UNIQUE (source_wh, dest_wh, created_at),
    CONSTRAINT fk_nf_transfer_source FOREIGN KEY (source_wh) REFERENCES lab.nf_transfer_warehouse (wh_code) ON DELETE RESTRICT,
    CONSTRAINT fk_nf_transfer_dest FOREIGN KEY (dest_wh) REFERENCES lab.nf_transfer_warehouse (wh_code) ON DELETE RESTRICT,
    CONSTRAINT ck_nf_transfer_warehouses CHECK (source_wh <> dest_wh)
);

-- 3НФ: позиции перемещения — количество зависит от пары (перемещение, товар)
CREATE TABLE lab.nf_transfer_item (
    transfer_id integer NOT NULL,
    product_id text NOT NULL,
    qty integer NOT NULL,
    CONSTRAINT pk_nf_transfer_item PRIMARY KEY (transfer_id, product_id),
    CONSTRAINT fk_nf_transfer_item_transfer FOREIGN KEY (transfer_id) REFERENCES lab.nf_transfer (transfer_id) ON DELETE CASCADE,
    CONSTRAINT fk_nf_transfer_item_product FOREIGN KEY (product_id) REFERENCES lab.nf_transfer_product (product_id) ON DELETE RESTRICT,
    CONSTRAINT ck_nf_transfer_item_qty CHECK (qty > 0)
);

-- наполнить справочник складов уникальными складами из плоского отношения
INSERT INTO lab.nf_transfer_warehouse (wh_code, city)
SELECT DISTINCT w.wh, w.city
FROM (
    SELECT source_wh AS wh, source_city AS city FROM lab.nf_transfer_flat
    UNION
    SELECT dest_wh, dest_city FROM lab.nf_transfer_flat
) AS w
ORDER BY w.wh;

-- наполнить справочник товаров уникальными товарами из плоского отношения
INSERT INTO lab.nf_transfer_product (product_id, category_name)
SELECT DISTINCT product_id, category_name
FROM lab.nf_transfer_flat
ORDER BY product_id;

-- наполнить шапки перемещений уникальными перемещениями из плоского отношения
INSERT INTO lab.nf_transfer (transfer_id, source_wh, dest_wh, created_at)
SELECT DISTINCT transfer_id, source_wh, dest_wh, created_at
FROM lab.nf_transfer_flat
ORDER BY transfer_id;

-- наполнить позиции перемещений парами перемещение-товар с количеством
INSERT INTO lab.nf_transfer_item (transfer_id, product_id, qty)
SELECT transfer_id, product_id, qty
FROM lab.nf_transfer_flat
ORDER BY transfer_id, product_id;

-- сверка: количество строк в плоском и нормализованном отношении
SELECT 'lab.nf_transfer_flat' AS relation, count(*) AS rows FROM lab.nf_transfer_flat
UNION ALL SELECT 'lab.nf_transfer_warehouse', count(*) FROM lab.nf_transfer_warehouse
UNION ALL SELECT 'lab.nf_transfer_product', count(*) FROM lab.nf_transfer_product
UNION ALL SELECT 'lab.nf_transfer', count(*) FROM lab.nf_transfer
UNION ALL SELECT 'lab.nf_transfer_item', count(*) FROM lab.nf_transfer_item;

-- сводка: сколько места занимает город склада и категория товара в двух схемах
SELECT 'город склада' AS reference_value,
       (SELECT count(*) FROM (
            SELECT source_wh, source_city FROM lab.nf_transfer_flat
            UNION ALL SELECT dest_wh, dest_city FROM lab.nf_transfer_flat) AS a) AS copies_in_flat,
       (SELECT count(*) FROM lab.nf_transfer_warehouse) AS copies_normalized
UNION ALL
SELECT 'категория товара',
       (SELECT count(*) FROM lab.nf_transfer_flat),
       (SELECT count(*) FROM lab.nf_transfer_product)
UNION ALL
SELECT 'шапка перемещения (маршрут + дата)',
       (SELECT count(*) FROM lab.nf_transfer_flat),
       (SELECT count(*) FROM lab.nf_transfer);

-- сравнение дублирования: плоское отношение против нормализованного, город на склад
SELECT f.wh AS warehouse,
       f.city,
       count(*) AS city_copies_in_flat,
       count(DISTINCT n.wh_code) AS city_copies_normalized
FROM (
    SELECT source_wh AS wh, source_city AS city FROM lab.nf_transfer_flat
    UNION ALL
    SELECT dest_wh, dest_city FROM lab.nf_transfer_flat
) AS f
LEFT JOIN lab.nf_transfer_warehouse AS n ON n.wh_code = f.wh
GROUP BY f.wh, f.city
ORDER BY f.wh;

-- сравнение дублирования: плоское отношение против нормализованного, категория на товар
SELECT f.product_id,
       f.category_name,
       count(*) AS category_copies_in_flat,
       count(DISTINCT p.product_id) AS category_copies_normalized
FROM lab.nf_transfer_flat AS f
LEFT JOIN lab.nf_transfer_product AS p ON p.product_id = f.product_id
GROUP BY f.product_id, f.category_name
ORDER BY f.product_id;

-- проверка равенства: обратное соединение нормализованных отношений восстанавливает плоское
SELECT
    (SELECT count(*) FROM lab.nf_transfer_flat) AS rows_in_flat,
    (SELECT count(*)
     FROM lab.nf_transfer AS t
     JOIN lab.nf_transfer_item AS ti ON ti.transfer_id = t.transfer_id
     JOIN lab.nf_transfer_warehouse AS ws ON ws.wh_code = t.source_wh
     JOIN lab.nf_transfer_warehouse AS wd ON wd.wh_code = t.dest_wh
     JOIN lab.nf_transfer_product AS p ON p.product_id = ti.product_id) AS rows_after_join,
    (SELECT count(*)
     FROM (
         SELECT t.transfer_id, t.source_wh, ws.city AS source_city, t.dest_wh, wd.city AS dest_city,
                ti.product_id, p.category_name, ti.qty, t.created_at
         FROM lab.nf_transfer AS t
         JOIN lab.nf_transfer_item AS ti ON ti.transfer_id = t.transfer_id
         JOIN lab.nf_transfer_warehouse AS ws ON ws.wh_code = t.source_wh
         JOIN lab.nf_transfer_warehouse AS wd ON wd.wh_code = t.dest_wh
         JOIN lab.nf_transfer_product AS p ON p.product_id = ti.product_id
         EXCEPT
         SELECT transfer_id, source_wh, source_city, dest_wh, dest_city, product_id, category_name, qty, created_at
         FROM lab.nf_transfer_flat
     ) AS diff) AS rows_lost_by_lossless_join;

-- проверка всех товаров позиций на существование в olist.products
SELECT count(*) AS items, count(op.product_id) AS matched_in_olist
FROM lab.nf_transfer_item AS ti
LEFT JOIN olist.products AS op ON op.product_id = ti.product_id;

-- ошибочное утверждение 1: повторный город для того же склада
-- INSERT INTO lab.nf_transfer_warehouse (wh_code, city) VALUES ('WH-SP01', 'santos');

-- ошибочное утверждение 2: перемещение со складом, которого нет в справочнике
-- INSERT INTO lab.nf_transfer (transfer_id, source_wh, dest_wh, created_at)
-- VALUES (99, 'WH-XXX9', 'WH-SP01', '2018-03-01 10:00');

-- ошибочное утверждение 3: нулевое количество в позиции
-- UPDATE lab.nf_transfer_item SET qty = 0 WHERE transfer_id = 1 AND product_id = (SELECT min(product_id) FROM lab.nf_transfer_item WHERE transfer_id = 1)
