/*-----------------------------------------------------------------------------
-- 05_JSON_BuildAndFind.sql
--
-- Written By: Andy Yun
-- Created On: 2026-10-05
--
-- Adapted From: Bob Ward, "SQL Server 2025 Unveiled" (Apress), chapter 5
-- https://github.com/microsoft/bobsql (demos/sqlserver2025/json)
--
-- SQL Server 2025 for T-SQL Developers: demo scripts
--
-- Feature : Find it:  JSON_CONTAINS and CREATE JSON INDEX
--           Build it: JSON_OBJECTAGG and JSON_ARRAYAGG (with RETURNING JSON)
--
-- References
-- - Microsoft Learn, JSON_OBJECTAGG:
--   https://learn.microsoft.com/en-us/sql/t-sql/functions/json-objectagg-transact-sql
-- - Microsoft Learn, JSON_ARRAYAGG:
--   https://learn.microsoft.com/en-us/sql/t-sql/functions/json-arrayagg-transact-sql
-- - Microsoft Learn, JSON_CONTAINS:
--   https://learn.microsoft.com/en-us/sql/t-sql/functions/json-contains-transact-sql
-- - Microsoft Learn, CREATE JSON INDEX 
--   https://learn.microsoft.com/en-us/sql/t-sql/statements/create-json-index-transact-sql
-- - Bob Ward, "SQL Server 2025 Unveiled" and his demo repo https://github.com/microsoft/bobsql 
-----------------------------------------------------------------------------*/


USE TSQL2025Demo;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
DROP TABLE IF EXISTS dbo.OrderLines;
DROP TABLE IF EXISTS dbo.OrderDocs;
DROP TABLE IF EXISTS dbo.OrderDocs_Heap;
GO








-------------
-- PART 1: FIND IT
-------------

-----
-- STEP 1: Build 500,000 JSON documents to search
-- DO NOT RUN - pre-executed in 00_Setup
/*
DROP TABLE IF EXISTS dbo.OrderDocs;
*/

CREATE TABLE dbo.OrderDocs (
	OrderID INT NOT NULL,
	Doc JSON NOT NULL,
	CONSTRAINT PK_OrderDocs PRIMARY KEY CLUSTERED (OrderID)
);
GO
/*
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
*/

SELECT
	OrderID,
	Doc
FROM dbo.OrderDocs
WHERE OrderID IN (1, 2, 50, 777)
ORDER BY OrderID;
GO

-- WHAT YOU JUST SAW
--    * 500,000 documents in a native json column, one for every order. 
--
--      Three things are rare on purpose, so that an index has something to do:
--         - "tracking" is unique to each document
--         - "giftNote" exists in only 4 documents (order 1 is one of them)
--         - "chewed-by-dog" is in only 5 documents (order 777 is one)
--    * ABSENT ON NULL leaves "giftNote" out of the other 499,996 documents
--      entirely. JSON_ARRAY skips NULL elements by default, which is how each
--      document ends up with a different number of tags.
-----








-----
-- STEP 2: Three searches with no index
-- DO: 
--     Turn on Include Actual Execution Plan with Ctrl+M
--     Run this step, then read the logical reads on the Messages tab.

SET STATISTICS IO ON;
GO

PRINT '--- Search 1: JSON_VALUE equality on a property ---';
SELECT OrderID
FROM dbo.OrderDocs
WHERE JSON_VALUE(Doc, '$.tracking') = 'TRK000012345';
GO

PRINT '--- Search 2: JSON_CONTAINS inside an array ---';
SELECT OrderID
FROM dbo.OrderDocs
WHERE JSON_CONTAINS(Doc, 'chewed-by-dog', '$.tags[*]') = 1;
GO

PRINT '--- Search 3: JSON_PATH_EXISTS, which documents have a gift note? ---';
SELECT OrderID
FROM dbo.OrderDocs
WHERE JSON_PATH_EXISTS(Doc, '$.giftNote') = 1;
GO

SET STATISTICS IO OFF;
GO

-- WHAT YOU SHOULD SEE
--    * 1 row, 5 rows, and 4 rows.
--    * Every search reads the entire table and opens all 500,000 documents to
--      answer the question. The logical reads are the same for all three,
--      because all three are a clustered index scan.
--    * JSON_CONTAINS is new in 2025. It asks "is this value at this path?" The
--      [*] wildcard means "any element of the array", and it is required when
--      the path points at an array.
--    * Before 2025, the fix was a computed column plus an ordinary index for
--      each property you wanted to search. One property, one column, one
--      index, and it could not reach inside an array.
-----








-----
-- STEP 3: Create the JSON index
-- DO: 
--     Turn OFF Include Actual Execution Plan with Ctrl+M
--     Run this step. The build is single-threaded and offline. 
--     About ~20 seconds
DECLARE @Started DATETIME2(3) = SYSDATETIME();

IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.OrderDocs') AND name = N'JX_OrderDocs_Doc')
	CREATE JSON INDEX JX_OrderDocs_Doc
		ON dbo.OrderDocs (Doc)
		WITH (OPTIMIZE_FOR_ARRAY_SEARCH = ON);

SELECT DATEDIFF(MILLISECOND, @Started, SYSDATETIME()) AS build_ms;
GO

SELECT
	name,
	index_id,
	type,
	type_desc
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'dbo.OrderDocs');

-- Space used by the table and by anything stored on its behalf.
SELECT
	COALESCE(internal_tables.name, OBJECT_NAME(dm_db_partition_stats.object_id)) AS object_name,
	COALESCE(internal_tables.internal_type_desc, N'USER_TABLE') AS object_type,
	dm_db_partition_stats.index_id,
	SUM(dm_db_partition_stats.row_count) AS row_count,
	CAST(SUM(dm_db_partition_stats.used_page_count) * 8 / 1024.0 AS DECIMAL(10, 1)) AS used_mb
FROM sys.dm_db_partition_stats
LEFT OUTER JOIN sys.internal_tables
	ON internal_tables.object_id = dm_db_partition_stats.object_id
WHERE dm_db_partition_stats.object_id = OBJECT_ID(N'dbo.OrderDocs')
	OR internal_tables.parent_id = OBJECT_ID(N'dbo.OrderDocs')
GROUP BY
	COALESCE(internal_tables.name, OBJECT_NAME(dm_db_partition_stats.object_id)),
	COALESCE(internal_tables.internal_type_desc, N'USER_TABLE'),
	dm_db_partition_stats.index_id
ORDER BY
	object_type DESC,
	dm_db_partition_stats.index_id;
GO

-- WHAT YOU SHOULD SEE 
--    * sys.indexes shows a second index with type_desc = JSON.
--    * No FOR clause, so the index covers the whole document: every property
--      at every level. To index only some paths, add FOR ('$.tracking',
--      '$.tags') and so on.
--    * OPTIMIZE_FOR_ARRAY_SEARCH = ON is there for Search 2, which looks
--      inside the "tags" array. It is OFF by default. The slide shows the
--      plain statement; mention the option if you run Search 2.
--    * Last result: the table's own storage (index_id 1) next to the storage
--      the JSON index needed, wherever the engine put it. Indexing every value
--      in every document is not free, in space or in write cost. Say that out
--      loud. (If only one row comes back, the index storage is not exposed
--      where this query looks; skip the size comparison.)
-----








-----
-- STEP 4: The same three searches, now with the index
-- DO: Run this step and compare the logical reads with STEP 7.
SET STATISTICS IO ON;
GO

PRINT '--- Search 1: JSON_VALUE equality on a property ---';
SELECT OrderID
FROM dbo.OrderDocs
WHERE JSON_VALUE(Doc, '$.tracking') = 'TRK000012345';
GO

PRINT '--- Search 2: JSON_CONTAINS inside an array ---';
SELECT OrderID
FROM dbo.OrderDocs
WHERE JSON_CONTAINS(Doc, 'chewed-by-dog', '$.tags[*]') = 1;
GO

PRINT '--- Search 3: JSON_PATH_EXISTS, which documents have a gift note? ---';
SELECT OrderID
FROM dbo.OrderDocs
WHERE JSON_PATH_EXISTS(Doc, '$.giftNote') = 1;
GO

SET STATISTICS IO OFF;
GO

-- WHAT YOU SHOULD SEE
--    * The optimizer decides whether to use the index, and you cannot force it
--      with a hint.
-----







-------------
-- PART 2: BUILD IT
-- Steps 5 - 9
-------------

-----
-- STEP 5: A small relational table to turn into JSON
-- DO: Run this step.
DROP TABLE IF EXISTS dbo.OrderLines;

CREATE TABLE dbo.OrderLines (
	OrderID INT NOT NULL,
	LineNumber TINYINT NOT NULL,
	Sku VARCHAR(20) NOT NULL,
	Qty INT NULL,
	CONSTRAINT PK_OrderLines PRIMARY KEY CLUSTERED (OrderID, LineNumber)
);

INSERT INTO dbo.OrderLines (
	OrderID,
	LineNumber,
	Sku,
	Qty
)
SELECT 1, 1, 'KIBBLE-5LB', 2 UNION ALL
SELECT 1, 2, 'TREATS-BACON', 6 UNION ALL
SELECT 1, 3, 'TOY-SQUEAK', 1 UNION ALL
SELECT 2, 1, 'BALL-TENNIS', 12 UNION ALL
SELECT 2, 2, 'TREATS-BACON', NULL UNION ALL		-- quantity not entered yet
SELECT 3, 1, 'LEASH-6FT', 1;

SELECT
	OrderID,
	LineNumber,
	Sku,
	Qty
FROM dbo.OrderLines
ORDER BY
	OrderID,
	LineNumber;
GO

-- WHAT YOU JUST SAW
--    * Three orders, six lines. The goal is one JSON value per order.
-----








-----
-- STEP 6: The old way to aggregate rows into one JSON object
-- DO: Run this step.
SELECT
	OrderID,
	'{'
		+ STRING_AGG('"' + STRING_ESCAPE(Sku, 'json') + '":' + COALESCE(CAST(Qty AS VARCHAR(12)), 'null'), ',') WITHIN GROUP (ORDER BY LineNumber)
		+ '}' AS lines_the_old_way
FROM dbo.OrderLines
GROUP BY OrderID
ORDER BY OrderID;
GO

-- WHAT YOU JUST SAW
--    * FOR JSON cannot use a column's VALUE as a property NAME, so the usual
--      answer was to glue a JSON string together by hand: quotes, colons,
--      commas, braces, escaping, and a special case for NULL.
--    * It works until someone forgets STRING_ESCAPE.
-----








-----
-- STEP 7: JSON_OBJECTAGG and JSON_ARRAYAGG
-- DO: Run this step.
SELECT
	OrderID,
	JSON_OBJECTAGG(Sku:Qty) AS lines_as_object,
	JSON_OBJECTAGG(Sku:Qty ABSENT ON NULL) AS lines_without_nulls,
	JSON_ARRAYAGG(Sku ORDER BY LineNumber) AS skus_as_array
FROM dbo.OrderLines
GROUP BY OrderID
ORDER BY OrderID;
GO

-- WHAT YOU JUST SAW
--    * JSON_OBJECTAGG() takes key:value and returns one object per group. 
--    * JSON_ARRAYAGG() returns one array per group and has its own ORDER BY.
--
--    * NULL handling is a clause, not a CASE expression. Order 2 has a NULL
--      quantity: the first column keeps it as null (NULL ON NULL is the
--      default for JSON_OBJECTAGG), the second drops the key (ABSENT ON NULL).
--      JSON_ARRAYAGG defaults the other way and skips NULLs.
-----








-----
-- STEP 8: RETURNING JSON gives you the native type, not a string
-- DO: Run this step.
-- What data types come back? Land the result in a temp table and ask tempdb.
DROP TABLE IF EXISTS #TypeCheck;

SELECT
	JSON_OBJECTAGG(Sku:Qty) AS without_returning,
	JSON_OBJECTAGG(Sku:Qty RETURNING JSON) AS with_returning_json
INTO #TypeCheck
FROM dbo.OrderLines
WHERE OrderID = 1;

SELECT
	name AS column_name,
	TYPE_NAME(system_type_id) AS data_type,
	max_length AS max_length_bytes
FROM tempdb.sys.columns
WHERE object_id = OBJECT_ID(N'tempdb..#TypeCheck')
ORDER BY column_id;

DROP TABLE IF EXISTS #TypeCheck;

SELECT
	OrderID,
	JSON_OBJECTAGG(Sku:Qty RETURNING JSON) AS lines_as_json_type
FROM dbo.OrderLines
GROUP BY OrderID
ORDER BY OrderID;
GO

-- WHAT YOU SHOULD SEE
--    * First result: nvarchar (max_length -1, meaning max) without the clause,
--      json with it. Microsoft Learn documents that SELECT ... INTO keeps the
--      json type, which is why this check uses a temp table.
--    * Why it matters: if the result is going into a json column or a json
--      variable, RETURNING JSON skips the trip through a string and the parse
--      on the other side.
-----








-----
-- STEP 9: (Optional) One whole document per order
-- DO: Run this step.
SELECT
	OrderID,
	JSON_OBJECT(
		'orderId': OrderID,
		'lineCount': COUNT(*),
		'lines': JSON_ARRAYAGG(
			JSON_OBJECT('sku': Sku, 'qty': Qty RETURNING JSON)
			ORDER BY LineNumber
			RETURNING JSON
		)
		RETURNING JSON
	) AS order_document
FROM dbo.OrderLines
GROUP BY OrderID
ORDER BY OrderID;
GO

-- WHAT YOU SHOULD SEE
--    * This nesting is not an example from the documentation.
--    * One document per order, with "lines" as an array of objects:
--      {"orderId":1,"lineCount":3,"lines":[{"sku":"KIBBLE-5LB","qty":2}, ...]}
--    * If "lines" comes back as an array of quoted strings full of
--      backslashes, the inner objects were treated as text. Cut this step from
--      the talk.
--    * This is the practical use: an API wants a document, the data lives in
--      tables, and the query builds the document with no string handling.
-----








-----
-- STEP 10: Reset
-- DO: Run this step when you are finished.
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
DROP TABLE IF EXISTS dbo.OrderLines;
DROP TABLE IF EXISTS dbo.OrderDocs;
DROP TABLE IF EXISTS dbo.OrderDocs_Heap;
GO
