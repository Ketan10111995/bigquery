WITH test_sales_data AS (
  SELECT '2026-06-01' AS sale_date, 'Electronics' AS category, 1500 AS revenue UNION ALL
  SELECT '2026-06-01', 'Furniture', 800 UNION ALL
  SELECT '2026-06-01', 'Clothing', 300 UNION ALL
  SELECT '2026-06-02', 'Electronics', 2100 UNION ALL
  SELECT '2026-06-02', 'Clothing', 450 UNION ALL
  SELECT '2026-06-03', 'Electronics', 1300 UNION ALL
  SELECT '2026-06-03', 'Furniture', 1200 UNION ALL
  SELECT '2026-06-03', 'Clothing', 550
)
SELECT * 
FROM test_sales_data
PIVOT(
  SUM(revenue) AS total_rev 
  FOR category IN ('Electronics', 'Furniture', 'Clothing')
);