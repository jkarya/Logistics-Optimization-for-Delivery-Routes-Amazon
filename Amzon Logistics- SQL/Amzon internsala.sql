use  amazon ;
-- 1.1 Identify and delete duplicate Order_ID records. 
SELECT Order_ID, COUNT(*) as duplicate_count
FROM Orders
GROUP BY Order_ID
HAVING COUNT(*) > 1;
-- 1.2 Replace null Traffic_Delay_Min with the average delay for that route. 
UPDATE Routes r1
LEFT JOIN (
    SELECT AVG(Traffic_Delay_Min) as avg_delay 
    FROM Routes 
    WHERE Traffic_Delay_Min IS NOT NULL
) r2 ON 1=1
SET r1.Traffic_Delay_Min = COALESCE(r1.Traffic_Delay_Min, r2.avg_delay);
-- 1.3 Convert all date columns into YYYY-MM-DD format using SQL functions. 
UPDATE Orders
SET 
    Order_Date = STR_TO_DATE(Order_Date, '%Y-%m-%d'),
    Expected_Delivery_Date = STR_TO_DATE(Expected_Delivery_Date, '%Y-%m-%d'),
    Actual_Delivery_Date = STR_TO_DATE(Actual_Delivery_Date, '%Y-%m-%d');
-- 1.4 Ensure that no Actual_Delivery_Date is before Order_Date (flag such records). 
ALTER TABLE Orders
ADD COLUMN Date_Anomaly VARCHAR(10) DEFAULT NULL;

UPDATE Orders
SET Date_Anomaly = 'INVALID'
WHERE Actual_Delivery_Date < Order_Date;

-- 2.1 Calculate delivery delay (in days) for each order.
ALTER TABLE Orders
ADD COLUMN Delay_Days INT;

UPDATE Orders
SET Delay_Days = DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date);
-- 2.2 Find Top 10 delayed routes based on average delay days. 
SELECT 
    r.Route_ID,
    r.Start_Location,
    r.End_Location,
    AVG(o.Delay_Days) as Avg_Delay_Days
FROM Orders o
JOIN Routes r ON o.Route_ID = r.Route_ID
WHERE o.Delay_Days > 0
GROUP BY r.Route_ID, r.Start_Location, r.End_Location
ORDER BY Avg_Delay_Days DESC
LIMIT 10;
-- 2.3 Use window functions to rank all orders by delay within each warehouse. 
SELECT 
    Order_ID,
    Warehouse_ID,
    Delay_Days,
    RANK() OVER (PARTITION BY Warehouse_ID ORDER BY Delay_Days DESC) as Delay_Rank
FROM Orders
WHERE Delay_Days > 0;

-- 3.1For each route, calculate: 
#Average delivery time (in days). 
#Average traffic delay. 
#Distance-to-time efficiency ratio: Distance_KM / Average_Travel_Time_Min. 
SELECT 
    r.Route_ID,
    r.Start_Location,
    r.End_Location,
    r.Distance_KM,
    AVG(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date)) as Avg_Delivery_Time_Days,
    AVG(r.Traffic_Delay_Min) as Avg_Traffic_Delay_Min,
    (r.Distance_KM / NULLIF(r.Average_Travel_Time_Min, 0)) as Distance_Time_Ratio
FROM routes r
JOIN orders o ON r.Route_ID = o.Route_ID
GROUP BY 
    r.Route_ID, 
    r.Start_Location, 
    r.End_Location, 
    r.Distance_KM, 
    r.Average_Travel_Time_Min;
-- 3.2 Identify 3 routes with the worst efficiency ratio. 
SELECT 
    Route_ID,
    Start_Location,
    End_Location,
    (Distance_KM / Average_Travel_Time_Min) as Efficiency_Ratio
FROM Routes
ORDER BY Efficiency_Ratio ASC
LIMIT 3;
-- 3.3 Find routes with >20% delayed shipments.
SELECT 
    r.Route_ID,
    r.Start_Location,
    r.End_Location,
    COUNT(*) as Total_Shipments,
    SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) as Delayed_Shipments,
    (SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) as Delayed_Percentage
FROM Routes r
JOIN Orders o ON r.Route_ID = o.Route_ID
GROUP BY r.Route_ID, r.Start_Location, r.End_Location
HAVING Delayed_Percentage > 20; 
-- 4.1 Find the top 3 warehouses with the highest average processing time. 
SELECT 
    Warehouse_ID,
    Location,
    Processing_Time_Min
FROM Warehouses
ORDER BY Processing_Time_Min DESC
LIMIT 3;
-- 4.2 Calculate total vs. delayed shipments for each warehouse. 
SELECT 
    w.Warehouse_ID,
    w.Location,
    COUNT(o.Order_ID) as Total_Shipments,
    SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) as Delayed_Shipments,
    (SUM(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) as Delayed_Percentage
FROM Warehouses w
LEFT JOIN Orders o ON w.Warehouse_ID = o.Warehouse_ID
GROUP BY w.Warehouse_ID, w.Location;
-- 4.3 Use CTEs to find bottleneck warehouses where processing time > global average. 
WITH GlobalAverage AS (
    SELECT AVG(Processing_Time_Min) as Global_Avg_Processing_Time
    FROM Warehouses
)
SELECT 
    w.Warehouse_ID,
    w.Location,
    w.Processing_Time_Min,
    g.Global_Avg_Processing_Time
FROM Warehouses w
CROSS JOIN GlobalAverage g
WHERE w.Processing_Time_Min > g.Global_Avg_Processing_Time;
-- 4.4Rank warehouses based on on-time delivery percentage. 
SELECT 
    w.Warehouse_ID,
    w.Location,
    COUNT(o.Order_ID) as Total_Orders,
    SUM(CASE WHEN o.Delivery_Status = 'On Time' THEN 1 ELSE 0 END) as On_Time_Orders,
    (SUM(CASE WHEN o.Delivery_Status = 'On Time' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) as On_Time_Percentage,
    RANK() OVER (ORDER BY (SUM(CASE WHEN o.Delivery_Status = 'On Time' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) DESC) as Warehouse_Rank
FROM Warehouses w
LEFT JOIN Orders o ON w.Warehouse_ID = o.Warehouse_ID
GROUP BY w.Warehouse_ID, w.Location;
-- 5.1 Rank agents (per route) by on-time delivery percentage  
SELECT 
    Agent_ID,
    Route_ID,
    On_Time_Percentage,
    RANK() OVER (PARTITION BY Route_ID ORDER BY On_Time_Percentage DESC) as Rank_Per_Route
FROM deliveryagents; 
-- 5.2 Find agents with on-time % < 80%. 
SELECT 
    Agent_ID,
    Route_ID,
    On_Time_Percentage
FROM deliveryagents
WHERE On_Time_Percentage < 80;
-- 5.3 Compare average speed of top 5 vs bottom 5 agents using subqueries. 

WITH RankedAgents AS (
    SELECT 
        Agent_ID,
        On_Time_Percentage,
        Avg_Speed_KM_HR,
        ROW_NUMBER() OVER (ORDER BY On_Time_Percentage DESC) as top_rank,
        ROW_NUMBER() OVER (ORDER BY On_Time_Percentage ASC) as bottom_rank
    FROM deliveryagents
)
SELECT 
    'Top 5 Agents' as Category,
    AVG(Avg_Speed_KM_HR) as Average_Speed
FROM RankedAgents
WHERE top_rank <= 5

UNION ALL

SELECT 
    'Bottom 5 Agents',
    AVG(Avg_Speed_KM_HR)
FROM RankedAgents
WHERE bottom_rank <= 5;
-- 6.1For each order, list the last checkpoint and time. 
SELECT 
    st1.Order_ID,
    st1.Checkpoint as Last_Checkpoint,
    st1.Checkpoint_Time as Last_Checkpoint_Time
FROM shipment_tracking st1
INNER JOIN (
    SELECT 
        Order_ID,
        MAX(Checkpoint_Time) as Max_Time
    FROM shipment_tracking
    GROUP BY Order_ID
) st2 ON st1.Order_ID = st2.Order_ID AND st1.Checkpoint_Time = st2.Max_Time;
-- 6.2Find the most common delay reasons (excluding None). 
SELECT 
    Delay_Reason,
    COUNT(*) as Frequency
FROM shipment_tracking
WHERE Delay_Reason != 'None'
GROUP BY Delay_Reason
ORDER BY Frequency DESC;
-- 6.3 Identify orders with >2 delayed checkpoints  
SELECT 
    Order_ID,
    COUNT(*) as Delayed_Checkpoints_Count
FROM shipment_tracking
WHERE Delay_Reason != 'None'
GROUP BY Order_ID
HAVING COUNT(*) > 2;
-- 7.1 Average Delivery Delay per Region (Start_Location). 
SELECT 
    r.Start_Location as Region,
    AVG(o.Delay_Days) as Avg_Delay_Days
FROM Orders o
JOIN Routes r ON o.Route_ID = r.Route_ID
WHERE o.Delay_Days > 0
GROUP BY r.Start_Location;
-- 7.2 On-Time Delivery % = (Total On-Time Deliveries / Total Deliveries) * 100.
SELECT 
    (COUNT(CASE WHEN Delivery_Status = 'On Time' THEN 1 END) * 100.0 / COUNT(*)) as On_Time_Delivery_Percentage
FROM Orders; 
--  7.3 Average Traffic Delay per Route. 
SELECT 
    Route_ID,
    Start_Location,
    End_Location,
    AVG(Traffic_Delay_Min) as Avg_Traffic_Delay_Min
FROM Routes
GROUP BY Route_ID, Start_Location, End_Location;















    



    
    

