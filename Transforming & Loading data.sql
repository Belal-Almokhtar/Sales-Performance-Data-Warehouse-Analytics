USE SalesDWH;
GO

-- ============================================================
-- dim_date
-- ============================================================
IF OBJECT_ID('dim_date','U') IS NOT NULL DROP TABLE dim_date;

CREATE TABLE dim_date (
    date_id     INT          NOT NULL PRIMARY KEY,
    full_date   DATE         NOT NULL,
    day_name    NVARCHAR(10),
    day_num     TINYINT,
    month_num   TINYINT,
    month_name  NVARCHAR(10),
    quarter     TINYINT,
    year        SMALLINT,
    is_weekend  BIT
);

WITH all_dates AS (
    SELECT TRY_CONVERT(DATE, sale_date, 23)  AS d FROM sales_raw_data
    UNION
    SELECT TRY_CONVERT(DATE, sale_date, 105) AS d FROM sales_raw_data
    UNION
    SELECT TRY_CONVERT(DATE, sale_date, 101) AS d FROM sales_raw_data
)
INSERT INTO dim_date
SELECT
    CONVERT(INT, FORMAT(d, 'yyyyMMdd'))                             AS date_id,
    d                                                               AS full_date,
    DATENAME(WEEKDAY, d)                                            AS day_name,
    DAY(d)                                                          AS day_num,
    MONTH(d)                                                        AS month_num,
    DATENAME(MONTH, d)                                              AS month_name,
    DATEPART(QUARTER, d)                                            AS quarter,
    YEAR(d)                                                         AS year,
    CASE WHEN DATEPART(WEEKDAY, d) IN (1,7) THEN 1 ELSE 0 END      AS is_weekend
FROM all_dates
WHERE d IS NOT NULL;
GO

-- ============================================================
-- dim_customer
-- ============================================================
IF OBJECT_ID('dim_customer','U') IS NOT NULL DROP TABLE dim_customer;

CREATE TABLE dim_customer (
    customer_id     NVARCHAR(10)    NOT NULL PRIMARY KEY,
    customer_name   NVARCHAR(100),
    age             TINYINT,
    age_group       NVARCHAR(20),
    gender          NVARCHAR(10),
    city            NVARCHAR(50),
    loyalty_level   NVARCHAR(20)
);

INSERT INTO dim_customer
SELECT
    customer_id,
    MAX(customer_name) AS customer_name,

    MAX(CASE
        WHEN TRY_CAST(customer_age AS INT) BETWEEN 18 AND 80
        THEN TRY_CAST(customer_age AS TINYINT)
        ELSE NULL
    END) AS age,

    MAX(CASE
        WHEN TRY_CAST(customer_age AS INT) BETWEEN 18 AND 25 THEN '18-25'
        WHEN TRY_CAST(customer_age AS INT) BETWEEN 26 AND 35 THEN '26-35'
        WHEN TRY_CAST(customer_age AS INT) BETWEEN 36 AND 50 THEN '36-50'
        WHEN TRY_CAST(customer_age AS INT) BETWEEN 51 AND 80 THEN '51-80'
        ELSE 'Unknown'
    END) AS age_group,

    MAX(CASE
        WHEN UPPER(TRIM(customer_gender)) IN ('MALE','M','MAN')               THEN 'Male'
        WHEN UPPER(TRIM(customer_gender)) IN ('FEMALE','F','WOMAN','FEMALE ')  THEN 'Female'
        ELSE 'Unknown'
    END) AS gender,

    MAX(CASE
        WHEN UPPER(TRIM(customer_city)) IN ('CAIRO','AL CAIRO','EL CAIRO')    THEN 'Cairo'
        WHEN UPPER(TRIM(customer_city)) LIKE '%ALEX%'                          THEN 'Alexandria'
        WHEN UPPER(TRIM(customer_city)) IN ('GIZA','AL GIZA')                  THEN 'Giza'
        ELSE TRIM(customer_city)
    END) AS city,

    MAX(CASE
        WHEN UPPER(TRIM(loyalty_level)) IN ('BRONZE','BONZE')                 THEN 'Bronze'
        WHEN UPPER(TRIM(loyalty_level)) IN ('SILVER','SLIVER')                THEN 'Silver'
        WHEN UPPER(TRIM(loyalty_level)) LIKE 'GOLD%'                          THEN 'Gold'
        WHEN UPPER(TRIM(loyalty_level)) IN ('PLATINUM','PLATINIUM')           THEN 'Platinum'
        ELSE 'Unknown'
    END) AS loyalty_level

FROM sales_raw_data
WHERE customer_id IS NOT NULL
GROUP BY customer_id;
GO

-- ============================================================
-- dim_product (SCD Type 2)
-- ============================================================
IF OBJECT_ID('dim_product','U') IS NOT NULL DROP TABLE dim_product;

CREATE TABLE dim_product (
    product_sk      INT IDENTITY(1,1)   NOT NULL PRIMARY KEY,
    product_id      NVARCHAR(10)        NOT NULL,
    product_name    NVARCHAR(150),
    category        NVARCHAR(50),
    unit_price      DECIMAL(10,2),
    scd_start_date  DATE                NOT NULL,
    scd_end_date    DATE,
    is_current      BIT                 DEFAULT 1
);

WITH base AS (
    SELECT
        product_id,
        MAX(product_name) AS product_name,
        CASE
            WHEN UPPER(TRIM(category)) IN ('ELECTRONICS','ELECTRONIICS')                        THEN 'Electronics'
            WHEN UPPER(TRIM(category)) IN ('CLOTHING','CLOTHES')                                THEN 'Clothing'
            WHEN UPPER(TRIM(category)) IN ('FOOD & BEVERAGES','FOOD AND BEVERAGES','F&B')       THEN 'Food & Beverages'
            WHEN UPPER(TRIM(category)) IN ('HOME APPLIANCES','HOME APPLIANCE','HOMEAPPLIANCES') THEN 'Home Appliances'
            WHEN UPPER(TRIM(category)) IN ('SPORTS','SPORT')                                    THEN 'Sports'
            WHEN UPPER(TRIM(category)) IN ('BEAUTY & HEALTH','BEAUTY AND HEALTH','B&H')         THEN 'Beauty & Health'
            ELSE TRIM(category)
        END AS category,
        TRY_CAST(unit_price AS DECIMAL(10,2)) AS unit_price,
        MIN(COALESCE(
            TRY_CONVERT(DATE, sale_date, 23),
            TRY_CONVERT(DATE, sale_date, 105),
            TRY_CONVERT(DATE, sale_date, 101)
        )) AS scd_start_date
    FROM sales_raw_data
    WHERE product_id IS NOT NULL
      AND TRY_CAST(unit_price AS DECIMAL(10,2)) IS NOT NULL
    GROUP BY
        product_id,
        CASE
            WHEN UPPER(TRIM(category)) IN ('ELECTRONICS','ELECTRONIICS')                        THEN 'Electronics'
            WHEN UPPER(TRIM(category)) IN ('CLOTHING','CLOTHES')                                THEN 'Clothing'
            WHEN UPPER(TRIM(category)) IN ('FOOD & BEVERAGES','FOOD AND BEVERAGES','F&B')       THEN 'Food & Beverages'
            WHEN UPPER(TRIM(category)) IN ('HOME APPLIANCES','HOME APPLIANCE','HOMEAPPLIANCES') THEN 'Home Appliances'
            WHEN UPPER(TRIM(category)) IN ('SPORTS','SPORT')                                    THEN 'Sports'
            WHEN UPPER(TRIM(category)) IN ('BEAUTY & HEALTH','BEAUTY AND HEALTH','B&H')         THEN 'Beauty & Health'
            ELSE TRIM(category)
        END,
        TRY_CAST(unit_price AS DECIMAL(10,2))
),
versioned AS (
    SELECT *,
        LEAD(scd_start_date) OVER (
            PARTITION BY product_id
            ORDER BY scd_start_date
        ) AS next_start
    FROM base
)
INSERT INTO dim_product
SELECT
    product_id,
    product_name,
    category,
    unit_price,
    scd_start_date,
    CASE WHEN next_start IS NOT NULL
         THEN DATEADD(DAY, -1, next_start)
         ELSE NULL
    END AS scd_end_date,
    CASE WHEN next_start IS NULL THEN 1 ELSE 0 END AS is_current
FROM versioned;
GO

-- ============================================================
-- dim_branch (SCD Type 2)
-- ============================================================
IF OBJECT_ID('dim_branch','U') IS NOT NULL DROP TABLE dim_branch;

CREATE TABLE dim_branch (
    branch_sk       INT IDENTITY(1,1)   NOT NULL PRIMARY KEY,
    branch_id       NVARCHAR(10)        NOT NULL,
    branch_name     NVARCHAR(100),
    city            NVARCHAR(50),
    branch_manager  NVARCHAR(100),
    scd_start_date  DATE                NOT NULL,
    scd_end_date    DATE,
    is_current      BIT                 DEFAULT 1
);

WITH base AS (
    SELECT
        branch_id,
        MAX(branch_name) AS branch_name,
        CASE
            WHEN UPPER(TRIM(city)) IN ('CAIRO','AL CAIRO','EL CAIRO')  THEN 'Cairo'
            WHEN UPPER(TRIM(city)) LIKE '%ALEX%'                        THEN 'Alexandria'
            WHEN UPPER(TRIM(city)) IN ('GIZA','AL GIZA')                THEN 'Giza'
            ELSE TRIM(city)
        END AS city,
        TRIM(branch_manager) AS branch_manager,
        MIN(COALESCE(
            TRY_CONVERT(DATE, sale_date, 23),
            TRY_CONVERT(DATE, sale_date, 105),
            TRY_CONVERT(DATE, sale_date, 101)
        )) AS scd_start_date
    FROM sales_raw_data
    WHERE branch_id      IS NOT NULL
      AND branch_manager IS NOT NULL
    GROUP BY
        branch_id,
        CASE
            WHEN UPPER(TRIM(city)) IN ('CAIRO','AL CAIRO','EL CAIRO')  THEN 'Cairo'
            WHEN UPPER(TRIM(city)) LIKE '%ALEX%'                        THEN 'Alexandria'
            WHEN UPPER(TRIM(city)) IN ('GIZA','AL GIZA')                THEN 'Giza'
            ELSE TRIM(city)
        END,
        TRIM(branch_manager)
),
versioned AS (
    SELECT *,
        LEAD(scd_start_date) OVER (
            PARTITION BY branch_id
            ORDER BY scd_start_date
        ) AS next_start
    FROM base
)
INSERT INTO dim_branch
SELECT
    branch_id,
    branch_name,
    city,
    branch_manager,
    scd_start_date,
    CASE WHEN next_start IS NOT NULL
         THEN DATEADD(DAY, -1, next_start)
         ELSE NULL
    END AS scd_end_date,
    CASE WHEN next_start IS NULL THEN 1 ELSE 0 END AS is_current
FROM versioned;
GO

-- ============================================================
-- dim_supplier
-- ============================================================
IF OBJECT_ID('dim_supplier','U') IS NOT NULL DROP TABLE dim_supplier;

CREATE TABLE dim_supplier (
    supplier_id         NVARCHAR(10)    NOT NULL PRIMARY KEY,
    supplier_name       NVARCHAR(100),
    total_qty_supplied  INT
);

INSERT INTO dim_supplier
SELECT
    TRIM(supplier_id)                        AS supplier_id,
    MAX(TRIM(supplier_name))                 AS supplier_name,
    SUM(TRY_CAST(quantity_supplied AS INT))  AS total_qty_supplied
FROM sales_raw_data
WHERE supplier_id IS NOT NULL
  AND TRIM(supplier_id) <> ''
GROUP BY TRIM(supplier_id);
GO

-- ============================================================
-- fact_sales
-- ============================================================
IF OBJECT_ID('fact_sales','U') IS NOT NULL DROP TABLE fact_sales;

CREATE TABLE fact_sales (
    transaction_id      NVARCHAR(20)    NOT NULL PRIMARY KEY,
    date_id             INT,
    customer_id         NVARCHAR(10),
    product_sk          INT,
    branch_sk           INT,
    supplier_id         NVARCHAR(10),
    unit_price          DECIMAL(10,2),
    unit_cost           DECIMAL(10,2),
    quantity            SMALLINT,
    discount_percentage DECIMAL(5,2),
    payment_method      NVARCHAR(30)
);

WITH cleaned AS (
    SELECT
        transaction_id,
        CONVERT(INT, FORMAT(
            COALESCE(
                TRY_CONVERT(DATE, sale_date, 23),
                TRY_CONVERT(DATE, sale_date, 105),
                TRY_CONVERT(DATE, sale_date, 101)
            ),
        'yyyyMMdd')) AS date_id,
        customer_id,
        product_id,
        branch_id,
        TRIM(supplier_id) AS supplier_id,
        TRY_CAST(unit_price AS DECIMAL(10,2))  AS unit_price,
        TRY_CAST(unit_cost  AS DECIMAL(10,2))  AS unit_cost,
        CASE
            WHEN TRY_CAST(quantity AS INT) > 0
            THEN TRY_CAST(quantity AS SMALLINT)
            ELSE NULL
        END AS quantity,
        CASE
            WHEN TRY_CAST(discount_percentage AS DECIMAL(5,2)) BETWEEN 0 AND 100
            THEN TRY_CAST(discount_percentage AS DECIMAL(5,2))
            ELSE NULL
        END AS discount_percentage,
        CASE
            WHEN UPPER(TRIM(payment_method)) IN ('CASH','CSH')                           THEN 'Cash'
            WHEN UPPER(TRIM(payment_method)) IN ('CREDIT CARD','CC','CREDITCARD')         THEN 'Credit Card'
            WHEN UPPER(TRIM(payment_method)) IN ('DEBIT CARD','DC')                      THEN 'Debit Card'
            WHEN UPPER(TRIM(payment_method)) IN ('MOBILE WALLET','E-WALLET','MOBILE','MOBILE WALLET ')
                                                                                          THEN 'Mobile Wallet'
            ELSE TRIM(payment_method)
        END AS payment_method,
        ROW_NUMBER() OVER (
            PARTITION BY transaction_id
            ORDER BY (SELECT NULL)
        ) AS rn
    FROM sales_raw_data
    WHERE transaction_id IS NOT NULL
)
INSERT INTO fact_sales
SELECT
    c.transaction_id,
    c.date_id,
    c.customer_id,
    p.product_sk,
    b.branch_sk,
    c.supplier_id,
    c.unit_price,
    c.unit_cost,
    c.quantity,
    c.discount_percentage,
    c.payment_method
FROM cleaned c
LEFT JOIN dim_product p ON c.product_id = p.product_id AND p.is_current = 1
LEFT JOIN dim_branch  b ON c.branch_id  = b.branch_id  AND b.is_current = 1
WHERE c.rn       = 1
  AND c.date_id  IS NOT NULL
  AND c.quantity IS NOT NULL;
GO

-- ============================================================
-- VALIDATION
-- ============================================================
SELECT 'dim_date'     AS table_name, COUNT(*) AS row_count FROM dim_date
UNION ALL
SELECT 'dim_customer',               COUNT(*) FROM dim_customer
UNION ALL
SELECT 'dim_product',                COUNT(*) FROM dim_product
UNION ALL
SELECT 'dim_branch',                 COUNT(*) FROM dim_branch
UNION ALL
SELECT 'dim_supplier',               COUNT(*) FROM dim_supplier
UNION ALL
SELECT 'fact_sales',                 COUNT(*) FROM fact_sales;

SELECT
    (SELECT COUNT(*) FROM sales_raw_data) AS staged_rows,
    (SELECT COUNT(*) FROM fact_sales)    AS loaded_rows,
    (SELECT COUNT(*) FROM sales_raw_data)
  - (SELECT COUNT(*) FROM fact_sales)   AS excluded_rows;
GO