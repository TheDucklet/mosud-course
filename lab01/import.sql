-- Импорт CSV Olist
COPY olist.customers FROM '/data/olist/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY olist.geolocation FROM '/data/olist/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY olist.orders FROM '/data/olist/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY olist.order_items FROM '/data/olist/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY olist.order_payments FROM '/data/olist/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY olist.order_reviews FROM '/data/olist/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY olist.products FROM '/data/olist/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY olist.sellers FROM '/data/olist/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
COPY olist.product_category_name_translation FROM '/data/olist/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');