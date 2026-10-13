USE DataCO
GO

WITH VentasMensuales AS 
(
    SELECT d.Month AS Mes,
           d.Month_Name AS Nombre_Mes,
           SUM(f.Total_Amount) AS Ventas_Netas
    FROM FactSales f

    INNER JOIN DimDate d ON f.Order_Date_Key = d.Date_Key
    INNER JOIN DimOrder o ON f.Order_Id= o.Order_Id
    WHERE o.Order_Status NOT IN ('CANCELED', 'SUSPECTED_FRAUD') AND d.Year BETWEEN 2015 AND 2016
    GROUP BY d.Year, d.Month, d.Month_Name
),

PorMes AS 
(
    SELECT Mes,
           Nombre_Mes,
           AVG(Ventas_Netas) AS Ventas_Prom_Mensual
    FROM VentasMensuales
    GROUP BY Mes, Nombre_Mes
)

SELECT Nombre_Mes AS 'Meses' ,
       CAST(Ventas_Prom_Mensual AS DECIMAL(12,2)) AS'Promedio de ventas mensulaes',
       CAST(Ventas_Prom_Mensual*100.0 /AVG(Ventas_Prom_Mensual) OVER () AS DECIMAL(6,2)) AS 'Indice estacional'
FROM PorMes
ORDER BY Mes;
GO


