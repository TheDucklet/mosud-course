# Практика 8. ER-модель и расширение предметной области (вариант 10)

**Тема варианта:** «Перемещения между складами» — `warehouses`, `inventory`, `transfers`,
`transfer_items` (источник, назначение и позиции перемещения).

| Параметр | Значение |
|---|---|
| СУБД | PostgreSQL 17 |
| База / схема | `olist`; учебные объекты — схема **`lab`**, исходные данные — схема **`olist`** (только чтение) |
| Файлы работы | `lab08.sql` — DDL, ограничения, тестовые данные, проверки; `erDiagram.png` — ER-диаграмма; `erDiagram.drawio` — редактируемый исходник для diagrams.net |

## 1. Постановка задачи

В исходном наборе Olist нет складской модели: товар продаётся напрямую продавцом, и нельзя
указать, с какого физического склада он уходит и как перераспределяется между складами перед
продажей. Расширение добавляет четыре таблицы:

| Таблица | Смысл | Ключ |
|---|---|---|
| `lab.warehouses` | справочник складов | `warehouse_id` (surrogate); альтернативные `warehouse_code`, `(city, warehouse_name)` |
| `lab.warehouse_inventory` | остаток товара на складе | составной `(warehouse_id, product_id)`; FK на `olist.products` |
| `lab.warehouse_transfers` | шапка перемещения: склад-источник → склад-назначение, даты, статус | `transfer_id` (surrogate); альтернативный `transfer_no` |
| `lab.warehouse_transfer_items` | позиции перемещения — связь M:N `transfers × products` с количеством | составной `(transfer_id, product_id)`; FK на `olist.products` |

С реальными объектами Olist связаны **две** таблицы: `lab.warehouse_inventory` и `lab.warehouse_transfer_items`
(обе — внешний ключ на `olist.products(product_id)`). Города и штаты складов берутся из
`olist.sellers`, поэтому справочник согласован с реальными регионами Olist, а сами данные Olist
нигде не дублируются — хранятся только ключи.

## 2. ER-диаграмма

Основной файл — `erDiagram.png`; редактируемый исходник — `erDiagram.drawio`.

| Связь | Кратность | Обязательность | Реализация |
|---|---|---|---|
| `warehouses` — `inventory` | 1:N | обязательная на стороне N (склад не может быть NULL) | FK `warehouse_id`, `ON DELETE RESTRICT` |
| `olist.products` — `inventory` | 0..1:N | необязательная: товар может не иметь остатков ни на одном складе | FK `product_id`, `ON DELETE RESTRICT` |
| `warehouses` — `transfers` (источник) | 1:N | обязательная, `NOT NULL` | FK `source_warehouse_id` |
| `warehouses` — `transfers` (назначение) | 1:N | обязательная, `NOT NULL` | FK `destination_warehouse_id` |
| `transfers` — `transfer_items` | 1:N | обязательная: позиция без шапки не существует (слабая сущность) | FK `transfer_id`, `ON DELETE CASCADE` |
| `olist.products` — `transfer_items` | 1:N | обязательная | FK `product_id`, `ON DELETE RESTRICT` |

Ключевые решения модели:

* связь `transfers` — `products` имеет кратность **M:N**, поэтому вынесена в отдельную таблицу
  `transfer_items` с собственным атрибутом `qty`;
* запрет «отправить со склада на него же» — не кратность диаграммы, а бизнес-правило B4
  (`CHECK`), потому что диаграмма не умеет выражать сравнение двух значений одной строки;
* удаление перемещения каскадно удаляет его позиции (`CASCADE`), а удаление склада или товара
  запрещено (`RESTRICT`) — история перемещений должна оставаться целостной.

## 3. Бизнес-правила и реализующие их ограничения

| № | Бизнес-правило | Ограничение в БД | Тип |
|---|---|---|---|
| B1 | У склада есть уникальный код и уникальное название в пределах города | `uq_warehouses_code UNIQUE (warehouse_code)`, `uq_warehouses_city_name UNIQUE (city, warehouse_name)` | альтернативный UNIQUE, составной UNIQUE |
| B2 | Перемещение отправляется из существующего склада A и принимается существующим складом B | `fk_warehouse_transfers_source`, `fk_warehouse_transfers_destination` → `lab.warehouses(warehouse_id)` | FK |
| B3 | У каждой строки склада, остатка и перемещения заполнены обязательные поля (всего 21 столбец `NOT NULL`) | `NOT NULL` на ключах, `warehouse_code`, `warehouse_name`, `city`, `state`, `is_active`, `created_at`, `qty_on_hand`, `reserved_qty`, `updated_at`, `transfer_no`, `source_warehouse_id`, `destination_warehouse_id`, `status`, `qty` | NOT NULL |
| B4 | Нельзя «переместить» товар со склада на тот же самый склад | `ck_warehouse_transfers_distinct CHECK (source_warehouse_id <> destination_warehouse_id)` | CHECK |
| B5 | Перемещение не может быть получено раньше отправки | `ck_warehouse_transfers_order_dates CHECK (shipped_at IS NULL OR received_at IS NULL OR received_at >= shipped_at)` | CHECK |
| B6 | Остаток неотрицателен, а резерв не превышает физический остаток | `ck_warehouse_inventory_qty_on_hand CHECK (qty_on_hand >= 0)`, `ck_warehouse_inventory_reserved CHECK (reserved_qty >= 0 AND reserved_qty <= qty_on_hand)` | CHECK |
| B7 | В одном перемещении товар встречается один раз (позиция уникальна) | `pk_warehouse_transfer_items PRIMARY KEY (transfer_id, product_id)` | составной PK |
| B8 | Остаток хранится в единственном экземпляре на пару «склад + товар» | `pk_warehouse_inventory PRIMARY KEY (warehouse_id, product_id)` | составной PK |
| B9 | Позиция ссылается только на существующий товар Olist и содержит положительное количество | `fk_warehouse_transfer_items_product` → `olist.products`, `ck_warehouse_transfer_items_qty CHECK (qty > 0)` | FK + CHECK |
| B10 | Статус перемещения — из фиксированного справочника; код штата склада — две латинские заглавные буквы; у склада корректный ZIP | `ck_warehouse_transfers_status CHECK (status IN ('draft','shipped','received','cancelled'))`, `ck_warehouses_state CHECK (state ~ '^[A-Z]{2}$')`, `ck_warehouses_zip CHECK (zip_code_prefix BETWEEN 1000 AND 99999)` | CHECK |

Сводка по видам ограничений (проверочный запрос №2, вывод в каталоге):

| Вид | Количество |
|---|---|
| `PRIMARY KEY` (`pk_`) | 4 (из них 2 составных) |
| `FOREIGN KEY` (`fk_`) | 6 (из них 3 на объекты `olist`, 3 внутри `lab`) |
| `UNIQUE` (`uq_`) | 3 (из них 1 составной) |
| `CHECK` (`ck_`) | 8 |
| `NOT NULL` | 21 столбец |

Требования задания выполнены с запасом: ≥3 таблицы (4), ≥2 таблицы с FK на Olist (2),
составной/альтернативный UNIQUE (3), ≥2 CHECK (8), ≥3 NOT NULL (21).

## 4. Тестовые данные и результаты запуска

Все значения выбираются подзапросами из `olist`, поэтому скрипт не зависит от конкретного
экземпляра данных и не содержит «вшитых» идентификаторов:

* **склады (5)** — `city`/`state`/`zip` берутся через `LATERAL` из `olist.sellers`
  (первый по `seller_id` продавец из каждого города: `sao paulo`, `rio de janeiro`,
  `curitiba`, `porto alegre`);
* **остатки (15 = 5 складов × 3 товара)** — три самых продаваемых товара категории
  `beleza_saude` по `olist.order_items`, со сдвигом на склад, чтобы наборы товаров различались;
* **перемещения (6)** — `created_at` = момент покупки реального заказа (`order_purchase_timestamp`)
  + смещение в часах, поэтому даты лежат в историческом диапазоне Olist (2016–2018);
* **позиции (12)** — по две позиции на перемещение, товары берутся из остатков склада-источника
  (перемещение физически обосновано).

Фактический результат запуска `lab08.sql` (запрос №5 и №7):

```
 table_name         | rows
--------------------+------
 lab.warehouses     |    5
 lab.warehouse_inventory      |   15
 lab.warehouse_transfers      |    6
 lab.warehouse_transfer_items |   12
```

Контроль ссылочной целостности (запрос №7): `items = 12`, `matched_in_olist = 12` —
все `product_id` позиций существуют в `olist.products`.

Отчёт «перемещение — источник — назначение — количество позиций» (запрос №6):

| transfer_no | source_city | destination_city | positions | total_qty |
|---|---|---|---|---|
| TR-0001 | sao paulo | sao paulo | 2 | 3 |
| TR-0002 | sao paulo | curitiba | 2 | 3 |
| TR-0003 | rio de janeiro | porto alegre | 2 | 3 |
| TR-0004 | sao paulo | rio de janeiro | 2 | 3 |
| TR-0005 | porto alegre | sao paulo | 2 | 3 |
| TR-0006 | curitiba | sao paulo | 2 | 3 |

Загрузка по складам (запрос №8: остатки и исходящие перемещения):

| warehouse_code | inventory_rows | transfers_out |
|---|---|---|
| WH-CWB1 | 3 | 1 |
| WH-POA1 | 3 | 1 |
| WH-RJ01 | 3 | 1 |
| WH-SP01 | 3 | 2 |
| WH-SP02 | 3 | 1 |

> `TR-0001` и `TR-0002` идут «sao paulo → sao paulo» — это разные склады (`WH-SP01` → `WH-SP02`)`,
> т.е. перевозка между складами одного города, правило B4 при этом соблюдено.

## 5. Ошибочные INSERT/UPDATE и отклоняющие их ограничения

Восемь утверждений присутствуют в `lab08.sql` **закомментированными** — иначе скрипт нельзя
выполнить сверху вниз в режиме `ON_ERROR_STOP=1`. Каждое проверено отдельно в psql внутри
транзакции с `ROLLBACK`; фактически полученные ошибки:

| № | Утверждение | Фактическая ошибка PostgreSQL | Ограничение |
|---|---|---|---|
| 1 | `UPDATE lab.warehouse_transfers SET destination_warehouse_id = source_warehouse_id WHERE transfer_no = 'TR-0001'` | `new row for relation "warehouse_transfers" violates check constraint "ck_warehouse_transfers_distinct"` | B4 |
| 2 | повторный `INSERT` позиции с тем же `(transfer_id, product_id)` | `duplicate key value violates unique constraint "pk_warehouse_transfer_items"` | B7 |
| 3 | `INSERT INTO lab.warehouse_transfers ... destination_warehouse_id = w.warehouse_id + 100` | `insert or update on table "warehouse_transfers" violates foreign key constraint "fk_warehouse_transfers_destination"` | B2 |
| 4 | `UPDATE lab.warehouse_transfers SET received_at = shipped_at - interval '1 day' WHERE transfer_no = 'TR-0003'` | `new row for relation "warehouse_transfers" violates check constraint "ck_warehouse_transfers_order_dates"` | B5 |
| 5 | `UPDATE lab.warehouse_inventory SET qty_on_hand = -1 ...` | `new row for relation "warehouse_inventory" violates check constraint "ck_warehouse_inventory_qty_on_hand"` | B6 |
| 6 | `INSERT INTO lab.warehouse_transfer_items ... product_id = 'no_such_product_000'` | `insert or update on table "warehouse_transfer_items" violates foreign key constraint "fk_warehouse_transfer_items_product"` | B9 |
| 7 | `UPDATE lab.warehouse_transfer_items SET qty = 0 ...` | `new row for relation "warehouse_transfer_items" violates check constraint "ck_warehouse_transfer_items_qty"` | B9 |
| 8 | повторный `INSERT INTO lab.warehouses ... warehouse_code = 'WH-SP01'` | `duplicate key value violates unique constraint "uq_warehouses_code"` | B1 |

## 6. Проверка схемы по системному каталогу

Скрипт содержит восемь проверочных запросов (все только читают, ничего не меняют):

| № | Запрос | Источник | Что показывает |
|---|---|---|---|
| 1 | все ограничения четырёх таблиц с определениями | `pg_constraint`, `pg_class`, `pg_namespace`, `pg_get_constraintdef` | 21 ограничение вида `pk_`/`fk_`/`uq_`/`ck_` |
| 2 | количество по видам | `pg_constraint` (`contype`) | 4 PK, 6 FK, 3 UNIQUE, 8 CHECK |
| 3 | все столбцы `NOT NULL` | `pg_attribute` (`attnotnull`), `format_type` | 21 столбец с типами |
| 4 | внешние ключи и их цели | `pg_constraint` (`confrelid`), `pg_class` | ссылки на `olist.products` и `lab.warehouses` |
| 5 | число строк в таблицах | сами таблицы | 5 / 15 / 6 / 12 |
| 6 | отчёт «перемещение — города — qty» | `lab.*` | данные загрузились корректно |
| 7 | все `product_id` позиций есть в `olist.products` | анти-соединение | 12 из 12 найдено |
| 8 | загрузка по складам | `LEFT JOIN` | остатки и исходящие перемещения |

Фактический вывод запроса №1 (21 строка, сокращённо — по одному-двум ограничениям на вид):

```
 table_name               |           constraint_name            |    kind     | definition
--------------------------+--------------------------------------+-------------+---------------------------------------------
 warehouse_inventory      | ck_warehouse_inventory_qty_on_hand   | CHECK       | CHECK ((qty_on_hand >= 0))
 warehouse_inventory      | ck_warehouse_inventory_reserved      | CHECK       | CHECK (((reserved_qty >= 0) AND (reserved_qty <= qty_on_hand)))
 warehouse_inventory      | fk_warehouse_inventory_product       | FOREIGN KEY | FOREIGN KEY (product_id) REFERENCES olist.products(product_id) ON DELETE RESTRICT
 warehouse_inventory      | fk_warehouse_inventory_warehouse     | FOREIGN KEY | FOREIGN KEY (warehouse_id) REFERENCES lab.warehouses(warehouse_id) ON DELETE RESTRICT
 warehouse_inventory      | pk_warehouse_inventory               | PRIMARY KEY | PRIMARY KEY (warehouse_id, product_id)
 warehouse_transfer_items | ck_warehouse_transfer_items_qty      | CHECK       | CHECK ((qty > 0))
 warehouse_transfer_items | fk_warehouse_transfer_items_product  | FOREIGN KEY | FOREIGN KEY (product_id) REFERENCES olist.products(product_id) ON DELETE RESTRICT
 warehouse_transfer_items | pk_warehouse_transfer_items          | PRIMARY KEY | PRIMARY KEY (transfer_id, product_id)
 warehouse_transfers      | ck_warehouse_transfers_distinct      | CHECK       | CHECK ((source_warehouse_id <> destination_warehouse_id))
 warehouse_transfers      | ck_warehouse_transfers_order_dates   | CHECK       | CHECK (((shipped_at IS NULL) OR (received_at IS NULL) OR (received_at >= shipped_at)))
 warehouse_transfers      | fk_warehouse_transfers_destination   | FOREIGN KEY | FOREIGN KEY (destination_warehouse_id) REFERENCES lab.warehouses(warehouse_id) ON DELETE RESTRICT
 warehouse_transfers      | pk_warehouse_transfers               | PRIMARY KEY | PRIMARY KEY (transfer_id)
 warehouse_transfers      | uq_warehouse_transfers_no            | UNIQUE      | UNIQUE (transfer_no)
 warehouses               | ck_warehouses_state                  | CHECK       | CHECK ((state ~ '^[A-Z]{2}$'::text))
 warehouses               | pk_warehouses                        | PRIMARY KEY | PRIMARY KEY (warehouse_id)
 warehouses               | uq_warehouses_city_name              | UNIQUE      | UNIQUE (city, warehouse_name)
 warehouses               | uq_warehouses_code                   | UNIQUE      | UNIQUE (warehouse_code)
```

Вывод запроса №2 — количество ограничений по видам:

```
 kind  | cnt
-------+-----
 CHECK  |   8
 FK     |   6
 PK     |   4
 UNIQUE |   3
```

## 7. Идемпотентность, изоляция и ограничения реализации

* Скрипт начинается с `CREATE SCHEMA IF NOT EXISTS lab` и семи отдельных `DROP TABLE IF EXISTS
  ... CASCADE` — по одному на каждый объект этой работы (`warehouse_transfer_items →
  warehouse_transfers → warehouse_inventory → warehouses`), плюс три «страховочных» DROP
  (`lab.inventory`, `lab.transfer_items`, `lab.transfers`) на случай таблиц с прежними именами.
  `CASCADE` снимает зависимости от объектов, которые могли остаться от других работ в схеме
  `lab`. Повторное выполнение (второй, третий запуск) проходит без ошибок.
* `warehouse_id` и `transfer_id` — `GENERATED BY DEFAULT AS IDENTITY`, счётчики начинаются
  заново после пересоздания таблицы; `transfer_no` хранится явно и стабилен между запусками.
* В схему `olist` ничего не записывается. Имена таблиц этой работы **префиксованы**
  (`warehouses`, `warehouse_inventory`, `warehouse_transfers`, `warehouse_transfer_items`), чтобы
  не пересекаться со «складскими» таблицами будущих практик. Фамильную таблицу `lab.inventory`
  из Практики 12 этот скрипт намеренно не создаёт; перед созданием своей схемы он, наоборот,
  удаляет постороннюю `lab.inventory`, если она осталась от другого варианта, — так повторный
  прогон не ломается ни в каком порядке.
* Декларативно проверены только **строчные** правила. Межстрочные правила (например, «сумма
  `qty` позиций не больше `qty_on_hand` у склада-источника» или «при получении остатки
  списываются с источника и начисляются на назначение») требуют триггера или транзакционной
  логики и в DDL этой работы осознанно не реализованы — это следующий шаг расширения.

## 8. Ответы на контрольные вопросы

1. **Когда связь M:N требует отдельной таблицы?** Когда обе стороны участвуют во многих
   экземплярах связи: одно перемещение содержит много товаров, а один товар участвует во многих
   перемещениях. Внешний ключ на стороне «N» такую связь выразить не может, поэтому нужна
   таблица-связка `transfer_items` с составным ключом `(transfer_id, product_id)`, в которую
   добавляются собственные атрибуты связи (`qty`, `note`).
2. **Чем естественный ключ отличается от surrogate key?** Естественный ключ взят из предметной
   области и несёт смысл (`warehouse_code`, `transfer_no`), но может измениться при исправлении
   данных. Surrogate key (`warehouse_id`, `transfer_id`) — искусственный, не меняется и
   дешевле для внешних ключей. В схеме используются оба: surrogate — `PRIMARY KEY`, естественный —
   альтернативный `UNIQUE`, который сохраняет уникальность бизнес-идентификатора.
3. **Какие ограничения лучше реализовывать декларативно, а не триггером?** Строчные локальные
   предикаты: `NOT NULL`, `UNIQUE`, `FOREIGN KEY`, `CHECK` на диапазоны и форматы. PostgreSQL
   проверяет их при любом способе записи (`INSERT`, `UPDATE`, `COPY`, параллельные транзакции),
   они видны в каталоге и не зависят от клиента. Триггеры оправданы только для межстрочных и
   межтабличных правил, где нужен доступ к другим строкам (см. раздел 7).
