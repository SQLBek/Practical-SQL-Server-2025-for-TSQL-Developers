/*-----------------------------------------------------------------------------
-- 04_JSON_NativeType.sql
--
-- Written By: Andy Yun
-- Created On: 2026-10-05
--
-- Adapted From: Bob Ward, "SQL Server 2025 Unveiled" (Apress), chapter 5
-- https://github.com/microsoft/bobsql (demos/sqlserver2025/json)
--
-- SQL Server 2025 for T-SQL Developers: demo scripts
--
-- Feature : The native json data type and its modify method
--
-- References
-- - Microsoft Learn, json data type (storage, conversion, modify method,
--   ALTER TABLE):
--   https://learn.microsoft.com/en-us/sql/t-sql/data-types/json-data-type
-- - Microsoft Learn, JSON_VALUE (RETURNING clause):
--   https://learn.microsoft.com/en-us/sql/t-sql/functions/json-value-transact-sql
-- - Microsoft Learn, JSON data in SQL Server 
--   https://learn.microsoft.com/en-us/sql/relational-databases/json/json-data-sql-server
-- - Bob Ward, "SQL Server 2025 Unveiled" (Apress) and his demo repo https://github.com/microsoft/bobsql 
-----------------------------------------------------------------------------*/


USE TSQL2025Demo;
GO

IF @@TRANCOUNT > 0
	ROLLBACK TRANSACTION;

DROP TABLE IF EXISTS dbo.OrderDocs_Text;
DROP TABLE IF EXISTS dbo.OrderDocs_JSON;
DROP TABLE IF EXISTS dbo.OrderDocs_Alter;
GO









-----
-- STEP 1: Faux JSON in a trench coat
-- DO: Run this step. It builds 100,000 JSON documents the pre-2025 way.
DROP TABLE IF EXISTS dbo.OrderDocs_Text;

CREATE TABLE dbo.OrderDocs_Text (
	OrderID INT NOT NULL,
	Doc NVARCHAR(MAX) NOT NULL,
	CONSTRAINT PK_OrderDocs_Text PRIMARY KEY CLUSTERED (OrderID),
	CONSTRAINT CK_OrderDocs_Text_IsJson CHECK (ISJSON(Doc) = 1)
);
GO

INSERT INTO dbo.OrderDocs_Text WITH (TABLOCK) (
	OrderID,
	Doc
)
SELECT
	Orders.OrderID,
	JSON_OBJECT(
		'orderId': Orders.OrderID,
		-- Order 42 is the one the slides update. Start it as
		-- 'processing' so that the change in STEP 6 is visible.
		'status': CASE WHEN Orders.OrderID = 42 THEN 'processing' ELSE Orders.OrderStatus END,
		'orderDate': Orders.OrderDate,
		'total': Orders.Amount,
		'tracking': Orders.TrackingNumber,
		'customer': JSON_OBJECT(
			'id': Customers.CustomerID,
			'name': Customers.FirstName + ' ' + Customers.LastName,
			'city': Customers.City,
			'state': Customers.StateCode
		)
	)
FROM dbo.Orders
INNER JOIN dbo.Customers
	ON Customers.CustomerID = Orders.CustomerID
WHERE Orders.OrderID <= 100000;
GO

SELECT TOP 3
	OrderID,
	Doc
FROM dbo.OrderDocs_Text
ORDER BY OrderID;
GO

-- WHAT YOU JUST SAW
--    * An nvarchar(max) column with an ISJSON check constraint. 
--      To the engine it is a string. It gets parsed again every time a JSON 
--      function touches it.
--    * JSON_OBJECT (SQL Server 2022) built the documents, including the nested
--      customer object.
-----








-----
-- STEP 2: The same documents in a real json column
-- DO: Run this step.
DROP TABLE IF EXISTS dbo.OrderDocs_JSON;

CREATE TABLE dbo.OrderDocs_JSON (
	OrderID INT NOT NULL,
	Doc JSON NOT NULL,
	CONSTRAINT PK_OrderDocs_JSON PRIMARY KEY CLUSTERED (OrderID)
);
GO

INSERT INTO dbo.OrderDocs_JSON WITH (TABLOCK) (
	OrderID,
	Doc
)
SELECT
	OrderID,
	CAST(Doc AS JSON)
FROM dbo.OrderDocs_Text;
GO

SELECT TOP 3
	OrderID,
	Doc
FROM dbo.OrderDocs_JSON
ORDER BY OrderID;
GO

-- WHAT YOU JUST SAW
--    * Same data, but the column type is json. No check constraint, because
--      the type is the constraint.
--    * The documents look the same in the grid. Underneath, they are stored in
--      a parsed binary format, not as text.
--    * The CAST is there to make the conversion visible. A string is parsed
--      and validated once, on the way in, and never again.
-----








-----
-- STEP 3: Both tables reject bad JSON, in different ways
-- DO: Run this step. Both inserts are expected to fail; the errors come back
--     as result sets.
BEGIN TRY
	INSERT INTO dbo.OrderDocs_Text (
		OrderID,
		Doc
	)
	SELECT -1, N'{"status": oops}';

	SELECT 'The row was inserted. That was not supposed to happen.' AS text_table_result;
END TRY
BEGIN CATCH
	SELECT
		'nvarchar(max) + ISJSON' AS attempt,
		ERROR_NUMBER() AS error_number,
		ERROR_MESSAGE() AS error_message;
END CATCH;

BEGIN TRY
	-- Dynamic SQL, so that the error is caught whether the engine rejects the
	-- literal when it compiles the statement or when it runs it.
	EXEC (N'INSERT INTO dbo.OrderDocs_JSON (OrderID, Doc) SELECT -1, ''{"status": oops}'';');

	SELECT 'The row was inserted. That was not supposed to happen.' AS json_table_result;
END TRY
BEGIN CATCH
	SELECT
		'json column' AS attempt,
		ERROR_NUMBER() AS error_number,
		ERROR_MESSAGE() AS error_message;
END CATCH;
GO

-- WHAT YOU SHOULD SEE
--    * nvarchar(max): error 547, a check constraint violation. It tells you
--      the constraint failed, and nothing about why.
--    * json: JSON parsing error 13609 that points at the unexpected character and
--      its position. 
--    * If someone forgets the ISJSON constraint on the nvarchar(max) version,
--      the bad document goes in and you find out at read time.
-----








-----
-- STEP 4: (Optional) How much space did each version take?
-- DO: Run this step.
SELECT
	OBJECT_NAME(object_id) AS table_name,
	SUM(row_count) AS row_count,
	SUM(used_page_count) AS used_pages,
	CAST(SUM(used_page_count) * 8 / 1024.0 AS DECIMAL(10, 1)) AS used_mb
FROM sys.dm_db_partition_stats
WHERE object_id IN (OBJECT_ID(N'dbo.OrderDocs_Text'), OBJECT_ID(N'dbo.OrderDocs_JSON'))
	AND index_id = 1
GROUP BY object_id
ORDER BY table_name;
GO

-- WHAT YOU SHOULD SEE
--    * The json table is smaller than the nvarchar(max) table for the same 100,000 
--      documents.
--    * Two reasons. nvarchar spends two bytes on every character of mostly
--      ASCII text. And the json type stores numbers and structure in binary
--      form, with strings in UTF-8.
--    * Bob Ward's book cites a test by Daniel Hutmacher showing about 50
--      percent savings. 
-----








-----
-- STEP 5: JSON_VALUE gains a RETURNING clause to adjust datatype inline
-- DO: Run this step.
SELECT TOP 3
	OrderID,
	JSON_VALUE(Doc, '$.customer.name') AS customer_name,
	JSON_VALUE(Doc, '$.total') AS total_as_text,
	JSON_VALUE(Doc, '$.total' RETURNING DECIMAL(10, 2)) AS total_as_decimal,
	JSON_VALUE(Doc, '$.orderDate' RETURNING DATE) AS order_date_as_date
FROM dbo.OrderDocs_JSON
ORDER BY OrderID;




-----
-- What data types came back? Land one row in a temp table and ask tempdb.
DROP TABLE IF EXISTS #TypeCheck;

SELECT TOP 1
	JSON_VALUE(Doc, '$.total') AS total_as_text,
	JSON_VALUE(Doc, '$.total' RETURNING DECIMAL(10, 2)) AS total_as_decimal,
	JSON_VALUE(Doc, '$.orderDate' RETURNING DATE) AS order_date_as_date
INTO #TypeCheck
FROM dbo.OrderDocs_JSON
ORDER BY OrderID;

SELECT
	name AS column_name,
	TYPE_NAME(system_type_id) AS data_type,
	max_length AS max_length_bytes,
	[precision],
	scale
FROM tempdb.sys.columns
WHERE object_id = OBJECT_ID(N'tempdb..#TypeCheck')
ORDER BY column_id;

DROP TABLE IF EXISTS #TypeCheck;
GO

-- WHAT YOU SHOULD SEE
--    * JSON_VALUE, JSON_QUERY, OPENJSON, and the rest work against a json
--      column with no code change. 
--    * Without RETURNING, JSON_VALUE hands back nvarchar(4000), as it always
--      has. 
--      The second result shows the types: nvarchar with a max_length of
--      8000 bytes (4,000 characters), then decimal(10,2), then date.
--    * With RETURNING, you get a typed value straight from the function. No
--      CAST or TRY_CONVERT wrapped around it. RETURNING only works when the
--      input is the json type.
--    * One trap: text that comes out of a json column carries a binary UTF-8
--      collation. Comparing it with a literal is fine. Comparing it with a
--      regular varchar column can raise a collation conflict; add COLLATE
--      DATABASE_DEFAULT if that happens.
-----








-----
-- STEP 6: Changing one value: JSON_MODIFY versus the modify method
-- DO: Run this step.


-----
-- (RESET) Put order 42 back to 'processing' in both tables, so that this step shows
-- a change every time it runs.
UPDATE dbo.OrderDocs_Text
SET Doc = JSON_MODIFY(Doc, '$.status', 'processing')
WHERE OrderID = 42;

UPDATE dbo.OrderDocs_JSON
SET Doc.modify('$.status', 'processing')
WHERE OrderID = 42;

SELECT
	'before' AS moment,
	(SELECT JSON_VALUE(Doc, '$.status') FROM dbo.OrderDocs_Text WHERE OrderID = 42) AS status_in_nvarchar_column,
	(SELECT JSON_VALUE(Doc, '$.status') FROM dbo.OrderDocs_JSON WHERE OrderID = 42) AS status_in_json_column;


-- The old way: read the string, build a new string, write the whole thing back.
UPDATE dbo.OrderDocs_Text
SET Doc = JSON_MODIFY(Doc, '$.status', 'shipped')
WHERE OrderID = 42;

-- The 2025 way: the modify method changes the value inside the document.
UPDATE dbo.OrderDocs_JSON
SET Doc.modify('$.status', 'shipped')
WHERE OrderID = 42;

SELECT
	'after' AS moment,
	(SELECT JSON_VALUE(Doc, '$.status') FROM dbo.OrderDocs_Text WHERE OrderID = 42) AS status_in_nvarchar_column,
	(SELECT JSON_VALUE(Doc, '$.status') FROM dbo.OrderDocs_JSON WHERE OrderID = 42) AS status_in_json_column;
GO

-- WHAT YOU JUST SAW
--    * "before" shows processing in both tables
--      "after" shows shipped in both
--
--    * JSON_MODIFY is a function: it returns a new copy of the document, and
--      the UPDATE assigns that copy to the column.
--    * modify is a method on the column, like the xml modify method. Note the
--      syntax: SET Doc.modify(...), with no equals sign.
--
--    * Same result either way. The next step shows why the second one is
--      cheaper.
-----









-----
-- STEP 8: (Optional) Converting an existing column with ALTER TABLE
-- DO: Run this whole step (three batches).
DROP TABLE IF EXISTS dbo.OrderDocs_Alter;

CREATE TABLE dbo.OrderDocs_Alter (
	OrderID INT NOT NULL,
	Doc VARCHAR(MAX) NOT NULL,
	CONSTRAINT PK_OrderDocs_Alter PRIMARY KEY CLUSTERED (OrderID),
	CONSTRAINT CK_OrderDocs_Alter_IsJson CHECK (ISJSON(Doc) = 1)
);

INSERT INTO dbo.OrderDocs_Alter (
	OrderID,
	Doc
)
SELECT
	OrderID,
	CAST(Doc AS VARCHAR(MAX))
FROM dbo.OrderDocs_Text
WHERE OrderID <= 1000;

SELECT
	'before' AS moment,
	name AS column_name,
	TYPE_NAME(system_type_id) AS data_type
FROM sys.columns
WHERE object_id = OBJECT_ID(N'dbo.OrderDocs_Alter')
	AND name = N'Doc';
GO




-----
-- The check constraint depends on the column, so it has to go first. It is
-- also no longer needed.
ALTER TABLE dbo.OrderDocs_Alter DROP CONSTRAINT IF EXISTS CK_OrderDocs_Alter_IsJson;

ALTER TABLE dbo.OrderDocs_Alter ALTER COLUMN Doc JSON NOT NULL;
GO

SELECT
	'after' AS moment,
	name AS column_name,
	TYPE_NAME(system_type_id) AS data_type
FROM sys.columns
WHERE object_id = OBJECT_ID(N'dbo.OrderDocs_Alter')
	AND name = N'Doc';

SELECT TOP 3
	OrderID,
	Doc
FROM dbo.OrderDocs_Alter
ORDER BY OrderID;
GO

-- WHAT YOU SHOULD SEE
--    * data_type goes from varchar to json, and the documents are still there.
--    * This is the "ALTER an existing varchar(max) column to json" bullet on
--      slide 18. Microsoft Learn documents the conversion for varchar(max).
--    * What to say about a real table: this rewrites every row, and nobody has
--      published how long it takes or how much log it generates on a big one.
--      Test it on a copy first. It is also one way only. You cannot ALTER a
--      json column back to a string type.
-----








-----
-- STEP 9: (Optional) What a json column will not do
-- DO: Run this step. The first query is expected to fail; the error comes
--     back as a result set.
BEGIN TRY
	-- Dynamic SQL so that an error at compile time can still be caught.
	EXEC (N'SELECT TOP 3 OrderID FROM dbo.OrderDocs_JSON ORDER BY Doc;');
END TRY
BEGIN CATCH
	SELECT
		'ORDER BY a json column' AS attempt,
		ERROR_NUMBER() AS error_number,
		ERROR_MESSAGE() AS error_message;
END CATCH;

SELECT TOP 3
	OrderID,
	JSON_VALUE(Doc, '$.total' RETURNING DECIMAL(10, 2)) AS total
FROM dbo.OrderDocs_JSON
ORDER BY
	JSON_VALUE(Doc, '$.total' RETURNING DECIMAL(10, 2)) DESC,
	OrderID;
GO

-- WHAT YOU SHOULD SEE
--    * Error 13636: the json type cannot be compared or sorted. No ORDER BY,
--      no equals, no DISTINCT on the column itself. The xml type behaves the
--      same way.
--    * The fix is to sort or compare a value pulled out of the document, as
--      the second query does.
--    * Also from Microsoft Learn: a json column cannot be an index key column.
--      It can be an included column. Searching inside the document is what the
--      JSON index in 05_JSON_BuildAndFind.sql is for.
-----








-----
-- STEP 10: Reset
-- DO: Run this step when you are finished.
IF @@TRANCOUNT > 0
	ROLLBACK TRANSACTION;

DROP TABLE IF EXISTS dbo.OrderDocs_Text;
DROP TABLE IF EXISTS dbo.OrderDocs_JSON;
DROP TABLE IF EXISTS dbo.OrderDocs_Alter;
GO
