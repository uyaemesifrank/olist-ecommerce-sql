-- =====================================================================
-- Olist Brazilian E-Commerce: Script 3 of 3, BUSINESS QUESTIONS
-- Run after script 2. In Workbench, put the cursor inside one query and
-- press Ctrl+Enter to run just that query.
--
-- Scope: delivered orders with a valid delivery date (96,470 orders).
-- "Late" means the order arrived after Olist's estimated delivery date.
-- Revenue = sum of item prices (freight shown separately).
-- =====================================================================
USE olist;

-- ---------------------------------------------------------------------
-- Q1. The headline: does late delivery hurt reviews?
-- ---------------------------------------------------------------------
SELECT CASE WHEN is_late = 1 THEN 'Late' ELSE 'On time or early' END AS delivery,
       COUNT(*)                                        AS orders,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders,
       ROUND(AVG(review_score), 2)                     AS avg_review,
       ROUND(100 * AVG(review_score = 1), 1)           AS one_star_pct,
       ROUND(100 * AVG(review_score = 5), 1)           AS five_star_pct
FROM v_delivered_orders
WHERE review_score IS NOT NULL
GROUP BY is_late
ORDER BY is_late;

-- Q1b. How much does each extra week of lateness cost in stars?
SELECT CASE WHEN delay_days < 0   THEN '1 Early'
            WHEN delay_days = 0   THEN '2 On the day'
            WHEN delay_days <= 3  THEN '3 1 to 3 days late'
            WHEN delay_days <= 7  THEN '4 4 to 7 days late'
            WHEN delay_days <= 15 THEN '5 8 to 15 days late'
            ELSE                       '6 Over 15 days late' END AS delivery_bucket,
       COUNT(*)                              AS orders,
       ROUND(AVG(review_score), 2)           AS avg_review,
       ROUND(100 * AVG(review_score = 1), 1) AS one_star_pct
FROM v_delivered_orders
WHERE review_score IS NOT NULL
GROUP BY delivery_bucket
ORDER BY delivery_bucket;

-- ---------------------------------------------------------------------
-- Q2. Where is delivery slow and late? (customer state)
-- ---------------------------------------------------------------------
SELECT customer_state,
       COUNT(*)                                AS orders,
       ROUND(AVG(ship_days), 1)                AS avg_days_to_deliver,
       ROUND(100 * AVG(is_late), 1)            AS late_pct,
       ROUND(AVG(review_score), 2)             AS avg_review,
       ROUND(AVG(freight), 2)                  AS avg_freight_brl
FROM v_delivered_orders
GROUP BY customer_state
HAVING COUNT(*) >= 300
ORDER BY late_pct DESC;

-- ---------------------------------------------------------------------
-- Q3. Is the problem the seller or the courier?
-- Seller handling time = purchase to carrier pickup.
-- Transit time = carrier pickup to customer delivery.
-- ---------------------------------------------------------------------
SELECT CASE WHEN DATE(o.delivered_customer_at) > DATE(o.estimated_delivery_at) THEN 'Late' ELSE 'On time' END AS delivery,
       COUNT(*) AS orders,
       ROUND(AVG(DATEDIFF(o.delivered_carrier_at, o.purchased_at)), 1)         AS avg_seller_handling_days,
       ROUND(AVG(DATEDIFF(o.delivered_customer_at, o.delivered_carrier_at)), 1) AS avg_transit_days,
       ROUND(AVG(DATEDIFF(o.estimated_delivery_at, o.purchased_at)), 1)        AS avg_promised_days
FROM orders o
WHERE o.order_status = 'delivered'
  AND o.delivered_customer_at IS NOT NULL AND o.delivered_carrier_at IS NOT NULL
GROUP BY delivery
ORDER BY delivery;

-- ---------------------------------------------------------------------
-- Q4. Which sellers are letting the platform down?
-- Sellers with at least 100 delivered orders, ranked by late rate.
-- ---------------------------------------------------------------------
-- Revenue is summed from the seller's own item lines, so multi-seller orders
-- do not credit one seller with another seller's items.
WITH seller_orders AS (
  SELECT seller_id, order_id, SUM(price) AS seller_revenue
  FROM order_items
  GROUP BY seller_id, order_id
)
SELECT s.seller_id, s.state AS seller_state,
       COUNT(*)                                 AS delivered_orders,
       ROUND(100 * AVG(d.is_late), 1)           AS late_pct,
       ROUND(AVG(d.review_score), 2)            AS avg_review,
       ROUND(SUM(so.seller_revenue), 0)         AS revenue_brl
FROM seller_orders so
JOIN v_delivered_orders d ON d.order_id  = so.order_id
JOIN sellers s            ON s.seller_id = so.seller_id
GROUP BY s.seller_id, s.state
HAVING COUNT(*) >= 100
ORDER BY late_pct DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- Q5. Which product categories earn the most, and do they review well?
-- ---------------------------------------------------------------------
SELECT p.category_english                         AS category,
       COUNT(DISTINCT i.order_id)                 AS orders,
       ROUND(SUM(i.price), 0)                     AS revenue_brl,
       ROUND(100 * SUM(i.price) / SUM(SUM(i.price)) OVER (), 1) AS revenue_share_pct,
       ROUND(AVG(i.price), 2)                     AS avg_item_price,
       ROUND(AVG(d.review_score), 2)              AS avg_review
FROM order_items i
JOIN products p ON p.product_id = i.product_id
JOIN v_delivered_orders d ON d.order_id = i.order_id
GROUP BY p.category_english
ORDER BY revenue_brl DESC
LIMIT 10;

-- ---------------------------------------------------------------------
-- Q6. Monthly revenue trend with month-on-month growth (window function)
-- ---------------------------------------------------------------------
WITH monthly AS (
  SELECT DATE_FORMAT(purchased_at, '%Y-%m') AS ym,
         COUNT(*)            AS orders,
         SUM(items_revenue)  AS revenue
  FROM v_delivered_orders
  GROUP BY DATE_FORMAT(purchased_at, '%Y-%m')
)
SELECT ym, orders, ROUND(revenue, 0) AS revenue_brl,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY ym)) / LAG(revenue) OVER (ORDER BY ym), 1) AS mom_growth_pct
FROM monthly
WHERE ym BETWEEN '2017-01' AND '2018-08'   -- full months only; Sep 2016 and Sep/Oct 2018 are partial
ORDER BY ym;

-- ---------------------------------------------------------------------
-- Q7. How do customers pay, and does instalment buying mean bigger orders?
-- ---------------------------------------------------------------------
SELECT payment_type,
       COUNT(DISTINCT order_id)                       AS orders,
       ROUND(100 * COUNT(DISTINCT order_id) / SUM(COUNT(DISTINCT order_id)) OVER (), 1) AS pct_of_orders,
       ROUND(AVG(payment_value), 2)                   AS avg_payment_brl,
       ROUND(AVG(payment_installments), 1)            AS avg_installments,
       ROUND(100 * AVG(payment_installments > 1), 1)  AS pct_paid_in_installments
FROM order_payments
WHERE payment_type <> 'not_defined'
GROUP BY payment_type
ORDER BY orders DESC;

-- Q7b. Do instalments mean bigger orders? (credit card orders, one row per order)
WITH pay AS (
  SELECT order_id, MAX(payment_installments) AS installments, SUM(payment_value) AS order_value
  FROM order_payments
  WHERE payment_type = 'credit_card'
  GROUP BY order_id
)
SELECT CASE WHEN installments <= 1 THEN '1 (upfront)'
            WHEN installments <= 3 THEN '2 to 3'
            WHEN installments <= 6 THEN '4 to 6'
            ELSE '7 or more' END AS installment_bucket,
       COUNT(*) AS orders,
       ROUND(AVG(order_value), 2) AS avg_order_brl
FROM pay
GROUP BY installment_bucket
ORDER BY MIN(installments);

-- ---------------------------------------------------------------------
-- Q8. Do customers come back? (repeat purchase, using the real person id)
-- ---------------------------------------------------------------------
WITH per_person AS (
  SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS orders
  FROM orders o
  JOIN customers c ON c.customer_id = o.customer_id
  WHERE o.order_status = 'delivered'
  GROUP BY c.customer_unique_id
)
SELECT CASE WHEN orders = 1 THEN '1 order'
            WHEN orders = 2 THEN '2 orders'
            ELSE '3 or more' END                    AS purchase_frequency,
       COUNT(*)                                     AS customers,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_customers
FROM per_person
GROUP BY purchase_frequency
ORDER BY purchase_frequency;

-- Q8b. Does a bad first experience stop people coming back?
-- Only first orders placed before July 2017 are counted, so every customer had at
-- least about a year to return. Without this, recent customers look less loyal.
-- This shows a link, not proof of cause.
WITH first_orders AS (
  SELECT d.customer_unique_id, d.order_id, d.is_late, d.review_score, d.purchased_at,
         ROW_NUMBER() OVER (PARTITION BY d.customer_unique_id ORDER BY d.purchased_at, d.order_id) AS rn,
         COUNT(*)     OVER (PARTITION BY d.customer_unique_id)                         AS total_orders
  FROM v_delivered_orders d
)
SELECT CASE WHEN is_late = 1 THEN 'First order late' ELSE 'First order on time' END AS first_experience,
       COUNT(*)                                       AS customers,
       ROUND(100 * AVG(total_orders > 1), 2)          AS came_back_pct
FROM first_orders
WHERE rn = 1 AND purchased_at < '2017-07-01'
GROUP BY is_late
ORDER BY is_late;

-- ---------------------------------------------------------------------
-- Q9. Freight as a share of what the customer pays, by state
-- High freight share in the North and North-East is a known pain point.
-- ---------------------------------------------------------------------
SELECT customer_state,
       COUNT(*)                                                     AS orders,
       ROUND(AVG(items_revenue), 2)                                 AS avg_items_brl,
       ROUND(AVG(freight), 2)                                       AS avg_freight_brl,
       ROUND(100 * SUM(COALESCE(freight, 0)) / SUM(COALESCE(items_revenue, 0) + COALESCE(freight, 0)), 1)  AS freight_share_pct
FROM v_delivered_orders
GROUP BY customer_state
HAVING COUNT(*) >= 300
ORDER BY freight_share_pct DESC;
