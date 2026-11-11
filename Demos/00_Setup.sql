/*-----------------------------------------------------------------------------
-- 00_Setup.sql
--
-- Written By: Andy Yun
-- Created On: 2026-10-05
--
-- SQL Server 2025 for T-SQL Developers: demo scripts
--
-- Purpose : Build the junk database that every demo script uses.
-- Creates : Database TSQL2025Demo with two tables:
--             dbo.Customers  1,000,000 rows
--             dbo.Orders       500,000 rows
--
-- Script index (each demo needs only this setup script; none of them depend
-- on each other):
--   01_Regex.sql                      
--   02_FuzzyStringMatching.sql        
--   03_SmallTSQLAdditions.sql         
--   04_JSON_NativeType.sql            
--   05_JSON_BuildAndFind.sql          
--   06_OPPO.sql                       
--   07_OptimizedLocking.sql           
--   07_OptimizedLocking_Window2.sql   
--   99_Cleanup.sql                    
--
-- Design notes
-- - All data is generated with modulo arithmetic, never with NEWID() or
--   RAND(), so every rebuild produces identical rows and the row counts
--   quoted in the demo scripts stay true.
-- - The database uses a Windows collation (Latin1_General_100_CI_AS) on
--   purpose. The fuzzy matching functions do not support the non-binary SQL_
--   collations, and SQL_Latin1_General_CP1_CI_AS is still the default server
--   collation on a US English install.
--   https://learn.microsoft.com/en-us/sql/relational-databases/fuzzy-string-match/overview
-----------------------------------------------------------------------------*/





-----
-- STEP 1: Drop and re-create the database
-- DO: Run this step. Close other query windows that are using TSQL2025Demo
--     first, or expect them to be disconnected.
USE master;
GO

IF DB_ID(N'TSQL2025Demo') IS NOT NULL
BEGIN
	ALTER DATABASE TSQL2025Demo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE TSQL2025Demo;
END;
GO

CREATE DATABASE TSQL2025Demo COLLATE Latin1_General_100_CI_AS;
GO

-- WHAT THAT DID
--    * USE master first: a database cannot be dropped by a session that is
--      sitting in it.
--    * SINGLE_USER WITH ROLLBACK IMMEDIATE rolls back and disconnects everyone
--      else, so the DROP cannot be blocked by a forgotten query window.
--    * CREATE DATABASE uses the instance default file locations. No paths to
--      edit.
-----








-----
-- STEP 2: Set the database options the demos expect
-- DO: Run this step.
ALTER DATABASE TSQL2025Demo SET RECOVERY SIMPLE;
ALTER DATABASE TSQL2025Demo SET COMPATIBILITY_LEVEL = 170;
ALTER DATABASE TSQL2025Demo SET QUERY_STORE = ON (
	OPERATION_MODE = READ_WRITE,
	QUERY_CAPTURE_MODE = ALL,
	DATA_FLUSH_INTERVAL_SECONDS = 60
);
GO




-----
-- Pre-size the files so the data load is not interrupted by autogrowth.
-- sys.master_files reports size in 8 KB pages: 65,536 pages = 512 MB.
DECLARE @SQL NVARCHAR(MAX);

SELECT @SQL = STRING_AGG(
	CAST(N'ALTER DATABASE TSQL2025Demo MODIFY FILE (NAME = ' + QUOTENAME(name) + N', SIZE = 512MB, FILEGROWTH = 128MB);' AS NVARCHAR(MAX)),
	NCHAR(10)
)
FROM sys.master_files
WHERE database_id = DB_ID(N'TSQL2025Demo')
	AND size < 65536;

IF @SQL IS NOT NULL
	EXEC sys.sp_executesql @SQL;
GO

-- WHAT THAT DID
--    * Compatibility level 170 is the "COMPAT 170" badge in the deck.
--      REGEXP_LIKE, the two regex table-valued functions, and optional
--      parameter plan optimization all need it.
--    * Query Store is on with QUERY_CAPTURE_MODE = ALL. The default mode
--      (AUTO) ignores queries that run only a few times, which describes every
--      query in a demo.
--    * Everything else is left at its default. That matters: optimized
--      locking, accelerated database recovery, read committed snapshot,
--      optimized sp_executesql, and preview features are all OFF in a new
--      database. The demo scripts turn on what they need and put it back.
-----








-----
-- STEP 3: Create and load dbo.Customers (1,000,000 rows)
-- DO: Run this step. It takes the longest of any step in this file.
USE TSQL2025Demo;
GO

DROP TABLE IF EXISTS dbo.Customers;

CREATE TABLE dbo.Customers (
	CustomerID INT NOT NULL,
	FirstName VARCHAR(30) NOT NULL,
	LastName VARCHAR(30) NOT NULL,
	City VARCHAR(30) NOT NULL,
	StateCode CHAR(2) NOT NULL,
	Phone VARCHAR(25) NULL,
	Email VARCHAR(100) NULL,
	CreatedDate DATE NOT NULL,
	CONSTRAINT PK_Customers PRIMARY KEY CLUSTERED (CustomerID)
);
GO

WITH Numbers_CTE (N) AS (
	SELECT CAST(value AS INT)
	FROM GENERATE_SERIES(1, 1000000)
), FirstNames_CTE (ID, FirstName) AS (
	SELECT 0, 'Sebastian' UNION ALL
	SELECT 1, 'Olivia' UNION ALL
	SELECT 2, 'Liam' UNION ALL
	SELECT 3, 'Emma' UNION ALL
	SELECT 4, 'Noah' UNION ALL
	SELECT 5, 'Ava' UNION ALL
	SELECT 6, 'Mason' UNION ALL
	SELECT 7, 'Sophia' UNION ALL
	SELECT 8, 'Lucas' UNION ALL
	SELECT 9, 'Mia' UNION ALL
	SELECT 10, 'Ethan' UNION ALL
	SELECT 11, 'Isabella' UNION ALL
	SELECT 12, 'Logan' UNION ALL
	SELECT 13, 'Amelia' UNION ALL
	SELECT 14, 'James' UNION ALL
	SELECT 15, 'Harper' UNION ALL
	SELECT 16, 'Elijah' UNION ALL
	SELECT 17, 'Evelyn' UNION ALL
	SELECT 18, 'Oliver' UNION ALL
	SELECT 19, 'Abigail' UNION ALL
	SELECT 20, 'Henry' UNION ALL
	SELECT 21, 'Ella' UNION ALL
	SELECT 22, 'Jack' UNION ALL
	SELECT 23, 'Scarlett' UNION ALL
	SELECT 24, 'Wyatt'
), TailNames_CTE (ID, LastName) AS (
	SELECT 0, 'Anderson' UNION ALL
	SELECT 1, 'Baker' UNION ALL
	SELECT 2, 'Carter' UNION ALL
	SELECT 3, 'Davis' UNION ALL
	SELECT 4, 'Edwards' UNION ALL
	SELECT 5, 'Foster' UNION ALL
	SELECT 6, 'Garcia' UNION ALL
	SELECT 7, 'Hughes' UNION ALL
	SELECT 8, 'Iverson' UNION ALL
	SELECT 9, 'Jackson' UNION ALL
	SELECT 10, 'Kim' UNION ALL
	SELECT 11, 'Lopez' UNION ALL
	SELECT 12, 'Martinez' UNION ALL
	SELECT 13, 'Nguyen' UNION ALL
	SELECT 14, 'Ortiz' UNION ALL
	SELECT 15, 'Patel' UNION ALL
	SELECT 16, 'Quinn' UNION ALL
	SELECT 17, 'Rivera' UNION ALL
	SELECT 18, 'Singh' UNION ALL
	SELECT 19, 'Turner' UNION ALL
	SELECT 20, 'Ueda' UNION ALL
	SELECT 21, 'Vargas' UNION ALL
	SELECT 22, 'Walker' UNION ALL
	SELECT 23, 'Xu' UNION ALL
	SELECT 24, 'Young' UNION ALL
	SELECT 25, 'Zimmerman' UNION ALL
	SELECT 26, 'Abbott' UNION ALL
	SELECT 27, 'Bennett' UNION ALL
	SELECT 28, 'Chen' UNION ALL
	SELECT 29, 'Diaz' UNION ALL
	SELECT 30, 'Ellis' UNION ALL
	SELECT 31, 'Flores' UNION ALL
	SELECT 32, 'Grant' UNION ALL
	SELECT 33, 'Hayes' UNION ALL
	SELECT 34, 'Ingram' UNION ALL
	SELECT 35, 'Jensen' UNION ALL
	SELECT 36, 'Keller' UNION ALL
	SELECT 37, 'Lambert' UNION ALL
	SELECT 38, 'Moreno' UNION ALL
	SELECT 39, 'Novak'
), Cities_CTE (ID, City, StateCode) AS (
	SELECT 0, 'Arlington', 'MA' UNION ALL
	SELECT 1, 'Boston', 'MA' UNION ALL
	SELECT 2, 'Waltham', 'MA' UNION ALL
	SELECT 3, 'Cambridge', 'MA' UNION ALL
	SELECT 4, 'Somerville', 'MA' UNION ALL
	SELECT 5, 'Worcester', 'MA' UNION ALL
	SELECT 6, 'Providence', 'RI' UNION ALL
	SELECT 7, 'Hartford', 'CT' UNION ALL
	SELECT 8, 'Portland', 'ME' UNION ALL
	SELECT 9, 'Manchester', 'NH' UNION ALL
	SELECT 10, 'Burlington', 'VT' UNION ALL
	SELECT 11, 'Albany', 'NY' UNION ALL
	SELECT 12, 'Chicago', 'IL' UNION ALL
	SELECT 13, 'Seattle', 'WA' UNION ALL
	SELECT 14, 'Austin', 'TX' UNION ALL
	SELECT 15, 'Denver', 'CO' UNION ALL
	SELECT 16, 'Atlanta', 'GA' UNION ALL
	SELECT 17, 'Phoenix', 'AZ' UNION ALL
	SELECT 18, 'Portland', 'OR' UNION ALL
	SELECT 19, 'Orlando', 'FL'
)
INSERT INTO dbo.Customers WITH (TABLOCK) (
	CustomerID,
	FirstName,
	LastName,
	City,
	StateCode,
	Phone,
	Email,
	CreatedDate
)
SELECT
	Numbers_CTE.N,
	FirstNames_CTE.FirstName,
	CustomerLastName.LastName,
	Cities_CTE.City,
	Cities_CTE.StateCode,
	CustomerPhone.Phone,
	CASE
		WHEN Numbers_CTE.N % 997 = 0 THEN REPLACE(CustomerEmail.EmailRaw, '@', ' at ')
		WHEN Numbers_CTE.N % 991 = 0 THEN LEFT(CustomerEmail.EmailRaw, CHARINDEX('@', CustomerEmail.EmailRaw)) + 'nodots'
		ELSE CustomerEmail.EmailRaw
	END,
	DATEADD(DAY, -(Numbers_CTE.N % 3650), CAST('2026-10-01' AS DATE))
FROM Numbers_CTE
INNER JOIN FirstNames_CTE
	ON FirstNames_CTE.ID = (Numbers_CTE.N * 3) % 25
INNER JOIN TailNames_CTE
	ON TailNames_CTE.ID = (Numbers_CTE.N / 100) % 40
INNER JOIN Cities_CTE
	ON Cities_CTE.ID = (Numbers_CTE.N * 7) % 20
-- Last name: three very common names, a long tail, and one rare name.
CROSS APPLY (
	SELECT
		CASE
			WHEN Numbers_CTE.N % 100000 = 4242 THEN 'Yun'		-- exactly 10 rows
			WHEN Numbers_CTE.N % 100 < 30 THEN 'Smith'		-- 30 percent
			WHEN Numbers_CTE.N % 100 < 45 THEN 'Johnson'		-- 15 percent
			WHEN Numbers_CTE.N % 100 < 55 THEN 'Williams'		-- 10 percent
			ELSE TailNames_CTE.LastName				-- the other 45 percent
		END AS LastName
) AS CustomerLastName
-- Phone number building blocks: an area code and a 4-digit line number.
CROSS APPLY (
	SELECT
		CHOOSE(Numbers_CTE.N % 8 + 1, '617', '781', '339', '857', '508', '978', '413', '774') AS Area,
		RIGHT('0000' + CAST(Numbers_CTE.N % 10000 AS VARCHAR(4)), 4) AS Line
) AS PhoneParts
-- Phone: five tidy formats (95 percent of rows) and five kinds of junk.
CROSS APPLY (
	SELECT
		CASE
			WHEN Numbers_CTE.N % 20 < 10 THEN '(' + PhoneParts.Area + ') 555-' + PhoneParts.Line
			WHEN Numbers_CTE.N % 20 < 14 THEN PhoneParts.Area + '-555-' + PhoneParts.Line
			WHEN Numbers_CTE.N % 20 < 16 THEN PhoneParts.Area + '.555.' + PhoneParts.Line
			WHEN Numbers_CTE.N % 20 < 18 THEN PhoneParts.Area + '555' + PhoneParts.Line
			WHEN Numbers_CTE.N % 20 = 18 THEN PhoneParts.Area + ' 555 ' + PhoneParts.Line
			ELSE
				CASE (Numbers_CTE.N / 20) % 5
					WHEN 0 THEN '555-' + PhoneParts.Line
					WHEN 1 THEN SUBSTRING(PhoneParts.Area, 1, 1) + '-' + SUBSTRING(PhoneParts.Area, 2, 1) + '-' + SUBSTRING(PhoneParts.Area, 3, 1) + '-5-5-5-' + PhoneParts.Line
					WHEN 2 THEN 'call the front desk'
					WHEN 3 THEN PhoneParts.Area + '-555-' + PhoneParts.Line + ' x12'
					ELSE NULL
				END
		END AS Phone
) AS CustomerPhone
CROSS APPLY (
	SELECT
		LOWER(FirstNames_CTE.FirstName + '.' + CustomerLastName.LastName) + CAST(Numbers_CTE.N AS VARCHAR(10)) + '@'
			+ CHOOSE(Numbers_CTE.N % 5 + 1, 'example.com', 'example.org', 'example.net', 'contoso.com', 'fabrikam.com') AS EmailRaw
) AS CustomerEmail;
GO

CREATE NONCLUSTERED INDEX IX_Customers_LastName
	ON dbo.Customers (LastName)
	INCLUDE (FirstName, City);
GO

-- WHAT THAT DID
--    * GENERATE_SERIES (SQL Server 2022 and later) supplies the numbers 1 to
--      1,000,000. Every column is derived from that number, which is what
--      makes the data repeatable.
--    * LastName is skewed on purpose: 'Smith' is 300,000 rows and 'Yun' is 10.
--      The OPPO demo and the regex index demo both need a value that is cheap
--      to seek and a table that is expensive to scan.
--    * Phone is messy on purpose. Of every 20 rows, 19 hold a 10-digit US
--      number in one of five formats. The 20th holds junk: 7 digits, digits
--      separated by too many dashes, free text, an extension, or NULL (10,000
--      rows each). The regex demo cleans this up.
--    * A few Email values are broken as well (about 1 in 1,000 has no @, and
--      about 1 in 1,000 has no dot after the @).
--    * IX_Customers_LastName covers the queries in the OPPO and regex demos,
--      so a seek on LastName never has to visit the clustered index.
-----








-----
-- STEP 4: Create and load dbo.Orders (500,000 rows)
-- DO: Run this step.
USE TSQL2025Demo;
GO

DROP TABLE IF EXISTS dbo.Orders;

CREATE TABLE dbo.Orders (
	OrderID INT NOT NULL,
	CustomerID INT NOT NULL,
	OrderDate DATE NOT NULL,
	OrderStatus VARCHAR(12) NOT NULL,
	Amount DECIMAL(10, 2) NOT NULL,
	TrackingNumber CHAR(12) NOT NULL,
	CONSTRAINT PK_Orders PRIMARY KEY CLUSTERED (OrderID)
);
GO

WITH Numbers_CTE (N) AS (
	SELECT CAST(value AS INT)
	FROM GENERATE_SERIES(1, 500000)
)
INSERT INTO dbo.Orders WITH (TABLOCK) (
	OrderID,
	CustomerID,
	OrderDate,
	OrderStatus,
	Amount,
	TrackingNumber
)
SELECT
	N,
	(N * 37) % 1000000 + 1,
	DATEADD(DAY, -(N % 1825), CAST('2026-10-01' AS DATE)),
	CASE
		WHEN N % 20 < 12 THEN 'shipped'
		WHEN N % 20 < 16 THEN 'delivered'
		WHEN N % 20 < 18 THEN 'processing'
		WHEN N % 20 = 18 THEN 'cancelled'
		ELSE 'returned'
	END,
	CAST(5 + (N % 20000) / 100.0 AS DECIMAL(10, 2)),
	'TRK' + RIGHT('000000000' + CAST(N AS VARCHAR(9)), 9)
FROM Numbers_CTE;
GO

-- WHAT THAT DID
--    * OrderID is the clustered primary key, 1 to 500,000 with no gaps. The
--      optimized locking demo relies on that to update "the first 10,000
--      orders" and "the very last order".
--    * TrackingNumber is unique and has NO index, on purpose. The lock after
--      qualification demo needs an UPDATE that has to scan to find its row.
-----








-----
-- STEP 5: Refresh statistics and confirm the result
-- DO: Run this step and check the two result sets.
USE TSQL2025Demo;
GO

UPDATE STATISTICS dbo.Customers WITH FULLSCAN;
UPDATE STATISTICS dbo.Orders WITH FULLSCAN;
GO

SELECT
	SERVERPROPERTY('ProductVersion') AS product_version,
	SERVERPROPERTY('ProductUpdateLevel') AS update_level,
	SERVERPROPERTY('Edition') AS edition,
	name AS database_name,
	compatibility_level,
	collation_name,
	recovery_model_desc,
	is_query_store_on,
	is_accelerated_database_recovery_on,
	is_optimized_locking_on,
	is_read_committed_snapshot_on
FROM sys.databases
WHERE name = N'TSQL2025Demo';

SELECT
	(SELECT COUNT(*) FROM dbo.Customers) AS customers,
	(SELECT COUNT(*) FROM dbo.Customers WHERE LastName = 'Smith') AS smiths,
	(SELECT COUNT(*) FROM dbo.Customers WHERE LastName = 'Yun') AS yuns,
	(SELECT COUNT(*) FROM dbo.Orders) AS orders;
GO

-- WHAT YOU SHOULD SEE
--    * First result: compatibility_level 170, Query Store on, and the three
--      locking-related flags all 0.
--    * The edition column doubles as a talking point for slide 16: it shows
--      whether this instance is the Enterprise Developer edition or the new
--      Standard Developer edition (free, with the Standard feature set).
--    * update_level shows the cumulative update. The deck recommends CU9 or
--      later before turning on optimized locking.
--    * Second result: 1,000,000 customers, 300,000 Smiths, 10 Yuns, 500,000
--      orders. If your numbers differ, stop and rerun this script before
--      rehearsing anything else.
-----







-----
-- STEP 6: Build 500,000 JSON documents to search
-- DO: Run this step. Takes ~30 seconds
DROP TABLE IF EXISTS dbo.OrderDocs;

CREATE TABLE dbo.OrderDocs (
	OrderID INT NOT NULL,
	Doc JSON NOT NULL,
	CONSTRAINT PK_OrderDocs PRIMARY KEY CLUSTERED (OrderID)
);
GO

INSERT INTO dbo.OrderDocs WITH (TABLOCK) (
	OrderID,
	Doc
)
SELECT
	OrderID,
	JSON_OBJECT(
		'orderId': OrderID,
		'status': OrderStatus,
		'total': Amount,
		'tracking': TrackingNumber,
		'giftNote': CASE WHEN OrderID % 125000 = 1 THEN 'Happy birthday, Sebastian!' END,
		'tags': JSON_ARRAY(
			CASE WHEN OrderID % 2 = 0 THEN 'web' ELSE 'phone' END,
			CASE WHEN OrderID % 10 = 0 THEN 'gift' END,
			CASE WHEN OrderID % 50 = 0 THEN 'rush' END,
			CASE WHEN OrderID % 100000 = 777 THEN 'chewed-by-dog' END
		)
		ABSENT ON NULL
		RETURNING JSON
	)
FROM dbo.Orders;
GO

SELECT
	OrderID,
	Doc
FROM dbo.OrderDocs
WHERE OrderID IN (1, 2, 50, 777)
ORDER BY OrderID;
GO

-- WHAT YOU JUST SAW
--    * 500,000 documents in a native json column, one for every order. Three
--      things are rare on purpose, so that an index has something to do:
--        "tracking"  is unique to each document
--        "giftNote"  exists in only 4 documents (order 1 is one of them)
--        the tag "chewed-by-dog" is in only 5 documents (order 777 is one)
--    * ABSENT ON NULL leaves "giftNote" out of the other 499,996 documents
--      entirely. JSON_ARRAY skips NULL elements by default, which is how each
--      document ends up with a different number of tags.
--    * The table has a clustered primary key. A JSON index requires one.
-----