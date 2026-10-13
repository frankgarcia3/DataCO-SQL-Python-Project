USE DataCO
GO

WITH VentasMensuales AS 
(
    SELECT d.Year AS 'Año',
           d.Month AS 'Mes',
           d.Month_Name AS 'Meses',
           SUM(f.Total_Amount) AS Ventas_Netas,
           SUM(f.Benefit) AS Beneficio_Total
    FROM FactSales f

    INNER JOIN DimDate d 
    ON f.Order_Date_Key = d.Date_Key
    INNER JOIN DimOrder o 
    ON f.Order_Id = o.Order_Id

    WHERE o.Order_Status NOT IN ('CANCELED', 'SUSPECTED_FRAUD')
    GROUP BY d.Year, d.Month, d.Month_Name
),

Anterior AS 
(
    SELECT *,
           LAG(Ventas_Netas) OVER (ORDER BY Año, Mes) AS Ventas_Mes_Anterior,
           LAG(Beneficio_Total) OVER (ORDER BY Año, Mes) AS Beneficio_Mes_Anterior
    FROM VentasMensuales
)

SELECT
    Año,
    Meses ,
    Ventas_Netas AS 'Ventas netas',
    Ventas_Mes_Anterior 'Ventas del mes anterior',
    Ventas_Netas - Ventas_Mes_Anterior AS 'Diferencia',
    CAST((Ventas_Netas - Ventas_Mes_Anterior) * 100.0 / Ventas_Mes_Anterior AS DECIMAL(10,2)) AS '% Variacion',
    Beneficio_Total  AS 'Beneficio total',
    Beneficio_Mes_Anterior AS 'Beneficio del mes anterior',
    Beneficio_Total - Beneficio_Mes_Anterior AS 'Diferencia',
    CAST((Beneficio_Total - Beneficio_Mes_Anterior) * 100.0 / Beneficio_Mes_Anterior AS DECIMAL(10,2)) AS '% Variacion',
    CAST(Beneficio_Total * 100.0 / Ventas_Netas AS DECIMAL(5,2)) AS 'Margen'
FROM Anterior
ORDER BY Año, Mes
GO

