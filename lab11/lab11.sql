-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 12)
-- Транзакции, конкурентный доступ и блокировки

-- создать схему lab, если её ещё нет
CREATE SCHEMA IF NOT EXISTS lab;

-- удалить таблицы экспериментов прошлого запуска в порядке, обратном зависимостям
DROP TABLE IF EXISTS lab.inventory_snapshot;
DROP TABLE IF EXISTS lab.inventory_movements;
DROP TABLE IF EXISTS lab.inventory;

-- удалить функции прошлого запуска, чтобы их сигнатуры не конфликтовали
DROP FUNCTION IF EXISTS lab.reserve(text, integer, text);
DROP FUNCTION IF EXISTS lab.release(text, integer, text);

-- остаток товара: PK product_id, неотрицательный qty и счётчик версий строки
CREATE TABLE lab.inventory (
    product_id text PRIMARY KEY REFERENCES olist.products (product_id),
    qty integer NOT NULL CHECK (qty >= 0),
    version integer NOT NULL DEFAULT 0,
    CONSTRAINT ck_inventory_qty CHECK (qty <= 1000)
);

-- заполнить остатки: по 10 единиц 100 самым продаваемым товарам Olist
INSERT INTO lab.inventory (product_id, qty)
SELECT top100.product_id, 10
FROM (
    SELECT product_id
    FROM olist.order_items
    GROUP BY product_id
    ORDER BY count(*) DESC, product_id
    LIMIT 100
) AS top100;

-- журнал движений склада: каждое резервирование оставляет строку
CREATE TABLE lab.inventory_movements (
    movement_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id text NOT NULL REFERENCES lab.inventory (product_id) ON DELETE CASCADE,
    delta integer NOT NULL CHECK (delta <> 0),
    kind text NOT NULL,
    qty_after integer NOT NULL CHECK (qty_after >= 0),
    note text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT ck_inventory_movements_kind CHECK (kind IN ('reserve', 'release', 'restock', 'seed'))
);

-- индекс для фантомного COUNT по условию kind = 'reserve'
CREATE INDEX ix_inventory_movements_kind ON lab.inventory_movements (kind, created_at);

-- зафиксировать исходное состояние: количество строк, суммарный qty, number of products
SELECT count(*) AS products, sum(qty) AS total_qty, min(qty) AS min_qty, max(qty) AS max_qty, sum(version) AS total_version
FROM lab.inventory;

-- сохранить снимок остатков для восстановления после экспериментов
CREATE TABLE lab.inventory_snapshot (
    product_id text PRIMARY KEY,
    qty integer NOT NULL,
    version integer NOT NULL,
    saved_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO lab.inventory_snapshot (product_id, qty, version)
SELECT product_id, qty, version
FROM lab.inventory;

-- атомарное резервирование одной единицы: UPDATE ... WHERE qty > 0 RETURNING
UPDATE lab.inventory
SET qty = qty - 1,
    version = version + 1
WHERE product_id = (
        SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1
    )
    AND qty > 0
RETURNING product_id, qty, version;

-- записать движение для только что выполненного резервирования
INSERT INTO lab.inventory_movements (product_id, delta, kind, qty_after, note)
SELECT product_id, -1, 'reserve', qty, 'atomic reservation demo'
FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1)
    AND version = 1;

-- проверка: остаток уменьшился ровно на 1, версия выросла ровно на 1
SELECT i.product_id, s.qty AS qty_before, i.qty AS qty_after, i.version - s.version AS version_delta
FROM lab.inventory AS i
JOIN lab.inventory_snapshot AS s USING (product_id)
WHERE i.product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- безопасное резервирование N единиц с проверкой остатка в одном операторе
UPDATE lab.inventory
SET qty = qty - 3,
    version = version + 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id OFFSET 1 LIMIT 1)
    AND qty >= 3
RETURNING product_id, qty, version;

-- журнал: движение на -3 для второго товара
INSERT INTO lab.inventory_movements (product_id, delta, kind, qty_after, note)
SELECT product_id, -3, 'reserve', qty, 'bulk reservation demo'
FROM lab.inventory
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id OFFSET 1 LIMIT 1);

-- попытка зарезервировать больше, чем есть: 0 строк, UPDATE не меняет данные
UPDATE lab.inventory
SET qty = qty - qty - 1,
    version = version + 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id OFFSET 2 LIMIT 1)
    AND qty > qty
RETURNING product_id, qty;

-- проверка ограничения qty >= 0: такой UPDATE должен завершиться ошибкой
SELECT count(*) AS rows_with_negative_attempt FROM lab.inventory WHERE qty < 0;

-- функция резервирования: тот же атомарный UPDATE, но с записью движения в одной транзакции
CREATE FUNCTION lab.reserve(p_product_id text, p_units integer DEFAULT 1, p_note text DEFAULT NULL)
RETURNS TABLE (product_id text, qty integer, version integer)
LANGUAGE plpgsql
AS $fn$
BEGIN
    UPDATE lab.inventory AS i
    SET qty = i.qty - p_units,
        version = i.version + 1
    WHERE i.product_id = p_product_id
        AND i.qty >= p_units
    RETURNING i.product_id, i.qty, i.version
    INTO product_id, qty, version;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    INSERT INTO lab.inventory_movements (product_id, delta, kind, qty_after, note)
    VALUES (p_product_id, -p_units, 'reserve', qty, p_note);

    RETURN NEXT;
END;
$fn$;

-- функция возврата единиц на склад
CREATE FUNCTION lab.release(p_product_id text, p_units integer DEFAULT 1, p_note text DEFAULT NULL)
RETURNS TABLE (product_id text, qty integer, version integer)
LANGUAGE plpgsql
AS $fn$
BEGIN
    UPDATE lab.inventory AS i
    SET qty = i.qty + p_units,
        version = i.version + 1
    WHERE i.product_id = p_product_id
    RETURNING i.product_id, i.qty, i.version
    INTO product_id, qty, version;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    INSERT INTO lab.inventory_movements (product_id, delta, kind, qty_after, note)
    VALUES (p_product_id, p_units, 'release', qty, p_note);

    RETURN NEXT;
END;
$fn$;

-- проверка функции резервирования: успех, отказ при нехватке и запись в журнал
SELECT * FROM lab.reserve((SELECT product_id FROM lab.inventory ORDER BY product_id OFFSET 3 LIMIT 1), 2, 'function reserve demo');
SELECT * FROM lab.reserve((SELECT product_id FROM lab.inventory ORDER BY product_id OFFSET 4 LIMIT 1), 100000, 'too many');
SELECT count(*) AS movements_for_offset3 FROM lab.inventory_movements
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id OFFSET 3 LIMIT 1);

-- согласованность журнала и остатков: сумма delta должна совпадать с qty - стартовым qty
SELECT count(*) AS inconsistent_products
FROM (
    SELECT i.product_id, i.qty - s.qty AS qty_delta, coalesce(sum(m.delta), 0) AS journal_delta
    FROM lab.inventory AS i
    JOIN lab.inventory_snapshot AS s USING (product_id)
    LEFT JOIN lab.inventory_movements AS m USING (product_id)
    GROUP BY i.product_id, i.qty, s.qty
) AS t
WHERE qty_delta <> journal_delta;

-- проверка, что остатки не ушли в минус
SELECT count(*) AS negative_rows FROM lab.inventory WHERE qty < 0;

-- восстановить исходные значения qty и version из снимка
UPDATE lab.inventory AS i
SET qty = s.qty,
    version = s.version
FROM lab.inventory_snapshot AS s
WHERE i.product_id = s.product_id;

-- очистить журнал движений после демонстрации
TRUNCATE TABLE lab.inventory_movements RESTART IDENTITY;

-- вернуть ровно 10 единиц на каждый товар для экспериментов с сеансами
UPDATE lab.inventory SET qty = 10, version = 0;

-- контроль: 100 товаров по 10 единиц, журнал пуст, функции на месте
SELECT count(*) AS products, min(qty) AS min_qty, max(qty) AS max_qty, sum(qty) AS total_qty
FROM lab.inventory;
SELECT count(*) AS movements FROM lab.inventory_movements;
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'lab'
ORDER BY p.proname;
