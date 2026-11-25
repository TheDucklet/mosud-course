-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 13)
-- Индексы и физический доступ к данным

-- Пункт 1: убрать тестовые индексы, если они остались от прошлого запуска (повторный запуск воспроизводим, PK не затрагиваются)
DROP INDEX IF EXISTS olist.i_geo_city_state_zip;

-- Пункт 1: второй тестовый индекс
DROP INDEX IF EXISTS olist.i_geo_zip_prefix_include;

-- Пункт 1: третий тестовый индекс
DROP INDEX IF EXISTS olist.i_geo_zip_am_partial;

-- Пункт 2: какие префиксы и города реально есть в данных (запросы опытов должны быть непустыми)
SELECT geolocation_zip_code_prefix AS zip_prefix,
       geolocation_state AS st,
       geolocation_city AS city,
       count(*) AS rows_in_table
FROM olist.geolocation
WHERE geolocation_zip_code_prefix IN (13214, 68900)
GROUP BY 1, 2, 3
ORDER BY 1, 3;

-- Пункт 2 Опыт 1 (ДО): точный поиск по zip_prefix = 13214 (город Жундиаи, 325 строк), индексного пути нет
EXPLAIN (ANALYZE, BUFFERS)
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state
FROM olist.geolocation
WHERE geolocation_zip_code_prefix = 13214;

-- Пункт 3 Опыт 2 (ДО): равенство по паре (город, штат) — Макапа, Амапа; это ключ варианта целиком
EXPLAIN (ANALYZE, BUFFERS)
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng
FROM olist.geolocation
WHERE geolocation_state = 'AP'
  AND geolocation_city = 'macapa';

-- Пункт 3 Опыт 3 (ДО): тот же город и диапазон префиксов 68900-69350 (Амапа и Рорайма) — предикат, в котором ключ варианта дополнен zip_prefix
EXPLAIN (ANALYZE, BUFFERS)
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng
FROM olist.geolocation
WHERE geolocation_zip_code_prefix BETWEEN 68900 AND 69350
  AND geolocation_state = 'AP'
  AND geolocation_city = 'macapa';

-- Пункт 4/9: индекс по ключу варианта — (city, state, zip_prefix); city первым (8463 значения против 27 у штата), zip_prefix третьим, координаты в INCLUDE
CREATE INDEX i_geo_city_state_zip ON olist.geolocation (geolocation_city, geolocation_state, geolocation_zip_code_prefix) INCLUDE (geolocation_lat, geolocation_lng);

-- Пункт 5: обновление статистики после создания индекса
ANALYZE olist.geolocation;

-- Пункт 6 Опыт 2 (ПОСЛЕ): Index Scan по всем трём колонкам ключа вместо полного сканирования
EXPLAIN (ANALYZE, BUFFERS)
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng
FROM olist.geolocation
WHERE geolocation_state = 'AP'
  AND geolocation_city = 'macapa';

-- Пункт 6 Опыт 3 (ПОСЛЕ): диапазон zip_prefix стал частью условия входа в индекс, план перешёл в Index Only Scan
EXPLAIN (ANALYZE, BUFFERS)
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng
FROM olist.geolocation
WHERE geolocation_zip_code_prefix BETWEEN 68900 AND 69350
  AND geolocation_state = 'AP'
  AND geolocation_city = 'macapa';

-- Пункт 9: второй индекс другого типа — покрывающий (только ключ zip_prefix, остальное в INCLUDE) для точного поиска по префиксу
CREATE INDEX i_geo_zip_prefix_include ON olist.geolocation (geolocation_zip_code_prefix) INCLUDE (geolocation_lat, geolocation_lng, geolocation_city, geolocation_state);

-- Пункт 5: обновление статистики после появления второго индекса
ANALYZE olist.geolocation;

-- Пункт 6 Опыт 1 (ПОСЛЕ): Index Only Scan с Heap Fetches: 0 — таблица не читается вообще
EXPLAIN (ANALYZE, BUFFERS)
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state
FROM olist.geolocation
WHERE geolocation_zip_code_prefix = 13214;

-- Пункт 9: третий индекс — частичный по штатам Амазонас/Амапа/Рорайма, где идёт облачное развёртывание варианта
CREATE INDEX i_geo_zip_am_partial ON olist.geolocation (geolocation_zip_code_prefix) INCLUDE (geolocation_lat, geolocation_lng)
WHERE geolocation_state IN ('AM', 'AP', 'RR');

-- Пункт 5: обновление статистики после появления частичного индекса
ANALYZE olist.geolocation;

-- Пункт 9: план запроса по Манаусу (шлюзовый город Амазонаса) — над частичным индексом нет условий, оба индекса конкурируют
EXPLAIN (ANALYZE, BUFFERS)
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng
FROM olist.geolocation
WHERE geolocation_state = 'AM'
  AND geolocation_city = 'manaus';

-- Пункт 7: низкая селективность — диапазон префиксов 6000-6999 (29 893 строки, 3,0 % таблицы), покрывающий индекс проигрывает параллельному сканированию
EXPLAIN (ANALYZE, BUFFERS)
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng
FROM olist.geolocation
WHERE geolocation_zip_code_prefix BETWEEN 6000 AND 6999;

-- Пункт 7: предельно низкая селективность — город сао-паулу штата SP (135 799 строк, 13,6 % таблицы): Bitmap Heap Scan по ключу варианта и 1343 страницы
EXPLAIN (ANALYZE, BUFFERS)
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng
FROM olist.geolocation
WHERE geolocation_state = 'SP'
  AND geolocation_city = 'sao paulo';

-- Пункт 7: контроль — тот же ключ варианта на малом городе (Боа-Вишта, RR, 646 строк): высокая селективность, обычный Index Scan
EXPLAIN (ANALYZE, BUFFERS)
SELECT geolocation_zip_code_prefix, geolocation_lat, geolocation_lng
FROM olist.geolocation
WHERE geolocation_state = 'RR'
  AND geolocation_city = 'boa vista';

-- Пункт 8: размеры таблицы и индексов через pg_relation_size / pg_size_pretty и доля от кучи
WITH parts AS (
    SELECT c.relname AS object,
           CASE c.relkind WHEN 'r' THEN 'heap' ELSE 'index' END AS kind,
           CASE WHEN c.relkind = 'i' THEN pg_get_indexdef(c.oid) END AS definition,
           pg_relation_size(c.oid) AS main,
           CASE WHEN c.relkind = 'r' THEN pg_table_size(c.oid) - pg_relation_size(c.oid) ELSE 0 END AS aux_fsm_vm
    FROM pg_class AS c
    WHERE c.oid = 'olist.geolocation'::regclass
       OR c.oid IN (SELECT indexrelid FROM pg_index WHERE indrelid = 'olist.geolocation'::regclass)
)
SELECT object, kind, definition, main, aux_fsm_vm,
       main + aux_fsm_vm AS total_bytes,
       pg_size_pretty(main::bigint) AS main_size,
       round(100.0 * (main + aux_fsm_vm)
             / nullif(max(main + aux_fsm_vm) FILTER (WHERE kind = 'heap') OVER (), 0), 1) AS pct_of_heap,
       pg_size_pretty((main + aux_fsm_vm)::bigint) AS total_size
FROM parts
ORDER BY kind, total_bytes DESC;

-- Пункт 10: удаление покрывающего индекса
DROP INDEX IF EXISTS olist.i_geo_zip_prefix_include;

-- Пункт 10: удаление частичного индекса
DROP INDEX IF EXISTS olist.i_geo_zip_am_partial;

-- Пункт 10: удаление составного индекса по ключу варианта
DROP INDEX IF EXISTS olist.i_geo_city_state_zip;

-- Пункт 10: контроль — в схеме olist остались только первичные ключи, схема возвращена в исходное состояние
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'olist'
ORDER BY tablename, indexname;
