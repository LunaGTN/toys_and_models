# CHOIX DE LA BASE DE DONNEES
USE toys_and_models ;

# VENTES

# Le nombre de produits vendus par catégorie et par mois, avec comparaison et taux de variation par rapport au même mois de l’année précédente.

WITH aggregated_data AS (
    SELECT 
        YEAR(o.orderDate) AS `YEAR`,
        MONTH(o.orderDate) AS `MONTH_NUMBER`,
        MONTHNAME(o.orderDate) AS `MONTH_NAME`,
        p.productLine AS `CATEGORY`,
        SUM(od.quantityOrdered) AS `TOTAL_QUANTITY_ORDERED`
    FROM 
        orders o
    INNER JOIN orderdetails od ON o.orderNumber = od.orderNumber
    INNER JOIN products p ON od.productCode = p.productCode
    GROUP BY
        YEAR(o.orderDate), MONTH(o.orderDate), MONTHNAME(o.orderDate), p.productLine
)
SELECT 
    `YEAR`,
    `MONTH_NAME`,
    `CATEGORY`,
    `TOTAL_QUANTITY_ORDERED`,
    CASE 
        WHEN LAG(`TOTAL_QUANTITY_ORDERED`, 1) OVER (PARTITION BY `CATEGORY`, `MONTH_NUMBER` ORDER BY `YEAR`) IS NULL 
        THEN NULL
        ELSE 
            100 * ( `TOTAL_QUANTITY_ORDERED` - LAG(`TOTAL_QUANTITY_ORDERED`, 1) OVER (PARTITION BY `CATEGORY`, `MONTH_NUMBER` ORDER BY `YEAR`) ) 
            / LAG(`TOTAL_QUANTITY_ORDERED`, 1) OVER (PARTITION BY `CATEGORY`, `MONTH_NUMBER` ORDER BY `YEAR`)
    END AS `VARIATION_RATE`
FROM 
    aggregated_data
ORDER BY 
    `CATEGORY`;

# FINANCES

# Le chiffre d’affaires des commandes des deux derniers mois par pays

DROP TABLE IF EXISTS recent_months;
CREATE TEMPORARY TABLE recent_months AS
SELECT DISTINCT YEAR(o.orderDate) AS year, MONTH(o.orderDate) AS month
FROM orders o
GROUP BY YEAR(o.orderDate), MONTH(o.orderDate)
ORDER BY YEAR(o.orderDate) DESC, MONTH(o.orderDate) DESC
LIMIT 2;

SELECT
    recent_months.year AS `YEAR`,
    recent_months.month AS `MONTH`,
    c.country AS `COUNTRY`,
    SUM(od.quantityOrdered * od.priceEach) AS `TOTAL SELLS`
FROM
    customers AS c
INNER JOIN orders AS o ON c.customerNumber = o.customerNumber
INNER JOIN orderdetails AS od ON o.orderNumber = od.orderNumber
INNER JOIN recent_months ON YEAR(o.orderDate) = recent_months.year AND MONTH(o.orderDate) = recent_months.month
GROUP BY
    `COUNTRY`, `YEAR`, `MONTH`
ORDER BY
    `TOTAL SELLS` DESC;

# Les commandes qui n’ont pas encore été payées

# Le code ci-apres donne les clients qui ont des impayés et non les commandes qui n ont pas encore été payées

WITH customers_payments_cte AS (
	SELECT
		p.customerNumber AS `CUSTOMER NUMBER_PYM`,
		SUM(p.amount) AS `AMOUNT PAID`
	FROM payments p
	GROUP BY p.customerNumber
), customers_orders_cte AS (
SELECT 
	o.customerNumber AS `CUSTOMER NUMBER_O`,
	SUM(od.quantityOrdered * od.priceEach) AS `AMOUNT ORDERED`
FROM
	orderdetails od
JOIN orders o ON o.orderNumber = od.orderNumber
WHERE
	o.status != 'Cancelled'
AND 
	o.customerNumber IN (
						SELECT
							p.customerNumber
						FROM
							payments p
						)
GROUP BY
	o.customerNumber
)
SELECT
	*,
	(`AMOUNT PAID` - `AMOUNT ORDERED`) AS `AMOUNT DUE`
FROM customers_payments_cte JOIN customers_orders_cte
WHERE `CUSTOMER NUMBER_PYM` = `CUSTOMER NUMBER_O`
AND (`AMOUNT PAID` - `AMOUNT ORDERED`) < 0
ORDER BY `AMOUNT DUE` ASC
; 
 
# LOGISTIQUE

# Le stock des 5 produits les plus commandés.

select p.productName,
p.quantityInStock
from products as p
inner join orderDetails as od 
on p.productCode = od.productCode
group by od.productCode
order by sum(quantityOrdered) desc
limit 5;

# RH

# Chaque mois, les 2 vendeurs ayant réalisé le plus de chiffre d’affaires. 

WITH MonthlySales AS (
    SELECT
    	c.salesRepEmployeeNumber AS `EMPLOYEE_ID`,
        CONCAT(e.firstName, ' ', e.lastName) AS `SALESPERSON`,
        DATE_FORMAT(o.orderDate, '%Y-%m') AS `SALE_MONTH`,
        SUM(od.quantityOrdered * od.priceEach) AS `TOTAL_SALES`
    FROM
        employees e
    INNER JOIN customers c ON e.employeeNumber = c.salesRepEmployeeNumber
    INNER JOIN orders o ON c.customerNumber = o.customerNumber
    INNER JOIN orderdetails od ON o.orderNumber = od.orderNumber
    GROUP BY
        `SALESPERSON`, `SALE_MONTH`, c.salesRepEmployeeNumber
)
SELECT
    `SALE_MONTH`,
    `SALESPERSON`,
    `EMPLOYEE_ID`,
    `TOTAL_SALES`
FROM (
    SELECT
        `SALE_MONTH`,
        `SALESPERSON`,
        `EMPLOYEE_ID`,
        `TOTAL_SALES`,
        ROW_NUMBER() OVER (PARTITION BY `SALE_MONTH` ORDER BY `TOTAL_SALES` DESC) AS sales_rank
    FROM
        MonthlySales
) AS ranked_sales
WHERE
    sales_rank <= 2
ORDER BY
    YEAR(`SALE_MONTH`) DESC,
    `SALE_MONTH` DESC,
    `TOTAL_SALES` DESC;

# KPI additionels

# NB de commandes par employés par agence 

select *, floor(nb_commandes/nb_employees) as nb_cde_per_employe from
(SELECT 
    off.officeCode, 
    off.country, 
    (SELECT COUNT(DISTINCT e.employeeNumber) 
     FROM employees e 
     WHERE e.officeCode = off.officeCode) AS nb_employees,
    COUNT(o.orderNumber) AS nb_commandes
FROM offices off
LEFT JOIN customers c ON c.salesRepEmployeeNumber IN (SELECT e.employeeNumber FROM employees e WHERE e.officeCode = off.officeCode)
LEFT JOIN orders o ON c.customerNumber = o.customerNumber
GROUP BY off.officeCode, off.city, off.country) as a
order by nb_cde_per_employe desc;

# Délais moyen de traitement des commandes

SELECT
	o.orderNumber AS `ORDER NUMBER`,
	o.orderDate AS `ORDER DATE`,
	o.shippedDate AS `SHIPPED DATE`,
    AVG(DATEDIFF(o.shippedDate, o.orderDate)) AS `AVERAGE ORDER PROCESSING TIME`
FROM
    products p
INNER JOIN
    orderdetails od ON p.productCode = od.productCode
INNER JOIN
    orders o ON od.orderNumber = o.orderNumber
WHERE
    o.shippedDate IS NOT NULL
GROUP BY
    `ORDER NUMBER`;