# Análisis de cadena de suministro DataCo: SQL Server + Python

Proyecto de análisis de datos sobre el dataset *DataCo Smart Supply Chain*
(pedidos, envíos, clientes y productos). Incluye modelado dimensional en
SQL Server, consultas de negocio en T-SQL y un análisis complementario en
Python (pandas, SQLAlchemy, pyodbc,
matplotlib) conectado a la base.



## Arquitectura y Modelado de Datos (ETL)

Esquema estrella con una tabla de hechos a nivel de ítem de pedido y una
dimensión de pedido para los atributos y medidas que pertenecen al pedido.

<img width="904" height="838" alt="image" src="https://github.com/user-attachments/assets/81090e63-00cc-4368-b7ee-732541927f35" />










| Tabla | Grano | Contenido |
|---|---|---|
| `FactSales` | 1 fila por ítem de pedido | ventas, descuento, beneficio, cantidades, días de envío y claves a las dimensiones |
| `DimOrder` | 1 fila por pedido | estado, tipo de transacción, mercado y ubicación del pedido |
| `DimCustomer`, `DimProduct`, `DimCategory`, `DimDepartment` | 1 fila por entidad | atributos descriptivos |
| `DimShipping` | 1 fila por combinación | modo de envío y estado de entrega |
| `DimDate` | 1 fila por día | año, mes, nombre del mes, día, nombre del día |


### Carga y tipos de datos

Al importar el CSV con los campos numéricos como `float`, SQL Server no
interpretó correctamente el punto decimal. Para resolverlo, volví a importar
el archivo con **todos los campos numéricos como `VARCHAR(50)`**, de modo que
el valor llegara intacto a la tabla staging y después convertirlos a tipo de dato `DECIMAL()`** con `ALTER COLUMN`:

```sql
USE DataCO
GO
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Benefit_per_order        DECIMAL(12,2);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Sales_per_customer       DECIMAL(12,2);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Order_Item_Discount      DECIMAL(12,2);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Order_Item_Product_Price DECIMAL(12,2);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Sales                    DECIMAL(12,2);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Order_Item_Total         DECIMAL(12,2);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Order_Profit_Per_Order   DECIMAL(12,2);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Product_Price            DECIMAL(12,2);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Order_Item_Discount_Rate DECIMAL(5,2);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Order_Item_Profit_Ratio  DECIMAL(5,2);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Latitude                 DECIMAL(10,7);
ALTER TABLE DataCoSupplyChainDataset2 ALTER COLUMN Longitude                DECIMAL(11,7);       
```


Antes de convertir, validé con TRY_CAST que no hubiera valores no convertibles, cadenas vacías (que se convertirían en 0 en lugar de NULL) ni desbordamientos de rango, y comprobé que la diferencia entre cada valor y su redondeo a 2 decimales fuera insignificante.
El archivo
[`db_setup.sql`](scripts/00_creacion_y_carga_tablas.sql)
crea y puebla las tablas del modelo, de modo que el proceso se pueda reproducir desde la tabla de
staging.

---

## Definiciones

- **Ingresos** = `Total_Amount` (neto de descuento). `Sales` es el monto
  bruto y solo se usa para medir descuentos.
- **Margen** = `SUM(Benefit) / SUM(Total_Amount)`
- **Pedidos válidos:** Se excluyen los estados `CANCELED` y
  `SUSPECTED_FRAUD`. Quedan 172 765 ítems y 62 897 pedidos.
- **Unidad de análisis de entregas:** El pedido, no el ítem. Las medidas de
  envío se repiten en cada ítem.

## Consultas SQL

### Consulta 1: Evolución mensual de ventas y beneficio

**Pregunta:** ¿Cómo evolucionan las ventas y el beneficio mes a mes y cuánto
varían respecto al mes anterior?

```sql
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
```
**Resultado:**

  <img width="1455" height="659" alt="WhatsApp Image 2026-10-14 at 1 36 24 PM" src="https://github.com/user-attachments/assets/3b8af27a-3c2f-4bb8-8763-f6506bd94244" />


**Hallazgos:**
- Las ventas netas son estables: ~10,6 M anuales en 2015 y 2016 (-0,2 %),
  con variaciones mensuales normales de entre -8 % y +6,5 %. <!-- VERIFICAR con consulta de totales anuales -->
- De enero a octubre de 2017 las ventas crecen alrededor del 4,1 % frente al mismo
  periodo de 2016.
- Febrero es el mes más bajo de cada año, con 792 mil en 2015 y 834 mil en 2016.
- El margen de beneficio varía entre el 10 % y el 14 %. El beneficio es más volátil que las
  ventas, lo que indica que las variaciones no se deben únicamente a cuánto se vende, sino también a cuánto se gana por    cada venta.

**Nota:** En noviembre y diciembre de 2017 las ventas
caen 40 % y 52 % frente a los mismos meses de 2016 (538 mil y 432 mil
frente a 895 mil), y enero de 2018 sigue bajo (285 mil). Hay ventas todos los
días de esos meses y la causa no se puede determinar con los datos
disponibles, por lo que no se interpreta como una caída real del negocio.

---

### Consulta 2: Margen según el nivel de descuento

**Pregunta:** ¿Cómo cambia el margen a medida que aumenta el descuento
aplicado a cada ítem?

```sql
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
```

**Resultado:**

  <img width="795" height="189" alt="image" src="https://github.com/user-attachments/assets/2dc86464-70fe-4d6c-b2b0-0f136e47069d" />


**Hallazgos:**
- El margen de beneficio se mantiene bastante estable, entre 11,72 % y 12,95 %. Además, el margen no disminuye de manera constante ya que en los descuentos mayores al 20 % vuelve a subir a 12,85 %, aunque este grupo representa solo el 4,63 % de las ventas.
- El 93,8 % de las ventas se realiza con algún descuento y el 41 % con más
  de 10 %.
- Cerca del 18,7 % de los productos vendidos genera pérdidas. Lo curioso es que este porcentaje se mantiene casi igual en todos los niveles de descuento, incluso cuando no se aplica ninguno. Esto indica que los descuentos no parecen ser la causa principal de las pérdidas, por lo que sería necesario analizar otros factores.



---

### Consulta 3: Retrasos por modo de envío

**Pregunta:** ¿Qué modo de envío tiene más retrasos y de cuántos días?

Se entiende como retraso = días reales > días programados.

```sql
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
```

**Resultado:**

  <img width="734" height="135" alt="image" src="https://github.com/user-attachments/assets/a3ad3ed6-cb39-473c-9bd4-37bc012ea86d" />



**Hallazgos:**
- De 62 897 pedidos, 36 048 (57,3 %) llegan tarde.
- First Class se retrasa en el 100 % de sus pedidos (siempre 1 día) y Second
  Class en el 80 % (en promedio 2,5 días), frente al 39,85 % de Standard
  Class.
- Standard Class tiene la menor tasa, pero concentra el 41,6 % de los pedidos
  retrasados por su volumen (59,8 % de los pedidos).
- Los modos más rápidos tienen plazos programados muy cortos, por lo que una demora de un día ya cuenta como retraso.

**Recomendación de negocio:** revisar los plazos prometidos de First y Second
Class, que no se cumplen de forma sistemática, antes de buscar causas en la
operación logística.

---

### Consulta 4: Estacionalidad (mes del año y día de la semana)

**Pregunta:** ¿Hay estacionalidad en las ventas por mes del año o por día de
la semana?

En el análisis sobre **2015 y 2016** (años completos). Se
excluye 2017 por la anomalía de noviembre-diciembre. El índice estacional
es 100 cuando el mes iguala al promedio mensual.

```sql
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

```



```sql
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
GO
```

**Resultado por mes:**

  <img width="487" height="350" alt="image" src="https://github.com/user-attachments/assets/cf9eeb8f-6ab1-4716-a33b-6de774446d1a" />
  
**Resultado por día de la semana**:

  <img width="422" height="217" alt="image" src="https://github.com/user-attachments/assets/43f69b9e-abf2-4feb-9fa0-95ea3b21fbff" />


**Hallazgos:**
- No hay estacionalidad marcada ya que once de los doce meses se ubican entre 98,0
  y 102,5.
- Febrero con un indice estacional de 91,97 es el único mes claramente bajo, su menor número de días podría explicar gran parte de la diferencia.
- Noviembre con 100,90 y diciembre con 102,10 no muestran efecto de temporada de
  fin de año.
- Por día de la semana, la diferencia entre el día más alto (sábado) y el
  más bajo (miércoles) es de aproximadamente 3 %.

**Nota:** En el año 2017, los meses de noviembre y diciembre caen 40 % y
52 % aproximadamente frente a 2016 aunque todos los días tienen ventas. Con 2017 incluido,
el índice de esos meses bajaría a 88,87 y 85,62, lo que parecería
estacionalidad pero no lo es, porque 2015 y 2016 no muestran esa caída.

**Recomendación de negocio:** La demanda es estable durante el año y la
semana, no se existe razón para planificar inventario o capacidad con picos
estacionales.

---

## Análisis en Python (post-SQL)

Conecté Python (pandas, SQLAlchemy, pyodbc) a la base de datos DataCO en SQL
Server. Cada análisis usa los mismos filtros que las consultas SQL para que
las cifras sean comparables. Notebook: [`graphics.ipynb`](graphics.ipynb).


### Análisis 1: Distribución de ítems por rango de margen

**Pregunta:** ¿Qué porcentaje de ítems tiene pérdida y cómo se reparte el
margen (`Benefit / Total_Amount`) del resto?

  <img width="888" height="484" alt="image" src="https://github.com/user-attachments/assets/c1d49067-dbb0-4171-a498-d25d60b94ac8" />





**Hallazgos:**
- El 18,7 % de los ítems tiene margen negativo.
- El 81,3 % de los ítems tiene margen positivo.
- Los ítems con margen entre 0 y 20 % son el grupo más pequeño
  (21,6 %), la distribución se concentra en los ítems con margen alto o en pérdida.

---

### Análisis 2: Descuento vs. margen

**Pregunta:** ¿Se relaciona el nivel de descuento con el margen del ítem?

  <img width="884" height="483" alt="WhatsApp Image 2026-10-14 at 12 58 27 PM" src="https://github.com/user-attachments/assets/13601b82-0708-4e7f-884a-1ec0137c3d9f" />





**Hallazgos:**
- La correlación entre descuento y margen es de -0,0015, prácticamente nula.
- El margen promedio es plano (~0,12) en todos los niveles de descuento.

---

### Análisis 3: Retraso por modo de envío y mercado

**Pregunta:** ¿El retraso depende del modo de envío, del mercado o de ambos?

  <img width="847" height="438" alt="WhatsApp Image 2026-10-14 at 12 57 20 PM" src="https://github.com/user-attachments/assets/ffd1ca0b-98c9-44f7-b613-4add96bbf174" />





**Hallazgos:**
- El retraso depende del modo de envío, no del mercado.
- First Class se retrasa en el 100 % de los pedidos en los cinco mercados, Second Class en torno al 80 %, Standard Class en   torno al 40 %.
- Same Day presenta el mayor rango entre mercados (46 % a 51 %), pero con
  celdas más pequeñas esa diferencia puede ser ruido.
- Los resultados por modo coinciden con la consulta 5.
  
---
## Resumen de hallazgos

- Las ventas netas son estables y no hay
  estacionalidad marcada ni por mes ni por día de la semana.
- El descuento no explica el margen: el margen se mantiene entre 11,7 % y
  13,0 % en todos los tramos de descuento (correlación de -0,0015).
- El 57,3 % de los pedidos válidos llega tarde, y el retraso depende del modo
  de envío, no del mercado.
- Se detectó una anomalía, las ventas de noviembre y diciembre de
  2017 caen ~40 % y ~52 % frente a 2016, por lo que se excluyen del análisis
  estacional.
- Cerca del 18,7 % de los ítems tiene beneficio negativo, con una proporción
  casi idéntica en todos los tramos de descuento.

---
  

El dataset se puede descargar desde Kaggle (DataCo Smart Supply Chain )

