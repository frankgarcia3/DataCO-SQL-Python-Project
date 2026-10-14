# Análisis de cadena de suministro DataCo: SQL Server + Python

Proyecto de análisis de datos sobre el dataset *DataCo Smart Supply Chain*
(pedidos, envíos, clientes y productos). Incluye modelado dimensional en
SQL Server, consultas de negocio en T-SQL y un análisis complementario en
Python conectado a la base.

**Herramientas:** SQL Server (T-SQL), Python (pandas, SQLAlchemy, pyodbc,
matplotlib).

## Resumen de hallazgos

- Las ventas netas son estables (~10,6 M anuales en 2015 y 2016) y no hay
  estacionalidad marcada ni por mes ni por día de la semana.
- El descuento no explica el margen: el margen se mantiene entre 11,7 % y
  13,0 % en todos los tramos de descuento (correlación de -0,0015).
- El 57,3 % de los pedidos válidos llega tarde, y el retraso depende del modo
  de envío, no del mercado.
- Se detectó una anomalía de datos: las ventas de noviembre y diciembre de
  2017 caen ~40 % y ~52 % frente a 2016, por lo que se excluyen del análisis
  estacional.
- Cerca del 18,7 % de los ítems tiene beneficio negativo, con una proporción
  casi idéntica en todos los tramos de descuento.

## Arquitectura y Modelado de Datos (ETL)

Esquema estrella con una tabla de hechos a nivel de **ítem de pedido** y una
dimensión de pedido para los atributos y medidas que pertenecen al pedido.

<img width="904" height="838" alt="image" src="https://github.com/user-attachments/assets/81090e63-00cc-4368-b7ee-732541927f35" />



| Tabla | Grano | Contenido |
|---|---|---|
| `FactSales` | 1 fila por ítem de pedido | ventas, descuento, beneficio, cantidades, días de envío y claves a las dimensiones |
| `DimOrder` | 1 fila por pedido | estado, tipo de transacción, mercado y ubicación del pedido |
| `DimCustomer`, `DimProduct`, `DimCategory`, `DimDepartment` | 1 fila por entidad | atributos descriptivos |
| `DimShipping` | 1 fila por combinación | modo de envío y estado de entrega |
| `DimDate` | 1 fila por día | año, mes, nombre del mes, día, nombre del día |

**Decisión de diseño:** los datos personales de clientes (nombre, calle) y
las columnas duplicadas del dataset original no se usan en ningún análisis ni
se publican en este repositorio.

### Carga y tipos de datos

Al importar el CSV con los campos numéricos como `float`, SQL Server no
interpretó correctamente el punto decimal. Para resolverlo, volví a importar
el archivo con **todos los campos numéricos como `VARCHAR(50)`**, de modo que
el valor llegara intacto a la tabla de staging, y después los convertí al
tipo definitivo con `ALTER COLUMN`:

| Columnas | Tipo final | Motivo |
|---|---|---|
| Montos (`Sales`, `Benefit_per_order`, `Order_Item_Total`, `Product_Price`, entre otros) | `DECIMAL(12,2)` | son dinero; el CSV traía ruido de punto flotante (p. ej. `59.99000168`) que se redondea a 2 decimales |
| `Order_Item_Discount_Rate`, `Order_Item_Profit_Ratio` | `DECIMAL(5,2)` | proporciones |
| `Latitude` | `DECIMAL(10,7)` | conserva la precisión geográfica |
| `Longitude` | `DECIMAL(11,7)` | conserva la precisión geográfica |

Antes de convertir, validé con `TRY_CAST` que no hubiera valores no
convertibles, cadenas vacías (que se convertirían en 0 en lugar de `NULL`) ni
desbordamientos de rango, y comprobé que la diferencia entre cada valor y su
redondeo a 2 decimales fuera insignificante.

**Script incluido:** el archivo
[`db_setup.sql`](scripts/00_creacion_y_carga_tablas.sql)
crea y puebla las tablas del modelo (conversión de tipos, dimensiones y tabla
de hechos), de modo que el proceso se pueda reproducir desde la tabla de
staging.

## Definiciones comunes a todas las consultas

- **Ingresos** = `Total_Amount` (neto de descuento). `Sales` es el monto
  bruto y solo se usa para medir descuentos.
- **Margen** = `SUM(Benefit) / SUM(Total_Amount)` (ponderado, no promedio de
  ratios por ítem).
- **Pedidos válidos:** se excluyen los estados `CANCELED` y
  `SUSPECTED_FRAUD`. Quedan 172 765 ítems y 62 897 pedidos.
- **Unidad de análisis de entregas:** el pedido, no el ítem. Las medidas de
  envío se repiten en cada ítem, por lo que se deduplican por `Order_Id`
  antes de promediar.

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


**Hallazgos:**
- Las ventas netas son estables: ~10,6 M anuales en 2015 y 2016 (-0,2 %),
  con variaciones mensuales normales de entre -8 % y +6,5 %. <!-- VERIFICAR con consulta de totales anuales -->
- De enero a octubre de 2017 las ventas crecen ~4,1 % frente al mismo
  periodo de 2016. <!-- VERIFICAR -->
- Febrero es el mes más bajo de cada año (792 mil en 2015 y 834 mil en 2016).
- El margen se mueve entre 10 % y 14 %. El beneficio es más volátil que las
  ventas, lo que indica variación de margen y no solo de volumen.

**Nota de calidad de datos:** en noviembre y diciembre de 2017 las ventas
caen ~40 % y ~52 % frente a los mismos meses de 2016 (538 mil y 432 mil
frente a 895 mil), y enero de 2018 sigue bajo (285 mil). Hay ventas todos los
días de esos meses y la causa no se puede determinar con los datos
disponibles, por lo que no se interpreta como una caída real del negocio.




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

| Tramo | Ítems | Ventas netas | % ventas | Beneficio | Margen % | Ítems con pérdida | % con pérdida |
|---|---|---|---|---|---|---|---|
| Sin descuento | 9 640 | 1 966 128,04 | 6,21 | 254 642,79 | 12,95 | 1 790 | 18,57 |
| 1 % - 5 % | 48 003 | 9 482 703,92 | 29,97 | 1 125 743,14 | 11,87 | 8 961 | 18,67 |
| 6 % - 10 % | 38 386 | 7 212 039,88 | 22,79 | 882 469,98 | 12,24 | 7 044 | 18,35 |
| 11 % - 15 % | 28 737 | 5 074 819,31 | 16,04 | 599 919,36 | 11,82 | 5 446 | 18,95 |
| 16 % - 20 % | 38 424 | 6 444 632,78 | 20,37 | 755 546,32 | 11,72 | 7 306 | 19,01 |
| Más de 20 % | 9 575 | 1 464 340,82 | 4,63 | 188 099,04 | 12,85 | 1 748 | 18,26 |
| **Total** | **172 765** | **31 644 664,75** | **100** | **3 806 420,63** | **12,03** | **32 295** | **18,69** |

<!-- VERIFICAR totales y % con pérdida con una consulta sin agrupar por tramo -->

**Hallazgos:**
- El margen se mantiene en un rango estrecho (11,72 % a 12,95 %): solo 1,23
  puntos porcentuales entre el mejor y el peor tramo, y no cae de forma
  continua (el tramo de más de 20 % recupera 12,85 %, con solo el 4,63 % de
  las ventas).
- El 93,8 % de las ventas se realiza con algún descuento y el 41 % con más
  de 10 %.
- Cerca del 18,7 % de los ítems tiene beneficio negativo, y la proporción es
  prácticamente la misma en todos los tramos (18,3 % a 19,0 %), incluso sin
  descuento. El descuento, por tanto, no explica las pérdidas.



---

### Consulta 3: Retrasos por modo de envío

**Pregunta:** ¿Qué modo de envío tiene más retrasos y de cuántos días?

**Definiciones:** retraso = días reales > días programados.

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

| Modo de envío | Pedidos | Con retraso | % retraso | Días prog. | Días reales | Retraso prom. (días) |
|---|---|---|---|---|---|---|
| First Class | 9 602 | 9 602 | 100,00 | 1,00 | 2,00 | 1,00 |
| Second Class | 12 256 | 9 803 | 79,99 | 2,00 | 4,00 | 2,50 |
| Same Day | 3 407 | 1 648 | 48,37 | 0,00 | 0,48 | 1,00 |
| Standard Class | 37 632 | 14 995 | 39,85 | 4,00 | 3,99 | 1,50 |

**Hallazgos:**
- De 62 897 pedidos, 36 048 (57,3 %) llegan tarde.
- First Class se retrasa en el 100 % de sus pedidos (siempre 1 día) y Second
  Class en el 80 % (2,5 días de promedio), frente al 39,85 % de Standard
  Class.
- Standard Class tiene la menor tasa, pero concentra el 41,6 % de los pedidos
  retrasados por su volumen (59,8 % de los pedidos).
- Los modos más rápidos tienen plazos programados muy cortos (0 a 2 días),
  por lo que una demora de un día ya cuenta como retraso.

**Recomendación de negocio:** revisar los plazos prometidos de First y Second
Class, que no se cumplen de forma sistemática, antes de buscar causas en la
operación logística.

**Nota de calidad de datos:** `Late_delivery_risk` coincide con el retraso
medido por días en los 36 048 pedidos válidos. Las únicas 1 650
discrepancias (788 `CANCELED` y 862 `SUSPECTED_FRAUD`) corresponden a
pedidos excluidos del análisis. El retraso se calcula con los días por
transparencia; el resultado es equivalente a usar la bandera.

**Limitación:** el 100 % de First Class, con días reales siempre iguales a
programados + 1, no es un patrón típico de operación real y sugiere que los
días del dataset siguen una regla artificial.



---

### Consulta 4: Estacionalidad (mes del año y día de la semana)

**Pregunta:** ¿Hay estacionalidad en las ventas por mes del año o por día de
la semana?

**Definiciones:** análisis sobre **2015 y 2016** (años completos). Se
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


**Resultado por mes:**

| Mes | Ventas prom. mensuales | Índice |
|---|---|---|
| Enero | 906 483,86 | 102,53 |
| Febrero | 813 182,78 | 91,97 |
| Marzo | 896 342,82 | 101,38 |
| Abril | 866 743,87 | 98,03 |
| Mayo | 888 029,74 | 100,44 |
| Junio | 872 056,30 | 98,63 |
| Julio | 895 140,74 | 101,24 |
| Agosto | 898 931,47 | 101,67 |
| Septiembre | 872 009,31 | 98,63 |
| Octubre | 906 032,12 | 102,47 |
| Noviembre | 892 127,35 | 100,90 |
| Diciembre | 902 715,52 | 102,10 |

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

**Resultado por día de la semana** (ventas promedio por día calendario):

| Día | Días en el periodo | Ventas prom. diarias |
|---|---|---|
| Sábado | 105 | 29 329,30 |
| Domingo | 104 | 29 218,38 |
| Viernes | 104 | 29 216,78 |
| Martes | 104 | 29 021,19 |
| Jueves | 105 | 28 985,39 |
| Lunes | 104 | 28 956,42 |
| Miércoles | 104 | 28 465,43 |

**Hallazgos:**
- No hay estacionalidad marcada: once de los doce meses se ubican entre 98,0
  y 102,5 (±2,5 % del promedio).
- Febrero es el único mes claramente bajo (91,97). Su menor número de días
  (28) podría explicar gran parte de la diferencia (hipótesis, no
  comprobada con ventas por día).
- Noviembre (100,90) y diciembre (102,10) no muestran efecto de temporada de
  fin de año.
- Por día de la semana, la diferencia entre el día más alto (sábado) y el
  más bajo (miércoles) es de ~3 %, y seis de los siete días están dentro de
  ±1 % del promedio.

**Nota de calidad de datos:** en 2017, noviembre y diciembre caen ~40 % y
~52 % frente a 2016 aunque todos los días tienen ventas. Con 2017 incluido,
el índice de esos meses bajaría a 88,87 y 85,62, lo que parecería
estacionalidad pero no lo es, porque 2015 y 2016 no muestran esa caída.

**Recomendación de negocio:** la demanda es estable durante el año y la
semana; no se justifica planificar inventario o capacidad con picos
estacionales.

**Limitación:** solo dos años completos; diferencias de este tamaño no
permiten distinguir un patrón real del ruido.





## Análisis en Python (post-SQL)

Conecté Python (pandas, SQLAlchemy, pyodbc) a la base `DataCO` en SQL
Server. Cada análisis usa los mismos filtros que las consultas SQL para que
las cifras sean comparables. Notebook: [`notebooks/analisis_dataco.ipynb`](notebooks/analisis_dataco.ipynb).

**Validación de la conexión:** el DataFrame cargado tiene [172 765] filas,
igual que el conteo de ítems válidos de la consulta 4. <!-- VERIFICAR con len(df) -->

### Análisis 1: Distribución de ítems por rango de margen

**Pregunta:** ¿Qué porcentaje de ítems tiene pérdida y cómo se reparte el
margen (`Benefit / Total_Amount`) del resto?

<img width="888" height="484" alt="image" src="https://github.com/user-attachments/assets/c1d49067-dbb0-4171-a498-d25d60b94ac8" />


**Hallazgos:**
- El 18,7 % de los ítems tiene margen negativo, cifra que coincide con la
  consulta 4 de SQL (32 295 de 172 765 ítems), lo que sirve como validación
  cruzada entre SQL y Python.
- El 81,3 % de los ítems tiene margen positivo, y el 43 % supera el 30 %
  (22,1 % entre 30 y 40 %, y 20,9 % por encima de 40 %). <!-- VERIFICAR sumas -->
- Los ítems con margen bajo (entre 0 y 20 %) son el grupo más pequeño
  (21,6 %): la distribución se concentra en margen alto o en pérdida.  

### Análisis 2: Descuento vs. margen

**Pregunta:** ¿Se relaciona el nivel de descuento con el margen del ítem?

<img width="884" height="483" alt="WhatsApp Image 2026-10-14 at 12 58 27 PM" src="https://github.com/user-attachments/assets/13601b82-0708-4e7f-884a-1ec0137c3d9f" />


**Hallazgos:**
- La correlación entre descuento y margen es de -0,0015, prácticamente nula.
- El margen promedio es plano (~0,12) en todos los niveles de descuento, de
  0 % a 25 %, coherente con la consulta 4.

**Limitación:** el gráfico usa una muestra aleatoria de 5 000 ítems para los
puntos; la línea de margen promedio usa todos los datos.


### Análisis 4: Retraso por modo de envío y mercado

**Pregunta:** ¿El retraso depende del modo de envío, del mercado o de ambos?

<img width="847" height="438" alt="WhatsApp Image 2026-10-14 at 12 57 20 PM" src="https://github.com/user-attachments/assets/ffd1ca0b-98c9-44f7-b613-4add96bbf174" />

**Hallazgos:**
- El retraso depende del modo de envío, no del mercado: dentro de cada modo,
  el porcentaje varía como máximo 5 puntos entre mercados.
- First Class se retrasa en el 100 % de los pedidos en los cinco mercados;
  Second Class, en torno al 80 %; Standard Class, en torno al 40 %.
- Same Day presenta el mayor rango entre mercados (46 % a 51 %), pero con
  celdas más pequeñas esa diferencia puede ser ruido.
- Los resultados por modo coinciden con la consulta 5.

**Limitaciones:**
- La celda más pequeña tiene 223 pedidos.
- La uniformidad entre mercados y el 100 % de First Class sugieren que los
  días de entrega del dataset siguen una regla artificial, por lo que no
  deben leerse como desempeño logístico real.

## Estructura del repositorio

```
/scripts        00_creacion_y_carga_tablas.sql (tipos, dimensiones y hechos)
                y consultas SQL numeradas (01_ventas_mensuales.sql, ...)
/notebooks      análisis en Python
/imagenes       capturas y gráficos
README.md
```

Los datos originales no se incluyen por tamaño; el dataset se puede
descargar desde Kaggle (*DataCo Smart Supply Chain for Big Data Analysis*).

