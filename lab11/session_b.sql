-- Автор: Демерджев Никита Андреевич
-- Группа: ИНБО-21-23
-- Вариант: 10 (Практика 12)
-- Транзакции, конкурентный доступ и блокировки

-- СЕАНС B. Открыть во втором окне SQL-редактора DBeaver (кнопка "New SQL editor"), автокоммит выключить.
-- Шаги идут парами с session_a.sql: выполнять блок, когда в комментарии сеанса A стоит WAIT.
-- Удалить в конце таблицы-артефакты нельзя: оба файла работают с одними и теми же объектами lab.

-- step 1: сеанс B узнаёт свой pid, он должен отличаться от pid сеанса A
SELECT pg_backend_pid() AS pid_b;

-- step 2: сеанс B читает тот же запас (qty = 10), что уже прочитал сеанс A [WAIT HERE: обоим сеансам известны 10]
SELECT product_id, qty FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 3: сеанс B начинает транзакцию потерянного обновления
BEGIN;

-- step 4: сеанс B записывает ту же константу 9, вычисленную из устаревшего значения 10
UPDATE lab.inventory SET qty = 9, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 5: сеанс B завершает транзакцию: итог qty = 9, хотя два сеанса продали по единице
COMMIT;

-- step 6: сеанс B проверяет итог потерянного обновления (qty = 9, version = 2) [WAIT HERE: переходить к шагу 8 сеанса A]
SELECT product_id, qty, version FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 7: сеанс B открывает транзакцию и пытается взять ту же строку под FOR UPDATE
BEGIN;

-- step 8: сеанс B ждёт блокировку, пока сеанс A не выполнит COMMIT [WAIT HERE: запомнить время ожидания]
SELECT product_id, qty FROM lab.inventory ORDER BY product_id LIMIT 1 FOR UPDATE;

-- step 9: сеанс B после снятия блокировки видит новое значение qty = 9
SELECT product_id, qty FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 10: сеанс B уменьшает остаток на единицу, теперь без потерь
UPDATE lab.inventory SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 11: сеанс B завершает транзакцию, итог qty = 8, version = 2
COMMIT;

-- step 12: сеанс B проверяет итог эксперимента с блокировкой [WAIT HERE: вернуться к шагу 13 сеанса A]
SELECT product_id, qty, version FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 13: сеанс B ставит запас 1, чтобы следующая транзакция A забирала последнюю единицу
UPDATE lab.inventory SET qty = 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 14: сеанс B открывает транзакцию и пытается резервировать ту же последнюю единицу
BEGIN;

-- step 15: сеанс B выполняет атомарный UPDATE по строке, которую держит сеанс A [WAIT HERE: ждать шага 17 сеанса A]
UPDATE lab.inventory SET qty = qty - 1, version = version + 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1) AND qty > 0
RETURNING product_id, qty, version;

-- step 16: сеанс B получает 0 строк: резервировать нечего, приложение должно вернуть «нет в наличии»
SELECT count(*) AS reserved_by_b FROM lab.inventory_movements WHERE note = 'session B';

-- step 17: сеанс B завершает транзакцию без изменений
COMMIT;

-- step 18: сеанс B возвращает запас 10 для эксперимента с неповторяемым чтением
UPDATE lab.inventory SET qty = 10
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 19: сеанс B меняет запас и коммитит изменение [WAIT HERE: сеанс A уже прочитал 10, теперь читает снова]
UPDATE lab.inventory SET qty = 7
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 20: сеанс B снова меняет запас для проверки REPEATABLE READ [WAIT HERE: ждать шага 25 сеанса A]
UPDATE lab.inventory SET qty = 5
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 21: сеанс B читает изменённое значение
SELECT qty FROM lab.inventory ORDER BY product_id LIMIT 1;

-- step 22: сеанс B вставляет движение резервирования для фантомного COUNT [WAIT HERE: сеанс A считает строки в READ COMMITTED]
INSERT INTO lab.inventory_movements (product_id, delta, kind, qty_after, note)
SELECT product_id, -1, 'reserve', qty, 'phantom by B'
FROM lab.inventory WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 23: сеанс B проверяет, что строка видна за пределами транзакции A [WAIT HERE: сеанс A перечитывает COUNT]
SELECT count(*) AS reserve_rows FROM lab.inventory_movements WHERE kind = 'reserve';

-- step 24: сеанс B открывает транзакцию взаимной блокировки
BEGIN;

-- step 25: сеанс B блокирует второй товар [WAIT HERE: сеанс A блокирует первый на шаге 35]
UPDATE lab.inventory SET qty = qty - 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id OFFSET 1 LIMIT 1);

-- step 26: сеанс B ждёт первый товар, которым владеет A, и замыкает цикл: deadlock detected (SQLSTATE 40P01)
UPDATE lab.inventory SET qty = qty - 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id LIMIT 1);

-- step 27: сеанс B откатывает прерванную транзакцию: сервер уже снял её блокировки, A продолжит работу
ROLLBACK;

-- step 28: сеанс B открывает транзакцию SERIALIZABLE и читает тот же предикат
BEGIN;

-- step 29: сеанс B включает SERIALIZABLE
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- step 30: сеанс B считает строки с запасом больше 5, получает то же число, что и A
SELECT count(*) AS rows_over_5 FROM lab.inventory WHERE qty > 5;

-- step 31: сеанс B изменяет второй товар
UPDATE lab.inventory SET qty = qty - 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id OFFSET 1 LIMIT 1);

-- step 32: сеанс B фиксирует: после COMMIT сеанса A здесь будет could not serialize access due to read/write dependencies (40001)
COMMIT;

-- step 33: сеанс B повторяет транзакцию после serialization_failure — обычный приём приложения
BEGIN;

-- step 34: сеанс B повторно включает SERIALIZABLE и читает предикат
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS rows_over_5 FROM lab.inventory WHERE qty > 5;

-- step 35: сеанс B повторно изменяет второй товар уже без конфликта
UPDATE lab.inventory SET qty = qty - 1
WHERE product_id = (SELECT product_id FROM lab.inventory ORDER BY product_id OFFSET 1 LIMIT 1);

-- step 36: сеанс B фиксирует повторную транзакцию
COMMIT;

-- step 37: сеанс B возвращает таблицу в исходное состояние (qty = 10, version = 0) после всех экспериментов
UPDATE lab.inventory SET qty = 10, version = 0;

-- step 38: сеанс B очищает журнал движений
TRUNCATE TABLE lab.inventory_movements RESTART IDENTITY;
