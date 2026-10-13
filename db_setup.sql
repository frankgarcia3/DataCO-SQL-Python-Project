USE DataCO
GO
/*    
CREATE TABLE DimCustomer
(
    Customer_Id INT PRIMARY KEY,
    Customer_City VARCHAR(20),
    Customer_Country VARCHAR(11),
    Customer_Fname VARCHAR(11),
    Customer_Lname VARCHAR(12),
    Customer_Segment VARCHAR(20),
    Customer_State VARCHAR(2),
    Customer_Street VARCHAR(33),
    Customer_Zipcode VARCHAR(5)
);
GO

INSERT INTO DimCustomer
SELECT DISTINCT
    Customer_Id,
    Customer_City,
    Customer_Country,
    Customer_Fname,
    Customer_Lname,
    Customer_Segment,
    Customer_State,
    Customer_Street,
    Customer_Zipcode
FROM dbo.DataCoSupplyChainDataset2;

CREATE TABLE DimDepartment 
(
    Department_Id INT PRIMARY KEY,
    Department_Name VARCHAR(17)
);
GO


INSERT INTO DimDepartment
SELECT DISTINCT
    Department_Id,
    Department_Name
FROM dbo.DataCoSupplyChainDataset2


CREATE TABLE DimCategory 
(
    Category_Id INT PRIMARY KEY,
    Department_Id INT
    CONSTRAINT fk_category_department 
    FOREIGN KEY (Department_Id) 
    REFERENCES DimDepartment(Department_Id),
    Category_Name VARCHAR(20),
    
);
GO


INSERT INTO DimCategory
SELECT DISTINCT
    Category_Id,
    Department_Id,
    Category_Name
FROM dbo.DataCoSupplyChainDataset2
GO


CREATE TABLE DimProduct 
(
    Product_Card_Id INT PRIMARY KEY,
    Category_Id INT
    CONSTRAINT fk_product_category
    FOREIGN KEY (Category_Id) 
    REFERENCES DimCategory(Category_Id),
    Product_Name VARCHAR(45),
    Product_Image VARCHAR(94),
    Product_Price DECIMAL(10, 2),
    Product_Status INT,
);

GO

INSERT INTO DimProduct
SELECT DISTINCT
    Product_Card_Id,
    Category_Id,
    Product_Name,
    Product_Image,
    Product_Price,
    Product_Status

FROM dbo.DataCoSupplyChainDataset2
GO


CREATE TABLE DimOrder 
(
    Order_Id INT PRIMARY KEY,
    Type VARCHAR(8),
    Order_Status VARCHAR(20),
    Order_City VARCHAR(40),
    Order_State VARCHAR(40),
    Order_Country VARCHAR(40),
    Order_Region VARCHAR(20),
    Order_Zipcode VARCHAR(5),
    Market VARCHAR(20)
);
GO

INSERT INTO DimOrder
SELECT DISTINCT
    Order_Id,
    Type,
    Order_Status,
    Order_City,
    Order_State,
    Order_Country,
    Order_Region,
    Order_Zipcode,
    Market  
FROM dbo.DataCoSupplyChainDataset2
WHERE Order_Id IS NOT NULL;
GO


CREATE TABLE DimShipping 
(
    Shipping_Key INT IDENTITY(1,1) PRIMARY KEY,
    Shipping_Mode VARCHAR(50),
    Delivery_Status VARCHAR(50)
);
GO


INSERT INTO DimShipping 
(
    Shipping_Mode, 
    Delivery_Status
)
SELECT DISTINCT
    Shipping_Mode,
    Delivery_Status
FROM dbo.DataCoSupplyChainDataset2
GO



CREATE TABLE DimDate 
(
    Date_Key INT PRIMARY KEY,           
    Full_Date DATE NOT NULL,           
    Year INT NOT NULL,                               
    Month INT NOT NULL,                 
    Month_Name VARCHAR(20) NOT NULL,    
    Day INT NOT NULL,                             
    Day_Name VARCHAR(20) NOT NULL      
);
GO

WITH Fechas_Consolidadas AS 
(
    SELECT CAST([order_date_DateOrders] AS DATE) AS Fecha
    FROM dbo.DataCoSupplyChainDataset2
    UNION
    SELECT CAST([shipping_date_DateOrders] AS DATE) AS Fecha
    FROM dbo.DataCoSupplyChainDataset2 
)

INSERT INTO DimDate 
(
    Date_Key,
    Full_Date,
    Year,
    Month,
    Month_Name,
    Day,
    Day_Name
)

SELECT
    CONVERT(INT, FORMAT(Fecha, 'yyyyMMdd')) AS Date_Key,
    Fecha AS Full_Date,
    YEAR(Fecha) AS Year,
    MONTH(Fecha) AS Month,
    DATENAME(MONTH, Fecha) AS Month_Name,
    DAY(Fecha) AS Day,
    DATENAME(WEEKDAY, Fecha) AS Day_Name
FROM Fechas_Consolidadas;
GO

*/

CREATE TABLE FactSales 
(
    Order_Item_Id INT PRIMARY KEY,
    Order_Id INT NOT NULL,
    CONSTRAINT fk_fact_order 
    FOREIGN KEY (Order_Id) REFERENCES DimOrder(Order_Id),

    Product_Card_Id INT NOT NULL,
    CONSTRAINT fk_fact_product 
    FOREIGN KEY (Product_Card_Id) REFERENCES DimProduct(Product_Card_Id),
    
    Customer_Id INT NOT NULL,
    CONSTRAINT fk_fact_customer 
    FOREIGN KEY (Customer_Id) REFERENCES DimCustomer(Customer_Id),
    
    Shipping_Key INT,
    CONSTRAINT fk_fact_shipping 
    FOREIGN KEY (Shipping_Key) REFERENCES DimShipping(Shipping_Key),
    
    Order_Date_Key INT,
    CONSTRAINT fk_fact_order_date 
    FOREIGN KEY (Order_Date_Key) REFERENCES DimDate(Date_Key),
    
    Shipping_Date_Key INT,
    CONSTRAINT fk_fact_shipping_date 
    FOREIGN KEY (Shipping_Date_Key) REFERENCES DimDate(Date_Key),
    
    Sales DECIMAL(12,2),
    Sales_Per_Customer DECIMAL(12,2),
    Quantity INT,
    Discount DECIMAL(12,2),
    Discount_Rate DECIMAL(5,2),
    Product_Price DECIMAL(12,2),
    Profit_Ratio DECIMAL(5,2),
    Total_Amount DECIMAL(12,2),
    Benefit DECIMAL(12,2),
    Days_For_Shipping_Real INT,
    Days_For_Shipment_Scheduled INT,
    Late_Delivery_Risk TINYINT
);
GO

INSERT INTO FactSales 
SELECT 
    dco.Order_Item_Id,
    dco.Order_Id,
    dco.Product_Card_Id,
    dco.Customer_Id,
    ds.Shipping_Key,
    CONVERT(INT, FORMAT(dco.order_date_DateOrders, 'yyyyMMdd' )) AS Order_Date_Key,
    CONVERT(INT,FORMAT(dco.shipping_date_DateOrders, 'yyyyMMdd')) AS Shipping_Date_Key,
    dco.Sales,
    dco.Sales_per_customer,
    dco.Order_Item_Quantity,
    dco.Order_Item_Discount,
    dco.Order_Item_Discount_Rate,
    dco.Order_Item_Product_Price,
    dco.Order_Item_Profit_Ratio,
    dco.Order_Item_Total,
    dco.Benefit_per_order,
    dco.Days_for_shipping_real,
    dco.Days_for_shipment_scheduled,
    dco.Late_delivery_risk
FROM dbo.DataCoSupplyChainDataset2 dco
LEFT JOIN DimShipping ds 
ON dco.Shipping_Mode = ds.Shipping_Mode AND dco.Delivery_Status = ds.Delivery_Status
