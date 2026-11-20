-- =====================================================================
-- Olist Brazilian E-Commerce: Script 2 of 3, CLEAN AND MODEL
-- Run after script 1. Builds typed, keyed tables from the staging tables,
-- and records every data quality decision in a table called dq_log.
-- =====================================================================
USE olist;
SET SQL_SAFE_UPDATES = 0;

-- Clean slate so the script can be run again. Children are dropped before parents
-- because of the foreign keys added at the end.
DROP VIEW  IF EXISTS v_delivered_orders;
DROP VIEW  IF EXISTS v_order_revenue;
DROP TABLE IF EXISTS order_reviews;
DROP TABLE IF EXISTS order_payments;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS sellers;
DROP TABLE IF EXISTS customers;

DROP TABLE IF EXISTS dq_log;
CREATE TABLE dq_log (
  id INT AUTO_INCREMENT PRIMARY KEY,
  table_name VARCHAR(40), issue VARCHAR(120), rows_affected INT, action_taken VARCHAR(200)
);

-- ---------------------------------------------------------------------
-- CUSTOMERS
-- customer_id is one row per order. customer_unique_id is the real person.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
  customer_id CHAR(32) PRIMARY KEY,
  customer_unique_id CHAR(32) NOT NULL,
  zip_code_prefix VARCHAR(10),
  city VARCHAR(100),
  state CHAR(2)
);
INSERT INTO customers
SELECT customer_id, customer_unique_id, customer_zip_code_prefix,
       -- normalise city text: trim and lower-case so joins are consistent
       LOWER(TRIM(customer_city)), UPPER(TRIM(customer_state))
FROM stg_customers;

-- ---------------------------------------------------------------------
-- SELLERS
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS sellers;
CREATE TABLE sellers (
  seller_id CHAR(32) PRIMARY KEY,
  zip_code_prefix VARCHAR(10),
  city VARCHAR(100),
  state CHAR(2)
);
INSERT INTO sellers
SELECT seller_id, seller_zip_code_prefix, LOWER(TRIM(seller_city)), UPPER(TRIM(seller_state))
FROM stg_sellers;

-- ---------------------------------------------------------------------
-- PRODUCTS (+ English category names)
-- 610 products have no category. The two source columns are misspelled
-- as "lenght"; they are renamed here. Some categories are missing from the
-- translation file (counted in dq_log), so COALESCE keeps the Portuguese name in those cases.
-- ---------------------------------------------------------------------
INSERT INTO dq_log (table_name, issue, rows_affected, action_taken)
SELECT 'products', 'Missing product_category_name', COUNT(*), 'Category set to "unknown"'
FROM stg_products WHERE TRIM(product_category_name) = '';

DROP TABLE IF EXISTS products;
CREATE TABLE products (
  product_id CHAR(32) PRIMARY KEY,
  category VARCHAR(80),
  category_english VARCHAR(80),
  name_length INT,
  description_length INT,
  photos_qty INT,
  weight_g INT,
  length_cm INT,
  height_cm INT,
  width_cm INT
);
INSERT INTO products
SELECT p.product_id,
       CASE WHEN TRIM(p.product_category_name) = '' THEN 'unknown' ELSE p.product_category_name END,
       COALESCE(NULLIF(t.product_category_name_english, ''),
                CASE WHEN TRIM(p.product_category_name) = '' THEN 'unknown' ELSE p.product_category_name END),
       NULLIF(TRIM(p.product_name_lenght), ''),
       NULLIF(TRIM(p.product_description_lenght), ''),
       NULLIF(TRIM(p.product_photos_qty), ''),
       NULLIF(TRIM(p.product_weight_g), ''),
       NULLIF(TRIM(p.product_length_cm), ''),
       NULLIF(TRIM(p.product_height_cm), ''),
       NULLIF(TRIM(p.product_width_cm), '')
FROM stg_products p
LEFT JOIN stg_category_translation t
  ON TRIM(p.product_category_name) = TRIM(t.product_category_name);

-- ---------------------------------------------------------------------
-- ORDERS
-- Timestamps arrive as 'YYYY-MM-DD HH:MM:SS' text; blanks become NULL.
-- ---------------------------------------------------------------------
INSERT INTO dq_log (table_name, issue, rows_affected, action_taken)
SELECT 'orders', 'Delivered order missing delivered date', COUNT(*), 'Left NULL, excluded from delivery timing'
FROM stg_orders WHERE order_status = 'delivered' AND TRIM(order_delivered_customer_date) = '';

DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
  order_id CHAR(32) PRIMARY KEY,
  customer_id CHAR(32) NOT NULL,
  order_status VARCHAR(20),
  purchased_at   DATETIME,
  approved_at    DATETIME,
  delivered_carrier_at  DATETIME,
  delivered_customer_at DATETIME,
  estimated_delivery_at DATETIME
);
INSERT INTO orders
SELECT order_id, customer_id, order_status,
       CAST(NULLIF(TRIM(order_purchase_timestamp), '')      AS DATETIME),
       CAST(NULLIF(TRIM(order_approved_at), '')             AS DATETIME),
       CAST(NULLIF(TRIM(order_delivered_carrier_date), '')  AS DATETIME),
       CAST(NULLIF(TRIM(order_delivered_customer_date), '') AS DATETIME),
       CAST(NULLIF(TRIM(order_estimated_delivery_date), '') AS DATETIME)
FROM stg_orders;

-- ---------------------------------------------------------------------
-- ORDER ITEMS
-- price and freight are numeric; order_item_id is the line number.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items (
  order_id CHAR(32) NOT NULL,
  order_item_id INT NOT NULL,
  product_id CHAR(32),
  seller_id CHAR(32),
  shipping_limit_at DATETIME,
  price DECIMAL(10,2),
  freight_value DECIMAL(10,2),
  PRIMARY KEY (order_id, order_item_id)
);
INSERT INTO order_items
SELECT order_id, CAST(order_item_id AS UNSIGNED), product_id, seller_id,
       CAST(NULLIF(TRIM(shipping_limit_date), '') AS DATETIME),
       CAST(price AS DECIMAL(10,2)), CAST(freight_value AS DECIMAL(10,2))
FROM stg_order_items;

-- ---------------------------------------------------------------------
-- PAYMENTS
-- 3 rows have payment_type 'not_defined'; kept but flagged.
-- ---------------------------------------------------------------------
INSERT INTO dq_log (table_name, issue, rows_affected, action_taken)
SELECT 'order_payments', 'payment_type = not_defined', COUNT(*), 'Kept, flagged as unknown method'
FROM stg_order_payments WHERE payment_type = 'not_defined';

DROP TABLE IF EXISTS order_payments;
CREATE TABLE order_payments (
  order_id CHAR(32) NOT NULL,
  payment_sequential INT,
  payment_type VARCHAR(20),
  payment_installments INT,
  payment_value DECIMAL(10,2),
  PRIMARY KEY (order_id, payment_sequential)
);
INSERT INTO order_payments
SELECT order_id, CAST(payment_sequential AS UNSIGNED), payment_type,
       CAST(payment_installments AS UNSIGNED), CAST(payment_value AS DECIMAL(10,2))
FROM stg_order_payments;

-- ---------------------------------------------------------------------
-- REVIEWS
-- 814 review_ids and 551 orders appear more than once. For a clean
-- one-review-per-order table, keep the most recent answer per order.
-- ---------------------------------------------------------------------
INSERT INTO dq_log (table_name, issue, rows_affected, action_taken)
SELECT 'order_reviews', 'Orders with more than one review', COUNT(*) - COUNT(DISTINCT order_id),
       'Kept the most recent review per order'
FROM stg_order_reviews;

DROP TABLE IF EXISTS order_reviews;
CREATE TABLE order_reviews (
  order_id CHAR(32) PRIMARY KEY,
  review_id CHAR(32),
  review_score TINYINT,
  has_comment TINYINT,
  review_created_at DATETIME,
  review_answered_at DATETIME
);
INSERT INTO order_reviews
SELECT order_id, review_id, review_score, has_comment, review_created_at, review_answered_at
FROM (
  SELECT order_id, review_id,
         CAST(review_score AS UNSIGNED) AS review_score,
         CASE WHEN TRIM(review_comment_message) <> '' THEN 1 ELSE 0 END AS has_comment,
         CAST(NULLIF(TRIM(review_creation_date), '')   AS DATETIME) AS review_created_at,
         CAST(NULLIF(TRIM(review_answer_timestamp), '') AS DATETIME) AS review_answered_at,
         ROW_NUMBER() OVER (
           PARTITION BY order_id
           ORDER BY CAST(NULLIF(TRIM(review_answer_timestamp), '') AS DATETIME) DESC, review_id DESC
         ) AS rn
  FROM stg_order_reviews
) x
WHERE rn = 1;

-- Extra quality notes worth knowing before analysis
INSERT INTO dq_log (table_name, issue, rows_affected, action_taken)
SELECT 'products', 'Category with no English translation', COUNT(DISTINCT TRIM(p.product_category_name)),
       'Portuguese name kept as category_english'
FROM stg_products p
LEFT JOIN stg_category_translation t
  ON TRIM(p.product_category_name) = TRIM(t.product_category_name)
WHERE TRIM(p.product_category_name) <> '' AND t.product_category_name IS NULL;

INSERT INTO dq_log (table_name, issue, rows_affected, action_taken)
SELECT 'orders', 'Orders with no item lines', COUNT(*), 'Kept; they are mostly cancelled or unavailable'
FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id);

INSERT INTO dq_log (table_name, issue, rows_affected, action_taken)
SELECT 'customers', 'customer_id is per order, not per person', COUNT(*) - COUNT(DISTINCT customer_unique_id),
       'Use customer_unique_id for repeat-purchase analysis'
FROM customers;

-- ---------------------------------------------------------------------
-- KEYS AND INDEXES
-- ---------------------------------------------------------------------
ALTER TABLE orders       ADD CONSTRAINT fk_orders_cust   FOREIGN KEY (customer_id) REFERENCES customers(customer_id);
ALTER TABLE order_items  ADD CONSTRAINT fk_items_order   FOREIGN KEY (order_id)   REFERENCES orders(order_id);
ALTER TABLE order_items  ADD CONSTRAINT fk_items_product FOREIGN KEY (product_id) REFERENCES products(product_id);
ALTER TABLE order_items  ADD CONSTRAINT fk_items_seller  FOREIGN KEY (seller_id)  REFERENCES sellers(seller_id);
ALTER TABLE order_payments ADD CONSTRAINT fk_pay_order   FOREIGN KEY (order_id)   REFERENCES orders(order_id);
ALTER TABLE order_reviews  ADD CONSTRAINT fk_rev_order   FOREIGN KEY (order_id)   REFERENCES orders(order_id);
CREATE INDEX ix_orders_status ON orders(order_status);
CREATE INDEX ix_items_seller  ON order_items(seller_id);
CREATE INDEX ix_cust_unique   ON customers(customer_unique_id);

-- ---------------------------------------------------------------------
-- VIEWS
-- v_delivered_orders: one row per delivered order with timing and review,
--   the base for most analysis. "late" means delivered after the estimate.
-- v_order_revenue: item revenue (price) and freight per order.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_order_revenue;
CREATE VIEW v_order_revenue AS
SELECT order_id,
       SUM(price)         AS items_revenue,
       SUM(freight_value) AS freight,
       COUNT(*)           AS item_count
FROM order_items
GROUP BY order_id;

DROP VIEW IF EXISTS v_delivered_orders;
CREATE VIEW v_delivered_orders AS
SELECT o.order_id, o.customer_id, c.customer_unique_id, c.state AS customer_state,
       o.purchased_at, o.delivered_customer_at, o.estimated_delivery_at,
       DATEDIFF(o.delivered_customer_at, o.purchased_at)        AS ship_days,
       DATEDIFF(o.delivered_customer_at, o.estimated_delivery_at) AS delay_days,
       -- late = arrived on a later calendar day than promised. The estimate is stored at
       -- midnight, so comparing full timestamps would wrongly mark same-day deliveries late.
       CASE WHEN DATE(o.delivered_customer_at) > DATE(o.estimated_delivery_at) THEN 1 ELSE 0 END AS is_late,
       r.review_score,
       rev.items_revenue, rev.freight
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
LEFT JOIN order_reviews r ON r.order_id = o.order_id
LEFT JOIN v_order_revenue rev ON rev.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.delivered_customer_at IS NOT NULL
  AND o.estimated_delivery_at IS NOT NULL
  AND o.purchased_at IS NOT NULL;

-- ---------------------------------------------------------------------
-- CHECKS
-- ---------------------------------------------------------------------
SELECT 'customers' AS tbl, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews (deduped)', COUNT(*) FROM order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'v_delivered_orders', COUNT(*) FROM v_delivered_orders;

SELECT * FROM dq_log ORDER BY id;
