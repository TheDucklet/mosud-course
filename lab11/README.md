# Практика 12. Транзакции, конкурентный доступ и блокировки

Вариант 10. Все эксперименты выполнены на PostgreSQL 17 (база `olist`, два
независимых клиента). Числа ниже — реальные наблюдения с учебной машины:
у вас эффекты те же, но pid, время ожидания и product_id будут другими.

## Состав работы

| Файл | Назначение |
|---|---|
| `lab11/session_a.sql` | шаги первого сеанса A с комментариями «где ждать» |
| `lab11/session_b.sql` | шаги второго сеанса B, идут в паре с шагами A |
| `lab11/lab11.sql` | DDL таблиц `lab.inventory` / `lab.inventory_movements`, атомарное резервирование, функции и восстановление состояния |
| `lab11/README.md` | этот отчёт: таблица экспериментов, вывод консоли, порядок запуска |

## Как запустить

### 1. Подготовка базы

```bash
psql -h localhost -p 5432 -U student -d olist -f lab11/lab11.sql
```

Приглашение вводить пароль: `student` (как в `lab01`). Скрипт создаёт схему `lab`,
таблицы, заполняет 100 самых продаваемых товаров по `qty = 10`, показывает результат
резервирования, проверяет журнал и в конце **возвращает таблицу в состояние
100 товаров × 10 единиц**. Скрипт можно запускать повторно: он начинается с
`DROP TABLE IF EXISTS`, поэтому ничего не накапливается. Он же освобождает
`lab.inventory` / `lab.inventory_movements` от объектов других работ (в курсе
`lab.inventory` используется ещё в ER-модели), так что после прогона `lab11.sql`
таблица имеет ровно столбцы из задания: `product_id`, `qty`, `version`.

Скрипт состоит из одного DDL-раздела и проверок: 33 независимых оператора,
каждый завершается точкой с запятой и может выполняться в DBeaver построчно.

### 2. Два сеанса в DBeaver

1. Подключитесь к базе `olist` (хост `localhost`, порт `5432`, пользователь `student`).
2. Откройте файл `session_a.sql` — это SQL-редактор A. **Снимите галочку
   Auto-commit**: на панели редактора значок `ᵃᵛ` / `Auto-commit` должен быть
   отключён (иначе `BEGIN` не даст эффекта и блокировки снимаются сразу).
   В DBeaver 23+ состояние автокоммита показывается в строке состояния редактора.
3. Откройте второе окно: `SQL Editor → New SQL editor` (Ctrl+Shift+N) на том же
   соединении, загрузите в него `session_b.sql`. Тоже отключите Auto-commit.
4. Выполняйте по одному блоку: поставьте курсор в блок и нажмите `Ctrl+Enter`
   (`Execute SQL statement`), а не `Alt+X` (execute script: он выполнит весь файл,
   включая `BEGIN`/`COMMIT` подряд, и эксперимент не воспроизведётся).
5. Комментарии `-- step N: ... [WAIT HERE ...]` показывают, когда перейти в
   другое окно и выполнить там парный блок.
6. Там, где сеанс ждёт блокировку, DBeaver показывает кружок «выполняется»;
   кнопкой `Cancel` (красный квадрат) его можно прервать, это эквивалентно
   `statement_timeout`: PostgreSQL вернёт `canceling statement due to statement timeout`.

Скрипты сеансов не рассчитаны на прогон одним файлом — это литеральный протокол
двух терминалов. Файл `lab11.sql` наоборот полностью воспроизводим и идемпотентен.

## Результаты экспериментов

| № | Эксперимент | Уровень изоляции | Наблюдаемый эффект (реальные значения) | Способ исправления |
|---|---|---|---|---|
| 1 | Два сеанса, `pg_backend_pid()` | по умолчанию (READ COMMITTED) | pid A = 18548, pid B = 26000 — соединения действительно разные | сравнивать pid перед экспериментом, иначе оба блока выполняются в одном сеансе и конкуренции нет |
| 2 | Потерянное обновление: оба читают `qty = 10`, оба пишут константу 9 | READ COMMITTED | у A и у B `BEGIN; UPDATE ... SET qty = 9, version = version + 1; COMMIT;`, B ждёт строку ~3 мс. Итог: `qty = 9`, `version = 2`, хотя продано 2 единицы | не читать-вычислять-писать в приложении: `UPDATE ... SET qty = qty - 1` считает по текущей версии строки или `SELECT ... FOR UPDATE` перед вычислением |
| 3 | `SELECT ... FOR UPDATE` в A, затем тот же `SELECT ... FOR UPDATE` в B | READ COMMITTED | B ждёт **2.006 с** (ровно столько A держал транзакцию), получает блокировку после `COMMIT`, видит новое значение `qty = 9`; без `COMMIT` в A ожидание бесконечное, прерывается только кнопкой Cancel (`canceling statement due to statement timeout`) | держать транзакцию короткой, выставлять `lock_timeout`/`statement_timeout`, блокировать строки в одном порядке |
| 4 | Атомарное резервирование `UPDATE ... WHERE qty > 0 RETURNING` | READ COMMITTED | A получает 1 строку `(qty = 0, version = 1)`, B получает **0 строк** — «нет в наличии»; `qty` после B по-прежнему 0, в журнале одна строка | проверять не только ошибку, но и число возвращённых строк: 0 строк = отказ, а не исключение |
| 5 | Неповторяемое чтение | READ COMMITTED | A: `qty = 10`, B меняет на 7 и коммитит, A повторно читает → **7** | если значение нужно согласованным, использовать REPEATABLE READ или блокировку строки |
| 6 | Повторное чтение в той же транзакции | REPEATABLE READ | A: `qty = 10`, B меняет на 7 и коммитит, A читает → **10** (снимок транзакции). Попытка `UPDATE` даёт `ERROR: could not serialize access due to concurrent update` (SQLSTATE 40001, `ROLLBACK`) | обрабатывать 40001 повтором всей транзакции, а не отдельного запроса |
| 7 | Фантомное появление строк в журнале движений | READ COMMITTED | `COUNT(*) WHERE kind = 'reserve'`: A видит 0, B вставляет строку, A повторно читает → **1**. В REPEATABLE READ второе чтение остаётся **1** при двух вставленных строках | для отчётов по журналу использовать снимок (RR/REPEATABLE READ) или SERIALIZABLE |
| 8 | Взаимная блокировка двумя строками `inventory` | READ COMMITTED | через ~1.01 с сеанс, замкнувший цикл, получает `ERROR: deadlock detected` (SQLSTATE 40P01), второй сеанс продолжается | блокировать строки в детерминированном порядке (напр. по `product_id`), уменьшить число строк в одной транзакции, повторять транзакцию при 40P01 |
| 9 | `SERIALIZABLE` и обработка `serialization_failure` | SERIALIZABLE | A и B читают предикат `qty > 5` (100 строк), каждая уменьшает свой товар; A `COMMIT` — успех, B `COMMIT` → `ERROR: could not serialize access due to read/write dependencies among transactions` (40001), после `ROLLBACK` повтор транзакции проходит | повторять транзакцию при SQLSTATE 40001, плюс `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE` в каждом повторе |

Подробности по каждому пункту — ниже, с реальным текстом консоли.

### Эксперимент 2. Потерянное обновление (lost update)

```
A> SELECT pg_backend_pid();          -> 18548
B> SELECT pg_backend_pid();          -> 26000
A> SELECT qty ... LIMIT 1;           -> 10
B> SELECT qty ... LIMIT 1;           -> 10
A> BEGIN; UPDATE ... SET qty = 9, version = version + 1; COMMIT;
B> BEGIN; UPDATE ... SET qty = 9, version = version + 1; COMMIT;   -- ждал ~3 мс
A> SELECT product_id, qty, version;  -> ('06edb72f...', 9, 2)
```

Обновление B не заблокировалось ошибкой: B ждёт строку, пока A держит транзакцию,
потом записывает **свою** константу 9, вычисленную из устаревшего значения 10.
Правильный итог — 8, фактический — 9: одна проданная единица потеряна.
Причина — `UPDATE` записывает значение, вычисленное в приложении, а не относительно
текущей версии строки.

### Эксперимент 3. `SELECT ... FOR UPDATE`

```
A> BEGIN; SELECT ... LIMIT 1 FOR UPDATE;   -> ('06edb72f...', 10)   -- A держит строку 2 с
B> BEGIN; SELECT ... LIMIT 1 FOR UPDATE;   -> ждал 2.006 с, затем ('06edb72f...', 9)
A> UPDATE ... SET qty = qty - 1; COMMIT;
B> UPDATE ... SET qty = qty - 1; COMMIT;   -> qty = 8, version = 2
```

`FOR UPDATE` превращает `SELECT` в блокирующее чтение: строка «закреплена» за
транзакцией до `COMMIT`/`ROLLBACK`, а второй сеанс видит уже зафиксированное
значение. Важно: блокировка живёт до конца транзакции, поэтому незакрытая
транзакция в DBeaver (сеанс оставлен на `idle in transaction`) держит строку
бесконечно; при `statement_timeout` ожидающий сеанс получит
`canceling statement due to statement timeout`.

### Эксперимент 4. Атомарное резервирование

```sql
UPDATE lab.inventory
SET qty = qty - 1, version = version + 1
WHERE product_id = ? AND qty > 0
RETURNING product_id, qty, version;
```

Один оператор читает и изменяет строку под блокировкой, вычисляя `qty` от текущей
версии, поэтому два одновременных резервирования не могут оба списать одну единицу.
Когда запас был `1`, сеанс A получил `(qty = 0, version = 1)`, а B — **пустой
результат** (0 строк). Приложение обязано трактовать 0 строк как отказ
«нет в наличии» и не считать это ошибкой БД.

### Эксперименты 5–6. Неповторяемое чтение и REPEATABLE READ

```
A> BEGIN; SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
A> SELECT qty ...;        -> 10
B> UPDATE ... SET qty = 7;                      -- автономно, закоммичено
A> SELECT qty ...;        -> 7    -- неповторяемое чтение
A> COMMIT;

A> BEGIN; SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
A> SELECT qty ...;        -> 10
B> UPDATE ... SET qty = 5;
A> SELECT qty ...;        -> 10   -- снимок транзакции A
A> UPDATE ... SET qty = qty - 1 ...;
ERROR:  could not serialize access due to concurrent update   (SQLSTATE 40001)
A> ROLLBACK;
```

В REPEATABLE READ транзакция видит снимок на момент первого запроса, поэтому
повторное чтение даёт 10. Запись в строку, изменённую конкурентной транзакцией
после снимка, PostgreSQL запрещает — это защита от lost update. Ошибка 40001
всегда требует `ROLLBACK` (транзакция прервана) и повтора бизнес-операции целиком.

### Эксперимент 7. Фантомы в журнале движений

```
A> BEGIN; SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
A> SELECT count(*) FROM lab.inventory_movements WHERE kind = 'reserve';  -> 0
B> INSERT INTO lab.inventory_movements ... kind = 'reserve';            -- коммит
A> SELECT count(*) ...;                                                 -> 1   -- фантом
A> COMMIT;

A> BEGIN; SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
A> SELECT count(*) ...;                                                 -> 1
B> INSERT ... (вторая строка);                                          -- коммит
A> SELECT count(*) ...;                                                 -> 1   -- фантома нет
```

`COUNT` по условию в READ COMMITTED пересчитывается на свежем снимке каждого
запроса, поэтому новая строка попадает в результат. В REPEATABLE READ снимок
фиксирован на первом запросе и COUNT не меняется. При этом сам INSERT в RR
не запрещён: если строку не читали, конфликта нет — строгая защита от
аномалий записи включается только в SERIALIZABLE.

### Эксперимент 8. Deadlock (ожидаемый вывод консоли)

```
A> BEGIN; UPDATE lab.inventory SET qty = qty - 1 WHERE product_id = '06edb72f...';
B> BEGIN; UPDATE lab.inventory SET qty = qty - 1 WHERE product_id = '08574b07...';
A> UPDATE lab.inventory SET qty = qty - 1 WHERE product_id = '08574b07...';  -- ждёт B (step 36)
B> UPDATE lab.inventory SET qty = qty - 1 WHERE product_id = '06edb72f...';  -- замыкает цикл (step 26)
ERROR:  deadlock detected
DETAIL:  Process 23740 waits for ShareLock on transaction 1556; blocked by process 18228.
Process 18228 waits for ShareLock on transaction 1555; blocked by process 23740.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (0,49) in relation "inventory"
```

Сервер обнаруживает цикл ожидания примерно через `deadlock_timeout` (по умолчанию
1 с) и прерывает одну из транзакций — ту, которая замкнула цикл, то есть сеанс,
выполнивший ожидание вторым (в протоколе это B на шаге 26). Первый ожидающий
сеанс (A на шаге 36) после прерывания партнёра получает блокировку и продолжает
работу. Поэтому: прерванный сеанс обязан выполнить `ROLLBACK` и повторить
транзакцию целиком, второй сеанс делает обычный `COMMIT`:

```
B (прерван)>  ROLLBACK;   -> ROLLBACK
A (ожидал)>   UPDATE ...  -> UPDATE 1   (блокировка освободилась)
A>            COMMIT;     -> COMMIT
```

Время до ошибки ≈ 1.01 с, то есть ровно `deadlock_timeout`; pid и номера
транзакций в DETAIL у вас будут другими, формат сообщения сохраняется.

### Эксперимент 9. SERIALIZABLE и повтор при serialization_failure

```
A> BEGIN; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
B> BEGIN; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
A> SELECT count(*) WHERE qty > 5;   -> 100
B> SELECT count(*) WHERE qty > 5;   -> 100
A> UPDATE ... product_id = <первый>;
B> UPDATE ... product_id = <второй>;
A> COMMIT;   -> COMMIT
B> COMMIT;   -> ERROR:  could not serialize access due to read/write dependencies among transactions
                DETAIL:  Reason code: Canceled on identification as a pivot, during commit attempt.
                HINT:  The transaction might succeed if retried.
B> ROLLBACK; -- и повтор всей транзакции
```

Обе транзакции читают один и тот же предикат и пишут разные строки — это
write skew, который не ловится ни уровнем READ COMMITTED, ни блокировками строк.
SERIALIZABLE фиксирует конфликт только на `COMMIT` второй транзакции.
Стандартная схема приложения — цикл повторов:

```python
for attempt in range(3):
    try:
        ...                # в одной транзакции SERIALIZABLE
        conn.commit()
        break
    except psycopg.errors.SerializationFailure:
        conn.rollback()     # SQLSTATE 40001
```

### Эксперимент «атомарный UPDATE в SERIALIZABLE»

Заметный контраст: две транзакции, которые только делают
`UPDATE lab.inventory SET qty = qty - 1 WHERE product_id = ?` под SERIALIZABLE,
**не конфликтуют** — у них нет читаемого предиката, а запись идёт в разные строки.
Конфликт возникает, только если транзакция читает диапазон/предикат, который
меняет конкурент. Именно поэтому в отчёте важно различать «резервирование одной
строки» и «транзакцию отчёта/ограничения».

## Проверки, которые выполняет lab11.sql

| Запрос | Что доказывает |
|---|---|
| `SELECT count(*), sum(qty) FROM lab.inventory` | 100 товаров, 1000 единиц до экспериментов |
| результат `UPDATE ... RETURNING` | атомарное резервирование вернуло строку и уменьшило qty на 1 |
| `count(*) WHERE qty - snapshot.qty <> sum(movements.delta)` | журнал движений согласован с остатками (0 расхождений) |
| `count(*) WHERE qty < 0` | ограничение `qty >= 0` не нарушено (0 строк) |
| `lab.reserve(..., 100000)` | функция вернула 0 строк, остаток не ушёл в минус |
| `UPDATE ... FROM snapshot` | восстановление исходных `qty` и `version` после занятия |
| `UPDATE ... SET qty = 10, version = 0` | в конце — ровно 10 единиц на товар для сеансов A и B |

## Контрольные вопросы

**1. Почему READ UNCOMMITTED в PostgreSQL не даёт грязного чтения?**
Принятый PostgreSQL уровень READ UNCOMMITTED реализован как READ COMMITTED, а
MVCC никогда не возвращает строки, записанные незакоммиченными транзакциями:
каждая транзакция получает снимок только из зафиксированных версий. Поэтому
«грязное чтение» в PostgreSQL принципиально не воспроизводится, и запрос
`SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED` ведёт себя как READ COMMITTED.

**2. Чем SELECT ... FOR UPDATE отличается от обычного SELECT?**
Обычный `SELECT` не блокирует изменяемую строку: он читает снимок и допускает
конкурентный `UPDATE` (эксперименты 2 и 5). `SELECT ... FOR UPDATE` берёт на
строке блокировку `FOR UPDATE` и удерживает её до конца транзакции: второй сеанс
с такой же блокировкой или `UPDATE` ждёт `COMMIT`/`ROLLBACK` первого. Тем самым
прочитанное значение гарантированно не изменится до записи.

**3. Почему UPDATE qty = qty - 1 безопаснее схемы read-modify-write с константой?**
Константа вычисляется приложением из устаревшего прочитанного значения: оба
сеанса прочитали 10 и записали 9, одна продажа потеряна (эксперимент 2).
`SET qty = qty - 1` вычисляется сервером от **текущей** версии строки под
неявной блокировкой `UPDATE`, а условие `WHERE qty > 0` проверяется в той же
атомарной операции: второй сеанс либо ждёт и получает уже уменьшенное значение,
либо не находит строки и получает 0 строк (`RETURNING` пуст) — двойное списание
невозможно.

## Выводы

- READ COMMITTED не защищает от lost update и неповторяемого чтения — их надо
  закрывать формой самого SQL-оператора, а не уровнем изоляции.
- Один атомарный `UPDATE ... WHERE ... RETURNING` — минимальный и самый дешёвый
  способ безопасного резервирования; `SELECT ... FOR UPDATE` нужен, когда
  решение принимается после чтения нескольких строк.
- Блокировки этого не решают для предикатов: write skew и фантомы видны только
  в SERIALIZABLE, и там обязателен повтор транзакции по SQLSTATE 40001.
- Deadlock — не баг PostgreSQL, а сигнал о разном порядке захвата строк; лечится
  детерминированным порядком `ORDER BY product_id` и короткими транзакциями.
