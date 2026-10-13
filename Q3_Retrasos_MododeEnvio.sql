USE DataCO;
GO

WITH Envios AS 
(
    SELECT DISTINCT f.Order_Id,
                    ds.Shipping_Mode AS Modo_Envio,
                    (f.Days_For_Shipping_Real -f.Days_For_Shipment_Scheduled)AS Dias_Retraso,
                    CASE 
                    WHEN f.Days_For_Shipping_Real> f.Days_For_Shipment_Scheduled
                    THEN 1 
                    ELSE 0 
                    END AS Retraso
    FROM FactSales f
    INNER JOIN DimShipping ds ON f.Shipping_Key = ds.Shipping_Key
    INNER JOIN DimOrder o  ON f.Order_Id = o.Order_Id
    WHERE o.Order_Status NOT IN ('CANCELED','SUSPECTED_FRAUD')
)

SELECT
    Modo_Envio AS 'Modo de envio',
    COUNT(*) AS 'Total de pedidos',
    SUM(Retraso) AS 'Pedidos con retraso',
    CAST(SUM(Retraso) * 100.0 / COUNT(*) AS DECIMAL(5,2)) AS '% Retraso',
    CAST(AVG(CASE
             WHEN Retraso = 1
             THEN (Dias_Retraso) * 1.0 END) AS DECIMAL(5,2))AS 'Promedio de días de retraso'
FROM Envios
GROUP BY Modo_Envio
ORDER BY '% Retraso' DESC
GO

