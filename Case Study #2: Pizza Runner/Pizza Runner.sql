------------------------
-----DATA CLEANING------
------------------------

--SQL functions: Create temp table, CASE WHEN, TRIM, ALTER TABLE, ALTER data type, filtering using '%'

--TABLE: customer_orders

SELECT order_id, customer_id, pizza_id, 
CASE
	WHEN exclusions IS null OR exclusions LIKE 'null' THEN ' '
	ELSE exclusions
	END AS exclusions,
CASE
	WHEN extras IS NULL or extras LIKE 'null' THEN ' '
	ELSE extras
	END AS extras,
	order_time
INTO #customer_orders
FROM customer_orders

--TABLE: runner_orders

exec sp_help runner_orders

--pickup_time - remove nulls and replace with ' '
--distance - remove km and nulls
--duration - remove minutes and nulls
--cancellation - remove NULL and null and replace with ' ' 

SELECT order_id, runner_id,  
CASE
	WHEN pickup_time LIKE 'null' THEN ' '
	ELSE pickup_time
	END AS pickup_time,
CASE
	WHEN distance LIKE 'null' THEN ' '
	WHEN distance LIKE '%km' THEN TRIM('km' from distance)
	ELSE distance
	END AS distance,
CASE
	WHEN duration LIKE 'null' THEN ' '
	WHEN duration LIKE '%mins' THEN TRIM('mins' from duration)
	WHEN duration LIKE '%minute' THEN TRIM('minute' from duration)
	WHEN duration LIKE '%minutes' THEN TRIM('minutes' from duration)
	ELSE duration
	END AS duration,
CASE
	WHEN cancellation IS NULL or cancellation LIKE 'null' THEN ' '
	ELSE cancellation
	END AS cancellation
INTO #runner_orders
FROM runner_orders

ALTER TABLE #runner_orders
ALTER COLUMN pickup_time DATETIME

ALTER TABLE #runner_orders
ALTER COLUMN distance FLOAT

ALTER TABLE #runner_orders
ALTER COLUMN duration INT


--A. Pizza Metrics
--1. How many pizzas were ordered?

SELECT COUNT(DISTINCT(order_id)) AS no_of_pizzas_ordered
FROM #customer_orders;

--2. How many unique customer orders were made?
SELECT customer_id, COUNT(order_id) AS unique_orders
FROM #customer_orders
GROUP BY customer_id

--3. How many successful orders were delivered by each runner?
SELECT COUNT(order_id) AS successful_orders
FROM #runner_orders
WHERE distance != 0

--4. How many of each type of pizza was delivered?
SELECT pizza_id, COUNT(pizza_id) AS no_of_delivered_pizza
FROM #customer_orders AS c
JOIN #runner_orders AS r
	ON c.order_id = r.order_id
WHERE distance != 0
GROUP BY pizza_id

--5. How many Vegetarian and Meatlovers were ordered by each customer?
SELECT c.customer_id, p.pizza_name, COUNT(p.pizza_name) AS no_of_orders
FROM #customer_orders AS c
JOIN pizza_names AS p
	ON c.pizza_id= p.pizza_id
GROUP BY c.customer_id, p.pizza_name
ORDER BY c.customer_id

--6. What was the maximum number of pizzas delivered in a single order?
WITH tempo AS
(
SELECT c.order_id, COUNT(c.pizza_id) AS no_of_pizzas_per_order
FROM #customer_orders AS c
JOIN #runner_orders AS r
	ON c.order_id = r.order_id
WHERE r.distance != 0
GROUP BY c.order_id
)

SELECT MAX(no_of_pizzas_per_order) AS max_no_of_pizzas_in_single_order
FROM tempo

--7. For each customer, how many delivered pizzas had at least 1 change and how many had no changes?

SELECT c.customer_id,
	SUM(CASE 
		WHEN c.exclusions <> ' ' OR c.extras <> ' ' THEN 1
		ELSE 0
		END) AS with_changes,
	SUM(CASE 
		WHEN c.exclusions IS NULL OR c.extras IS NULL THEN 1 
		ELSE 0
		END) AS no_changes
FROM #customer_orders AS c
JOIN #runner_orders AS r
	ON c.order_id = r.order_id
WHERE r.distance != 0
GROUP BY c.customer_id
ORDER BY c.customer_id

--8. How many pizzas were delivered that had both exclusions and extras?
SET ANSI_NULLS OFF

SELECT c.order_id, 
	SUM(CASE
		WHEN exclusions IS NOT NULL AND extras IS NOT NULL THEN 1
		ELSE 0
		END) AS no_of_pizza_delivered_w_exclusions_extras
FROM #customer_orders AS c
JOIN #runner_orders AS r
	ON c.order_id = r.order_id
WHERE r.distance >= 1 
	AND exclusions <> ' ' 
	AND extras <> ' ' 
GROUP BY c.order_id, c.pizza_id

--9. What was the total volume of pizzas ordered for each hour of the day?
SELECT DATEPART(HOUR, [order_time]) AS hour_of_the_day, COUNT(order_id) AS total_pizzas_ordered
FROM #customer_orders
GROUP BY DATEPART(HOUR, [order_time])

--10. What was the volume of orders for each day of the week?
SELECT DATEPART(DAY, [order_time]) AS day_of_week, COUNT(order_id) AS total_pizzas_ordered
FROM #customer_orders
GROUP BY DATEPART(DAY, [order_time])

--B. Runner and Customer Experience

--1. How many runners signed up for each 1 week period? (i.e. week starts 2021-01-01)
SELECT runner_id,
	CASE
		WHEN registration_date BETWEEN '2021-01-01' AND '2021-01-07' THEN 'Week 1'
		WHEN registration_date BETWEEN '2021-01-08' AND '2021-01-14'THEN 'Week 2'
		ELSE 'Week 3'
		END AS runner_signups
FROM runners
GROUP BY registration_date, runner_id

--2. What was the average time in minutes it took for each runner to arrive at the Pizza Runner HQ to pickup the order?
WITH time_taken AS
(
SELECT r.runner_id, c.order_id, c.order_time, r.pickup_time, DATEDIFF(MINUTE, c.order_time, r.pickup_time) AS mins_taken_to_arrive_HQ
FROM #customer_orders AS c
JOIN #runner_orders AS r
	ON c.order_id = r.order_id
WHERE r.distance != 0
GROUP BY r.runner_id, c.order_id, c.order_time, r.pickup_time
)

SELECT runner_id, AVG(mins_taken_to_arrive_HQ) AS avg_mins_taken_to_arrive_HQ
FROM time_taken
WHERE mins_taken_to_arrive_HQ > 1
GROUP BY runner_id

--3. Is there any relationship between the number of pizzas and how long the order takes to prepare?
WITH prepare_time AS
(
SELECT c.order_id, COUNT(c.order_id) AS no_pizza_ordered, c.order_time, r.pickup_time, DATEDIFF(MINUTE, c.order_time, r.pickup_time) AS time_taken_to_prepare
FROM #customer_orders AS c
JOIN #runner_orders AS r
	ON c.order_id = r.order_id
WHERE r.distance != 0
GROUP BY c.order_id, c.order_time, r.pickup_time
)

SELECT no_pizza_ordered, AVG(time_taken_to_prepare) AS avg_time_to_prepare
FROM prepare_time
WHERE time_taken_to_prepare > 1
GROUP BY no_pizza_ordered

--4. What was the average distance travelled for each customer?
SELECT c.customer_id, AVG(r.distance) AS avg_distance
FROM #customer_orders AS c
JOIN #runner_orders AS r
	ON c.order_id = r.order_id
WHERE duration != 0
GROUP BY c.customer_id

--5. What was the difference between the longest and shortest delivery times for all orders?

WITH time_taken AS
(
SELECT r.runner_id, c.order_id, c.order_time, r.pickup_time, DATEDIFF(MINUTE, c.order_time, r.pickup_time) AS delivery_time
FROM #customer_orders AS c
JOIN #runner_orders AS r
	ON c.order_id = r.order_id
WHERE r.distance != 0
GROUP BY r.runner_id, c.order_id, c.order_time, r.pickup_time
)

SELECT (MAX(delivery_time) - MIN(delivery_time)) AS diff_longest_shortest_delivery_time
FROM time_taken
WHERE delivery_time > 1

--6. What was the average speed for each runner for each delivery and do you notice any trend for these values?
SELECT runner_id, c.order_id, COUNT(c.order_id) AS pizza_count, (distance * 1000) AS distance_meter, duration, ROUND((distance * 1000/duration),2) AS avg_speed
FROM #runner_orders AS r
JOIN #customer_orders AS c
	ON r.order_id = c.order_id
WHERE distance != 0
GROUP BY runner_id, c.order_id, distance, duration
ORDER BY runner_id, pizza_count, avg_speed

--7. What is the successful delivery percentage for each runner?
WITH delivery AS
(
SELECT runner_id, COUNT(order_id) AS total_delivery,
	SUM(CASE
		WHEN distance != 0 THEN 1
		ELSE distance
		END) AS successful_delivery,
	SUM(CASE
		WHEN cancellation LIKE '%Cancel%' THEN 1 
		ELSE cancellation
		END) AS failed_delivery
FROM #runner_orders
GROUP BY runner_id, order_id
)

SELECT runner_id, (SUM(successful_delivery)/SUM(total_delivery)*100) AS successful_delivery_perc
FROM delivery
GROUP BY runner_id
