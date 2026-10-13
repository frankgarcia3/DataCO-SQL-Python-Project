USE DataCO
GO

WITH Items AS 
(
    SELECT f.Order_Item_Id,
           f.Total_Amount,
           f.Benefit,
           f.Discount_Rate,
           CASE
           WHEN f.Discount_Rate = 0 THEN 'Sin descuento'
           WHEN f.Discount_Rate<= 0.05 THEN '1% - 5%'
           WHEN f.Discount_Rate<= 0.10 THEN '6% - 10%'
           WHEN f.Discount_Rate <= 0.15 THEN '11% - 15%'
           WHEN f.Discount_Rate <= 0.20 THEN '16% - 20%'
           ELSE                              'Más de 20%'
           END
           AS Descuento
    FROM FactSales f

    INNER JOIN DimOrder o 
    ON o.Order_Id = f.Order_Id
    WHERE o.Order_Status NOT IN ('CANCELED', 'SUSPECTED_FRAUD')
 )

SELECT Descuento,
       COUNT(*) AS 'Items vendidos',
       SUM(Total_Amount) AS 'Ventas Netas',
       CAST(SUM(Total_Amount) * 100.0/ SUM( SUM(Total_Amount)) OVER() AS DECIMAL(5,2)) AS '% Ventas',
       SUM(Benefit) AS 'Beneficio total',
       CAST(SUM(Benefit) * 100.0 / SUM(Total_Amount)AS DECIMAL(5,2)) AS '% Margen',
       SUM(CASE 
           WHEN Benefit < 0 THEN 1 
           ELSE 0 END) AS 'Items con perdida'
FROM Items
GROUP BY Descuento
ORDER BY MIN(Discount_Rate)
GO

