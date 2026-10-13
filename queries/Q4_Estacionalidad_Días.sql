USE DataCO
GO

WITH VentasDiarias AS 
(
    SELECT d.Full_Date,
           d.Day_Name,
           SUM(f.Total_Amount) AS Ventas_Netas
    FROM FactSales f

    INNER JOIN DimDate d ON f.Order_Date_Key = d.Date_Key
    INNER JOIN DimOrder o ON f.Order_Id= o.Order_Id
    WHERE o.Order_Status NOT IN ('CANCELED', 'SUSPECTED_FRAUD')AND d.Year BETWEEN 2015 AND 2016
    GROUP BY d.Full_Date, d.Day_Name
)

SELECT Day_Name AS 'Dia de la semana',
       COUNT(*)AS 'Dias',
       CAST(AVG(Ventas_Netas)AS DECIMAL(18,2)) AS 'Promedio de ventas diarias'
FROM VentasDiarias
GROUP BY Day_Name
