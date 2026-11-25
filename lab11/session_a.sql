-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 12)
-- Транзакции, конкурентный доступ и блокировки

-- СЕАНС A. Два окна SQL-редактора DBeaver на одном соединении, автокоммит выключен.
-- Каждый блок выполняется отдельно (Ctrl+Enter); ждать там, где написано [WAIT HERE].
-- Перед началом выполнить lab11/lab11.sql: он создаёт lab.inventory с qty = 10 и пустой журнал.

-- step 1: сеанс A узнаёт свой pid, запомнить число из результата [WAIT: в сеансе B получить другой pid]
SELECT pg_backend_pid() AS pid_a;

-- step 2: сеанс A читает запас первого товара по алфавиту, ожидается qty = 10 [WAIT HERE: дать сеансу B прочитать ту же строку]
SELECT product_id, qty FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 3: сеанс A начинает транзакцию потерянного обновления
BEGIN;

-- step 4: сеанс A записывает константу 9 вместо вычисления qty - 1 — это и есть ошибка read-modify-write
UPDATE lab.inventory SET qty = 9, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 5: сеанс A завершает транзакцию [WAIT HERE: теперь сеанс B может дописать свою константу]
COMMIT;

-- step 6: сеанс A проверяет итог: qty = 9, version = 2 — обновление B потерялось
SELECT product_id, qty, version FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 7: сеанс A возвращает товар в исходное состояние перед следующим экспериментом
UPDATE lab.inventory SET qty = 10, version = 0;

-- step 8: сеанс A берёт строку под блокировку на время своей транзакции
BEGIN;

-- step 9: сеанс A блокирует товар SELECT ... FOR UPDATE [WAIT HERE: переключиться в сеанс B, он повиснет]
SELECT product_id, qty FROM lab.inventory ORDER BY product_id LIMIT 1 FOR UPDATE;

-- step 10: сеанс A уменьшает остаток, пока держит блокировку
UPDATE lab.inventory SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 11: сеанс A снимает блокировку, ожидающий сеанс B продолжится [WAIT HERE: вернуться в сеанс B]
COMMIT;

-- step 12: сеанс A проверяет, что оба сеанса уменьшили остаток без потерь (qty = 8, version = 2)
SELECT product_id, qty, version FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 13: сеанс A восстанавливает запас 10 для эксперимента с атомарным UPDATE
UPDATE lab.inventory SET qty = 10, version = 0;

-- step 14: сеанс A открывает транзакцию и забирает последнюю единицу атомарным UPDATE
BEGIN;

-- step 15: сеанс A выполняет атомарное резервирование, 1 строка в результате [WAIT HERE: сеанс B пробует то же самое]
UPDATE lab.inventory SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1) AND qty > 0
RETURNING product_id, qty, version;

-- step 16: сеанс A пишет движение в журнал
INSERT INTO lab.inventory_movements (product_id, delta, kind, qty_after, note)
SELECT product_id, -1, 'reserve', qty, 'session A'
FROM lab.inventory WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 17: сеанс A фиксирует резервирование [WAIT HERE: теперь сеанс B получит 0 строк]
COMMIT;

-- step 18: сеанс A считает строки журнала с kind = 'reserve' в READ COMMITTED
BEGIN;

-- step 19: сеанс A включает READ COMMITTED явно, чтобы уровень был зафиксирован в выводе
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- step 20: сеанс A читает qty = 10 (после восстановления ниже) [WAIT HERE: сеанс B меняет значение и коммитит]
SELECT qty FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 21: сеанс A повторяет чтение в той же транзакции: значение изменилось — неповторяемое чтение
SELECT qty FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 22: сеанс A завершает транзакцию
COMMIT;

-- step 23: сеанс A открывает транзакцию повторяемого чтения
BEGIN;

-- step 24: сеанс A включает REPEATABLE READ
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- step 25: сеанс A читает qty, запомнить значение [WAIT HERE: сеанс B снова меняет и коммитит]
SELECT qty FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 26: сеанс A читает снова: значение прежнее (снимок транзакции)
SELECT qty FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 27: сеанс A пытается изменить строку, изменённую конкурентом: could not serialize access due to concurrent update
UPDATE lab.inventory SET qty = qty - 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 28: сеанс A откатывает прерванную транзакцию (после ошибки любая команда требует ROLLBACK)
ROLLBACK;

-- step 29: сеанс A открывает транзакцию для фантомного COUNT
BEGIN;

-- step 30: сеанс A включает READ COMMITTED
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- step 31: сеанс A считает движения резервирования [WAIT HERE: сеанс B вставляет строку]
SELECT count(*) AS reserve_rows FROM lab.inventory_movements WHERE kind = 'reserve';

-- step 32: сеанс A повторяет COUNT: появилась лишняя строка — фантом
SELECT count(*) AS reserve_rows FROM lab.inventory_movements WHERE kind = 'reserve';

-- step 33: сеанс A завершает транзакцию
COMMIT;

-- step 34: сеанс A открывает транзакцию для взаимной блокировки
BEGIN;

-- step 35: сеанс A блокирует первый товар [WAIT HERE: сеанс B блокирует второй товар]
UPDATE lab.inventory SET qty = qty - 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 36: сеанс A ждёт второй товар, которым владеет B; сервер прервёт транзакцию, замкнувшую цикл [WAIT HERE: ожидать ошибку 40P01]
UPDATE lab.inventory SET qty = qty - 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id OFFSET 1 LIMIT 1);

-- step 37: сеанс A откатывает транзакцию, если именно она получила deadlock detected
ROLLBACK;

-- step 38: сеанс A запускает последовательный уровень и читает предикат qty > 5
BEGIN;

-- step 39: сеанс A включает SERIALIZABLE
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- step 40: сеанс A читает количество строк с запасом больше 5 [WAIT HERE: сеанс B читает тот же предикат]
SELECT count(*) AS rows_over_5 FROM lab.inventory WHERE qty > 5;

-- step 41: сеанс A изменяет первый товар [WAIT HERE: сеанс B изменяет второй]
UPDATE lab.inventory SET qty = qty - 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 42: сеанс A фиксирует транзакцию, обычно первой
COMMIT;

-- step 43: сеанс A возвращает таблицы в исходное состояние после всех экспериментов
UPDATE lab.inventory SET qty = 10, version = 0;

-- step 44: сеанс A очищает журнал движений
TRUNCATE TABLE lab.inventory_movements RESTART IDENTITY;
