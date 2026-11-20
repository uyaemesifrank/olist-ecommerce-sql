-- =====================================================================
-- Olist Brazilian E-Commerce: Script 1 of 3, CREATE DATABASE AND LOAD RAW DATA
-- Target: MySQL 8.0 in MySQL Workbench 8.0 CE
--
-- BEFORE YOU RUN:
-- 1. Unzip olist_Kaggle_dataset.zip into a folder with a SIMPLE path, e.g. D:/olist/
--    (use forward slashes; no spaces if you can avoid them).
-- 2. Edit > Find and Replace in this script: replace  D:/olist/  with your folder path.
-- 3. Allow local file loading. In Workbench: Database > Manage Connections > select your
--    connection > Advanced tab > in "Others" type  OPT_LOCAL_INFILE=1  > Close, then
--    reconnect. The next statement turns the server side on (needs an admin login such as root).
-- 4. Run the whole script (lightning bolt). Loading about 126 MB takes 1 to 3 minutes.
--
-- Every column is loaded as text so no row is ever rejected. Script 2 converts the types.
-- =====================================================================
SET GLOBAL local_infile = 1;
SET SQL_SAFE_UPDATES = 0;

DROP DATABASE IF EXISTS olist;
CREATE DATABASE olist CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE olist;

CREATE TABLE stg_customers (
  customer_id VARCHAR(40), customer_unique_id VARCHAR(40),
  customer_zip_code_prefix VARCHAR(10), customer_city VARCHAR(100), customer_state VARCHAR(10)
);
CREATE TABLE stg_orders (
  order_id VARCHAR(40), customer_id VARCHAR(40), order_status VARCHAR(20),
  order_purchase_timestamp VARCHAR(30), order_approved_at VARCHAR(30),
  order_delivered_carrier_date VARCHAR(30), order_delivered_customer_date VARCHAR(30),
  order_estimated_delivery_date VARCHAR(30)
);
CREATE TABLE stg_order_items (
  order_id VARCHAR(40), order_item_id VARCHAR(10), product_id VARCHAR(40), seller_id VARCHAR(40),
  shipping_limit_date VARCHAR(30), price VARCHAR(20), freight_value VARCHAR(20)
);
CREATE TABLE stg_order_payments (
  order_id VARCHAR(40), payment_sequential VARCHAR(10), payment_type VARCHAR(20),
  payment_installments VARCHAR(10), payment_value VARCHAR(20)
);
CREATE TABLE stg_order_reviews (
  review_id VARCHAR(40), order_id VARCHAR(40), review_score VARCHAR(5),
  review_comment_title TEXT, review_comment_message TEXT,
  review_creation_date VARCHAR(30), review_answer_timestamp VARCHAR(30)
);
CREATE TABLE stg_products (
  product_id VARCHAR(40), product_category_name VARCHAR(80),
  product_name_lenght VARCHAR(10), product_description_lenght VARCHAR(10), product_photos_qty VARCHAR(10),
  product_weight_g VARCHAR(10), product_length_cm VARCHAR(10), product_height_cm VARCHAR(10),
  product_width_cm VARCHAR(10)
);
CREATE TABLE stg_sellers (
  seller_id VARCHAR(40), seller_zip_code_prefix VARCHAR(10), seller_city VARCHAR(100), seller_state VARCHAR(10)
);
CREATE TABLE stg_geolocation (
  geolocation_zip_code_prefix VARCHAR(10), geolocation_lat VARCHAR(30), geolocation_lng VARCHAR(30),
  geolocation_city VARCHAR(100), geolocation_state VARCHAR(10)
);
CREATE TABLE stg_category_translation (
  product_category_name VARCHAR(80), product_category_name_english VARCHAR(80)
);

-- ESCAPED BY '' is important: the review comments contain backslashes and line breaks.
-- Without it, the default backslash-escaping merges one review row into another.
-- The CSV files wrap every value in double quotes, so ENCLOSED BY is required.
-- Review comments contain line breaks inside quotes; ENCLOSED BY handles those too.
LOAD DATA LOCAL INFILE 'D:/olist/olist_customers_dataset.csv' INTO TABLE stg_customers
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES;
LOAD DATA LOCAL INFILE 'D:/olist/olist_orders_dataset.csv' INTO TABLE stg_orders
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES;
LOAD DATA LOCAL INFILE 'D:/olist/olist_order_items_dataset.csv' INTO TABLE stg_order_items
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES;
LOAD DATA LOCAL INFILE 'D:/olist/olist_order_payments_dataset.csv' INTO TABLE stg_order_payments
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES;
LOAD DATA LOCAL INFILE 'D:/olist/olist_order_reviews_dataset.csv' INTO TABLE stg_order_reviews
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES;
LOAD DATA LOCAL INFILE 'D:/olist/olist_products_dataset.csv' INTO TABLE stg_products
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES;
LOAD DATA LOCAL INFILE 'D:/olist/olist_sellers_dataset.csv' INTO TABLE stg_sellers
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES;
LOAD DATA LOCAL INFILE 'D:/olist/olist_geolocation_dataset.csv' INTO TABLE stg_geolocation
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES;
-- This file starts with an invisible BOM character; skipping the header line removes it.
LOAD DATA LOCAL INFILE 'D:/olist/product_category_name_translation.csv' INTO TABLE stg_category_translation
  CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '' LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- Check: row counts must match the expected column exactly.
SELECT 'stg_customers' AS tbl, COUNT(*) AS rows_loaded, 99441 AS expected FROM stg_customers
UNION ALL SELECT 'stg_orders',            COUNT(*),  99441 FROM stg_orders
UNION ALL SELECT 'stg_order_items',       COUNT(*), 112650 FROM stg_order_items
UNION ALL SELECT 'stg_order_payments',    COUNT(*), 103886 FROM stg_order_payments
UNION ALL SELECT 'stg_order_reviews',     COUNT(*),  99224 FROM stg_order_reviews
UNION ALL SELECT 'stg_products',          COUNT(*),  32951 FROM stg_products
UNION ALL SELECT 'stg_sellers',           COUNT(*),   3095 FROM stg_sellers
UNION ALL SELECT 'stg_geolocation',       COUNT(*), 1000163 FROM stg_geolocation
UNION ALL SELECT 'stg_category_translation', COUNT(*), 71 FROM stg_category_translation;
