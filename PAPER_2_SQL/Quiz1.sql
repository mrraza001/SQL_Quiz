-- Task 1 — Build the Sales Detail Dataset

SELECT
    o.order_id,
    o.order_date,
    c.first_name + ' ' + c.last_name AS customer_full_name,
    st.store_name,
    sf.first_name + ' ' + sf.last_name AS staff_full_name,
    p.product_name,
    cat.category_name,
    b.brand_name,
    oi.quantity,
    oi.list_price,
    oi.discount,
    (oi.quantity * oi.list_price * (1 - oi.discount)) AS net_line_revenue
FROM sales.orders o
INNER JOIN sales.customers c ON o.customer_id = c.customer_id
INNER JOIN sales.stores st ON o.store_id = st.store_id
INNER JOIN sales.staffs sf ON o.staff_id = sf.staff_id
INNER JOIN sales.order_items oi ON o.order_id = oi.order_id
INNER JOIN production.products p ON oi.product_id = p.product_id
INNER JOIN production.categories cat ON p.category_id = cat.category_id
INNER JOIN production.brands b ON p.brand_id = b.brand_id
WHERE o.order_status = 4
ORDER BY o.order_date DESC;


-- Task 2 — Store Performance Summary

SELECT
    st.store_name,
    COUNT(DISTINCT o.order_id) AS number_of_distinct_orders,
    SUM(oi.quantity) AS total_units_sold,
    SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_net_revenue,
    SUM(oi.quantity * oi.list_price * (1 - oi.discount)) 
        / COUNT(DISTINCT o.order_id) AS average_order_value
FROM sales.stores st
INNER JOIN sales.orders o ON st.store_id = o.store_id
INNER JOIN sales.order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 4
GROUP BY st.store_name
ORDER BY total_net_revenue DESC;


-- Task 3 — High-Value Customers

WITH customer_spending AS (
    SELECT
        c.customer_id,
        c.first_name + ' ' + c.last_name AS customer_name,
        COUNT(DISTINCT o.order_id) AS completed_order_count,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_spending
    FROM sales.customers c
    INNER JOIN sales.orders o ON c.customer_id = o.customer_id
    INNER JOIN sales.order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 4
    GROUP BY c.customer_id, c.first_name, c.last_name
),
avg_spending AS (
    SELECT AVG(total_spending) AS avg_total
    FROM customer_spending
)
SELECT
    cs.customer_id,
    cs.customer_name,
    cs.completed_order_count,
    cs.total_spending
FROM customer_spending cs
CROSS JOIN avg_spending a
WHERE cs.total_spending > a.avg_total
ORDER BY cs.total_spending DESC;


-- Task 4 — Inventory Risk Report

SELECT
    p.product_name,
    st.store_name,
    s.quantity AS current_quantity,
    cat.category_name,
    b.brand_name
FROM production.stocks s
INNER JOIN production.products p ON s.product_id = p.product_id
INNER JOIN sales.stores st ON s.store_id = st.store_id
INNER JOIN production.categories cat ON p.category_id = cat.category_id
INNER JOIN production.brands b ON p.brand_id = b.brand_id
WHERE s.quantity < 5
ORDER BY s.quantity ASC, p.product_name ASC;


-- Task 5 — Top Products Within Each Category

WITH product_revenue AS (
    SELECT
        cat.category_name,
        p.product_name,
        SUM(oi.quantity) AS total_units_sold,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_net_revenue
    FROM sales.orders o
    INNER JOIN sales.order_items oi ON o.order_id = oi.order_id
    INNER JOIN production.products p ON oi.product_id = p.product_id
    INNER JOIN production.categories cat ON p.category_id = cat.category_id
    WHERE o.order_status = 4
    GROUP BY cat.category_name, p.product_name
),
ranked AS (
    SELECT
        category_name,
        product_name,
        total_units_sold,
        total_net_revenue,
        DENSE_RANK() OVER (PARTITION BY category_name ORDER BY total_net_revenue DESC) AS position_in_category
    FROM product_revenue
)
SELECT
    category_name,
    product_name,
    total_units_sold,
    total_net_revenue,
    position_in_category
FROM ranked
WHERE position_in_category <= 3
ORDER BY category_name, position_in_category;


-- Task 6 — Monthly Sales Trend

WITH monthly_revenue AS (
    SELECT
        YEAR(o.order_date) AS year,
        MONTH(o.order_date) AS month,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_net_revenue
    FROM sales.orders o
    INNER JOIN sales.order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 4
    GROUP BY YEAR(o.order_date), MONTH(o.order_date)
)
SELECT
    year,
    month,
    total_net_revenue,
    LAG(total_net_revenue) OVER (ORDER BY year, month) AS previous_month_revenue,
    total_net_revenue - LAG(total_net_revenue) OVER (ORDER BY year, month) AS revenue_change
FROM monthly_revenue
ORDER BY year, month;


-- Task 7 — Reusable Reporting View

CREATE VIEW sales.vw_customer_sales_summary AS
SELECT
    c.customer_id,
    c.first_name + ' ' + c.last_name AS customer_full_name,
    COUNT(DISTINCT o.order_id) AS total_completed_orders,
    ISNULL(SUM(oi.quantity), 0) AS total_units_purchased,
    ISNULL(SUM(oi.quantity * oi.list_price * (1 - oi.discount)), 0) AS total_net_revenue,
    MAX(o.order_date) AS most_recent_completed_order_date
FROM sales.customers c
LEFT JOIN sales.orders o ON c.customer_id = o.customer_id AND o.order_status = 4
LEFT JOIN sales.order_items oi ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.first_name, c.last_name;


-- Task 8 — Safe Data Modification

BEGIN TRANSACTION;

UPDATE sales.customers
SET phone = '(999) 555-0101'
WHERE customer_id = 1;

SELECT customer_id, first_name, last_name, phone
FROM sales.customers
WHERE customer_id = 1;

ROLLBACK TRANSACTION;


-- Task 9 — Store Sales Procedure

CREATE PROCEDURE sales.usp_store_sales_report
    @store_id INT,
    @start_date DATE,
    @end_date DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @start_date > @end_date
    BEGIN
        RAISERROR('Invalid date range: @start_date cannot be later than @end_date.', 16, 1);
        RETURN;
    END

    SELECT
        p.product_name,
        SUM(oi.quantity) AS total_units_sold,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_net_revenue
    FROM sales.orders o
    INNER JOIN sales.order_items oi ON o.order_id = oi.order_id
    INNER JOIN production.products p ON oi.product_id = p.product_id
    WHERE o.store_id = @store_id
      AND o.order_status = 4
      AND o.order_date BETWEEN @start_date AND @end_date
    GROUP BY p.product_name
    ORDER BY total_net_revenue DESC;
END;


-- Task 10 — Management Insight Query

SELECT
    sf.staff_id,
    sf.first_name + ' ' + sf.last_name AS staff_full_name,
    st.store_name,
    COUNT(DISTINCT o.customer_id) AS distinct_customers_served,
    COUNT(DISTINCT o.order_id) AS completed_orders,
    SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_net_revenue
FROM sales.staffs sf
INNER JOIN sales.stores st ON sf.store_id = st.store_id
INNER JOIN sales.orders o ON sf.staff_id = o.staff_id
INNER JOIN sales.order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 4
GROUP BY sf.staff_id, sf.first_name, sf.last_name, st.store_name
ORDER BY total_net_revenue DESC;