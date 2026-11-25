-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 3)
-- Выборка, проекция, переименование и реляционная алгебра

-- пункт 1: исходное отношение products и используемые атрибуты
SELECT
    'olist.products' AS relation_name,
    'product_id, product_category_name, product_length_cm, product_height_cm, product_width_cm' AS used_attributes,
    count(*) AS total_rows,
    count(*) FILTER (WHERE product_category_name IS NULL) AS null_category,
    count(*) FILTER (WHERE product_length_cm IS NULL OR product_height_cm IS NULL OR product_width_cm IS NULL) AS null_dimensions
FROM olist.products;

-- пункт 2–3: проекция π и выборка σ по составному предикату; показаны первые 10 строк результата
SELECT
    product_id,
    product_category_name,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM olist.products
WHERE product_category_name IS NOT NULL
  AND product_length_cm * product_height_cm * product_width_cm > 20000
ORDER BY product_id
LIMIT 10;

-- пункт 3: мощность результата исходного выражения и проверка числа строк через count(*)
SELECT
    'σ_(category <> NULL ∧ volume > 20000)(products)' AS expression,
    count(*) AS cnt_rows,
    count(DISTINCT product_id) AS cnt_distinct
FROM olist.products
WHERE product_category_name IS NOT NULL
  AND product_length_cm * product_height_cm * product_width_cm > 20000;

-- пункт 4: предикат разбит на два последовательных σ — сначала по категории, затем по объёму
SELECT
    product_id,
    product_category_name,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM (
    SELECT *
    FROM olist.products
    WHERE product_category_name IS NOT NULL
) AS s1
WHERE product_length_cm * product_height_cm * product_width_cm > 20000
ORDER BY product_id
LIMIT 10;

-- пункт 4: эквивалентность исходного и разбитого выражения — обе разности пусты
WITH orig AS (
    SELECT product_id, product_category_name, product_length_cm, product_height_cm, product_width_cm
    FROM olist.products
    WHERE product_category_name IS NOT NULL
      AND product_length_cm * product_height_cm * product_width_cm > 20000
),
split AS (
    SELECT p.product_id, p.product_category_name, p.product_length_cm, p.product_height_cm, p.product_width_cm
    FROM (
        SELECT *
        FROM olist.products
        WHERE product_category_name IS NOT NULL
    ) AS p
    WHERE p.product_length_cm * p.product_height_cm * p.product_width_cm > 20000
),
diff_1 AS (SELECT * FROM orig EXCEPT SELECT * FROM split),
diff_2 AS (SELECT * FROM split EXCEPT SELECT * FROM orig)
SELECT '|orig|' AS quantity, (SELECT count(*) FROM orig) AS rows_cnt, 0 AS rows_in_diff
UNION ALL
SELECT '|split|', (SELECT count(*) FROM split), 0
UNION ALL
SELECT '|orig − split|', (SELECT count(*) FROM orig), (SELECT count(*) FROM diff_1)
UNION ALL
SELECT '|split − orig|', (SELECT count(*) FROM split), (SELECT count(*) FROM diff_2);

-- пункт 5: второй вариант — сначала проекция до трёх нужных столбцов и отбрасывание NULL-категорий, затем выборка
SELECT
    p.product_id,
    p.product_category_name,
    p.volume_cm3
FROM (
    SELECT product_id, product_category_name, product_length_cm * product_height_cm * product_width_cm AS volume_cm3
    FROM olist.products
    WHERE product_category_name IS NOT NULL
) AS p
WHERE p.volume_cm3 > 20000
ORDER BY p.product_id
LIMIT 10;

-- пункт 5: вариант с ранним сокращением атрибутов через ρ (переименование атрибута объёма) даёт тот же результат
WITH renamed AS (
    SELECT
        product_id AS pid,
        product_category_name AS category,
        product_length_cm * product_height_cm * product_width_cm AS volume_cm3
    FROM olist.products
    WHERE product_category_name IS NOT NULL
)
SELECT pid AS product_id, category AS product_category_name, volume_cm3
FROM renamed
WHERE volume_cm3 > 20000
ORDER BY product_id
LIMIT 10;

-- пункт 5: эквивалентность исходного выражения и варианта с ранним сокращением атрибутов
WITH orig AS (
    SELECT product_id, product_category_name
    FROM olist.products
    WHERE product_category_name IS NOT NULL
      AND product_length_cm * product_height_cm * product_width_cm > 20000
),
early AS (
    SELECT pid AS product_id, category AS product_category_name
    FROM (
        SELECT
            product_id AS pid,
            product_category_name AS category,
            product_length_cm * product_height_cm * product_width_cm AS volume_cm3
        FROM olist.products
        WHERE product_category_name IS NOT NULL
    ) AS renamed
    WHERE volume_cm3 > 20000
)
SELECT '|orig|' AS quantity, (SELECT count(*) FROM orig) AS rows_cnt, 0 AS rows_in_diff
UNION ALL
SELECT '|early|', (SELECT count(*) FROM early), 0
UNION ALL
SELECT '|orig − early| (product_id, category)', (SELECT count(*) FROM orig), (SELECT count(*) FROM (SELECT * FROM orig EXCEPT SELECT * FROM early) AS d1)
UNION ALL
SELECT '|early − orig| (product_id, category)', (SELECT count(*) FROM early), (SELECT count(*) FROM (SELECT * FROM early EXCEPT SELECT * FROM orig) AS d2);

-- пункт 6: проверка появления дубликатов в проекции — SELECT без DISTINCT и с DISTINCT, а также проекция только category
SELECT
    'SELECT (5 атрибутов, по ключу)' AS variant,
    count(*) AS cnt_rows,
    count(DISTINCT product_id) AS cnt_distinct_key
FROM olist.products
WHERE product_category_name IS NOT NULL
  AND product_length_cm * product_height_cm * product_width_cm > 20000
UNION ALL
SELECT
    'SELECT DISTINCT (5 атрибутов, по ключу)',
    count(*),
    count(DISTINCT product_id)
FROM (
    SELECT DISTINCT product_id, product_category_name, product_length_cm, product_height_cm, product_width_cm
    FROM olist.products
    WHERE product_category_name IS NOT NULL
      AND product_length_cm * product_height_cm * product_width_cm > 20000
) AS d
UNION ALL
SELECT
    'SELECT (только category)',
    count(*),
    count(DISTINCT product_category_name)
FROM olist.products
WHERE product_category_name IS NOT NULL
  AND product_length_cm * product_height_cm * product_width_cm > 20000
UNION ALL
SELECT
    'SELECT DISTINCT (только category)',
    count(*),
    count(DISTINCT product_category_name)
FROM (
    SELECT DISTINCT product_category_name
    FROM olist.products
    WHERE product_category_name IS NOT NULL
      AND product_length_cm * product_height_cm * product_width_cm > 20000
) AS dc;

-- пункт 6: пример категорий, где в проекции π_category возникают дубликаты (топ-5 по числу товаров)
SELECT
    product_category_name,
    count(*) AS products_in_result,
    count(*) - 1 AS duplicate_rows
FROM olist.products
WHERE product_category_name IS NOT NULL
  AND product_length_cm * product_height_cm * product_width_cm > 20000
GROUP BY product_category_name
HAVING count(*) > 1
ORDER BY products_in_result DESC, product_category_name
LIMIT 5;

-- итог: сводная строка с итоговыми числами для README (входные строки, NULL, результат и дубликаты)
SELECT
    count(*) AS input_rows,
    count(*) FILTER (WHERE product_category_name IS NULL) AS null_category,
    count(*) FILTER (WHERE product_length_cm IS NULL OR product_height_cm IS NULL OR product_width_cm IS NULL) AS null_dimensions,
    count(*) FILTER (
        WHERE product_category_name IS NOT NULL
          AND product_length_cm * product_height_cm * product_width_cm > 20000
    ) AS result_rows
FROM olist.products;
