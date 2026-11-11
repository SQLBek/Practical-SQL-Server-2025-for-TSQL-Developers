/*-----------------------------------------------------------------------------
-- 06_OPPO_v2.sql
--
-- Written By: Andy Yun
-- Created On: 2026-11-01
--
-- SQL Server 2025 for T-SQL Developers: demo scripts
--
-- Feature : Optional parameter plan optimization (OPPO). A variant of
--           06_OPPO.sql, which is unchanged.
--
-- For a short demo: run the setup batch, then STEPS 1, 2, 5, 6, and 7.
--
-- What this version asks
-- 1. With one optional parameter, do NULL and non-NULL callers get different
--    plans? (Yes, per Learn and your CU10 run of 06_OPPO.sql.)
-- 2. With six optional parameters, which ones does OPPO build variants on?
-- 3. When does it decide? Brent's tests say the first caller decides.
-- 4. Can it track more than one? The Learn example shows three.
-- 5. What happens to a caller whose parameter was not chosen?
--
-- References
-- - Microsoft Learn, optional parameter plan optimization. 
--   https://learn.microsoft.com/en-us/sql/relational-databases/performance/optional-parameter-optimization
-- - Microsoft Learn, parameter sensitive plan optimization. 
--   https://learn.microsoft.com/en-us/sql/relational-databases/performance/parameter-sensitive-plan-optimization
-- - Brent Ozar, "How SQL Server 2025's Optional Parameter Plan Optimization
--   Works" 
--   https://www.brentozar.com/archive/2025/05/how-sql-server-2025s-optional-parameter-plan-optimization-works/
-----------------------------------------------------------------------------*/


USE TSQL2025Demo;
GO

SET STATISTICS IO OFF;

IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = N'Demo06_OPPO_Receipts')
	DROP EVENT SESSION Demo06_OPPO_Receipts ON SERVER;

IF (SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()) <> 170
	ALTER DATABASE TSQL2025Demo SET COMPATIBILITY_LEVEL = 170;

ALTER DATABASE SCOPED CONFIGURATION SET OPTIONAL_PARAMETER_OPTIMIZATION = ON;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
ALTER DATABASE TSQL2025Demo SET QUERY_STORE CLEAR;
GO

SELECT
	databases.compatibility_level,
	database_scoped_configurations.name AS configuration_name,
	database_scoped_configurations.value AS configuration_value,
	database_scoped_configurations.is_value_default
FROM sys.databases
CROSS JOIN sys.database_scoped_configurations
WHERE databases.name = DB_NAME()
	AND database_scoped_configurations.name = N'OPTIONAL_PARAMETER_OPTIMIZATION';
GO








-----
-- STEP 1: Give a second optional column an index
-- DO: Run this step. It takes a few seconds.
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name = 'IX_Customers_Email')
	CREATE NONCLUSTERED INDEX IX_Customers_Email
		ON dbo.Customers (Email);
GO

-- WHAT THAT DID
--    * Two of the six columns in the search procedure can now be sought:
--      LastName (IX_Customers_LastName, from 00_Setup.sql) and Email. The
--      other four (FirstName, City, StateCode, Phone) have no index.
--    * The two indexed columns look very different. LastName is skewed:
--      300,000 Smiths and 10 Yuns. Email is nearly unique.
--    * Brent's tests indexed every searchable column. Without a second index
--      here, there is no way to tell whether OPPO prefers LastName because of
--      the first caller or because it is the only column with an index.
-----








-----
-- STEP 2: Create the two search procedures and a helper to read the plan cache
-- DO: Run this step.
CREATE OR ALTER PROCEDURE dbo.usp_OPPO_OneOptional (
	@LastName VARCHAR(30) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;

	SELECT /* OPPOv2One */
		COUNT(*) AS customers_found,
		MIN(City) AS first_city
	FROM dbo.Customers
	WHERE LastName = @LastName
		OR @LastName IS NULL;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_OPPO_SixOptional (
	@FirstName VARCHAR(30) = NULL,
	@LastName VARCHAR(30) = NULL,
	@City VARCHAR(30) = NULL,
	@StateCode CHAR(2) = NULL,
	@Phone VARCHAR(25) = NULL,
	@Email VARCHAR(100) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;

	SELECT /* OPPOv2Six */ COUNT(*) AS customers_found
	FROM dbo.Customers
	WHERE (FirstName = @FirstName OR @FirstName IS NULL)
		AND (LastName = @LastName OR @LastName IS NULL)
		AND (City = @City OR @City IS NULL)
		AND (StateCode = @StateCode OR @StateCode IS NULL)
		AND (Phone = @Phone OR @Phone IS NULL)
		AND (Email = @Email OR @Email IS NULL);
END;
GO




-----
-- The helper. It finds every cached statement that contains @Tag, then pulls
-- the PLAN PER VALUE hint out of that statement's plan.
CREATE OR ALTER PROCEDURE dbo.usp_OPPO_ShowVariants (
	@Tag NVARCHAR(50)
)
AS
BEGIN
	SET NOCOUNT ON;

	WITH Statements_CTE AS (
		SELECT
			dm_exec_query_stats.creation_time,
			dm_exec_query_stats.execution_count,
			dm_exec_query_stats.last_logical_reads,
			dm_exec_text_query_plan.query_plan AS plan_text,
			CHARINDEX(N'PLAN PER VALUE', dm_exec_text_query_plan.query_plan) AS hint_start
		FROM sys.dm_exec_query_stats
		CROSS APPLY sys.dm_exec_sql_text(dm_exec_query_stats.sql_handle) AS dm_exec_sql_text
		CROSS APPLY sys.dm_exec_text_query_plan(dm_exec_query_stats.plan_handle, dm_exec_query_stats.statement_start_offset, dm_exec_query_stats.statement_end_offset) AS dm_exec_text_query_plan
		WHERE dm_exec_sql_text.text LIKE N'%' + @Tag + N'%'
			AND dm_exec_sql_text.text NOT LIKE N'%usp_OPPO_ShowVariants%'
	), Hints_CTE AS (
		SELECT
			creation_time,
			execution_count,
			last_logical_reads,
			plan_text,
			CASE
				WHEN hint_start > 0 THEN SUBSTRING(plan_text, hint_start, CHARINDEX(N'"', plan_text, hint_start) - hint_start)
				ELSE N''
			END AS hint
		FROM Statements_CTE
	)
	SELECT
		CASE
			WHEN CHARINDEX(N'QueryVariantID =', hint) > 0
				THEN TRY_CAST(LTRIM(RTRIM(SUBSTRING(hint, CHARINDEX(N'QueryVariantID =', hint) + 16, CHARINDEX(N',', hint, CHARINDEX(N'QueryVariantID =', hint)) - CHARINDEX(N'QueryVariantID =', hint) - 16))) AS INT)
		END AS query_variant_id,
		(LEN(hint) - LEN(REPLACE(hint, N'optional_predicate(', N''))) / LEN(N'optional_predicate(') AS optional_predicates,
		CASE
			WHEN plan_text LIKE N'%PhysicalOp="Index Seek"%' THEN 'seek'
			WHEN plan_text LIKE N'%Scan"%' THEN 'scan'
			ELSE 'no plan operators'
		END AS plan_shape,
		execution_count,
		last_logical_reads,
		hint
	FROM Hints_CTE
	ORDER BY creation_time;
END;
GO

-- WHAT THAT DID
--    * Two copies of the search procedure: one optional parameter, and six.
--      Every predicate has the shape OPPO looks for:
--      column = @parameter OR @parameter IS NULL.
--    * The comment tags OPPOv2One and OPPOv2Six are how the helper finds
--      their statements in the plan cache, so leave them in.
--    * dbo.usp_OPPO_ShowVariants returns one row for each cached statement:
--        query_variant_id     the QueryVariantID from the hint
--        optional_predicates  how many optional_predicate entries the hint
--                             lists, which is how many parameters OPPO is
--                             tracking
--        plan_shape           seek or scan
--        hint                 the PLAN PER VALUE hint itself
--    * A row with an empty hint and "no plan operators" is the dispatcher, or
--      the procedure's own plan entry. Which one appears can vary by build.
-----








-----
-- STEP 3: (Optional) Start an Extended Events session to capture OPPO's own
--         account of each compile
-- DO: Run this step if you want the receipts in STEP 10.
DECLARE
	@Events NVARCHAR(MAX),
	@SQL NVARCHAR(MAX);

-- Build the event list from what this instance has, so that the script does
-- not break if an event is missing or renamed in a later build.
SELECT @Events = STRING_AGG(
	CAST(N'ADD EVENT ' + dm_xe_packages.name + N'.' + dm_xe_objects.name + N' (WHERE (sqlserver.database_name = N''TSQL2025Demo''))' AS NVARCHAR(MAX)),
	N',' + NCHAR(13) + NCHAR(10)
)
FROM sys.dm_xe_objects
INNER JOIN sys.dm_xe_packages
	ON dm_xe_packages.guid = dm_xe_objects.package_guid
WHERE dm_xe_objects.object_type = N'event'
	AND dm_xe_objects.name IN (
		N'optional_parameter_optimization_skipped_reason',
		N'query_with_optional_parameter_predicate'
	)
	AND (dm_xe_objects.capabilities IS NULL OR dm_xe_objects.capabilities & 1 = 0);

IF @Events IS NULL
BEGIN
	PRINT 'Neither OPPO extended event exists on this instance. Skip STEP 10.';
END
ELSE IF NOT EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = N'Demo06_OPPO_Receipts')
BEGIN
	SET @SQL = N'CREATE EVENT SESSION Demo06_OPPO_Receipts ON SERVER' + NCHAR(13) + NCHAR(10)
		+ @Events + NCHAR(13) + NCHAR(10)
		+ N'ADD TARGET package0.ring_buffer' + NCHAR(13) + NCHAR(10)
		+ N'WITH (MAX_DISPATCH_LATENCY = 1 SECONDS, MAX_DURATION = 15 MINUTES);';

	EXEC sys.sp_executesql @SQL;

	ALTER EVENT SESSION Demo06_OPPO_Receipts ON SERVER STATE = START;
END;
GO

-- WHAT THAT DID
--    * Started an Extended Events session that records two OPPO events for
--      this database. It stops by itself after 15 minutes (MAX_DURATION, the
--      time-bound sessions from 10_TimeBoundXE.sql).
--    * It uses the same session name as 06_OPPO.sql, so 99_Cleanup.sql
--      removes it either way.
-----








-----
-- STEP 4: One optional parameter, OPPO switched OFF (the old behavior)
-- DO: Run this step. Click the Messages tab for the logical reads.
ALTER DATABASE SCOPED CONFIGURATION SET OPTIONAL_PARAMETER_OPTIMIZATION = OFF;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

SET STATISTICS IO ON;
GO

PRINT '--- OPPO OFF, everybody (NULL) ---';
EXEC dbo.usp_OPPO_OneOptional @LastName = NULL;
GO

PRINT '--- OPPO OFF, just the Yuns ---';
EXEC dbo.usp_OPPO_OneOptional @LastName = 'Yun';
GO

SET STATISTICS IO OFF;
GO

EXEC dbo.usp_OPPO_ShowVariants @Tag = N'OPPOv2One';
GO

-- WHAT YOU JUST SAW
--    * One cached plan, used twice. No PLAN PER VALUE hint.
--    * That one plan has to be correct whether @LastName is NULL or not, so it
--      scans. Looking up 10 Yuns costs the same thousands of reads as
--      counting all 1,000,000 customers.
--    * This is the Kitchen Sink slide in one statement.
-----








-----
-- STEP 5: One optional parameter, OPPO ON
-- DO: Run this step. Compare the reads with STEP 4.
ALTER DATABASE SCOPED CONFIGURATION SET OPTIONAL_PARAMETER_OPTIMIZATION = ON;
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

SET STATISTICS IO ON;
GO

PRINT '--- OPPO ON, everybody (NULL) ---';
EXEC dbo.usp_OPPO_OneOptional @LastName = NULL;
GO

PRINT '--- OPPO ON, just the Yuns ---';
EXEC dbo.usp_OPPO_OneOptional @LastName = 'Yun';
GO

SET STATISTICS IO OFF;
GO

EXEC dbo.usp_OPPO_ShowVariants @Tag = N'OPPOv2One';
GO

-- WHAT YOU SHOULD SEE
--    * Two variants, each listing optional_predicate(@LastName IS NULL):
--        - the NULL caller: a scan, thousands of reads
--        - the Yun caller: a seek on IX_Customers_LastName, a handful of reads
--    * Same procedure, same statement, no code change. The dispatcher checks
--      whether @LastName is NULL and hands the call to the matching variant.
--    * This is the slide that says "Two Plans Are Better Than One."
-----








-----
-- STEP 6: Six optional parameters. The first caller searches by last name.
-- DO: Run this step.
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

SET STATISTICS IO ON;
GO

PRINT '--- First caller: last name only ---';
EXEC dbo.usp_OPPO_SixOptional @LastName = 'Yun';
GO

PRINT '--- Second caller: email only ---';
EXEC dbo.usp_OPPO_SixOptional @Email = 'olivia.yun4242@example.net';
GO

SET STATISTICS IO OFF;
GO

EXEC dbo.usp_OPPO_ShowVariants @Tag = N'OPPOv2Six';
GO

-- WHAT YOU SHOULD SEE
--    * Counts: 10, then 1. The email belongs to CustomerID 4242, the first of
--      the 10 Yuns. (Derived from the formulas in 00_Setup.sql.)
--    * The hint on every variant lists ONE optional predicate:
--      optional_predicate(@LastName IS NULL). 
--    * The last-name caller gets a seek. The email caller does not get the
--      Email index: its call lands in the "@LastName IS NULL" variant and
--      scans, even though IX_Customers_Email is sitting right there.
--    * That second caller is the real limitation. OPPO did not "only handle
--      one parameter"; it handled the one it picked.
-----








-----
-- STEP 7: Same procedure, empty cache, but the first caller searches by email
-- DO: Run this step. This is the step that answers "when does it decide?"
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

SET STATISTICS IO ON;
GO

PRINT '--- First caller: email only ---';
EXEC dbo.usp_OPPO_SixOptional @Email = 'olivia.yun4242@example.net';
GO

PRINT '--- Second caller: last name only ---';
EXEC dbo.usp_OPPO_SixOptional @LastName = 'Yun';
GO

SET STATISTICS IO OFF;
GO

EXEC dbo.usp_OPPO_ShowVariants @Tag = N'OPPOv2Six';
GO

-- WHAT YOU SHOULD SEE
--    * If the hint now lists optional_predicate(@Email IS NULL): OPPO picks
--      its parameters when the statement first compiles, from what the first
--      caller supplied. That is what Brent saw in May 2025. The email caller
--      now gets the seek, and the last-name caller is the one who scans.
--      Same procedure, same two calls, opposite winners.
--    * If the hint still lists only @LastName: OPPO is choosing on something
--      else, most likely statistics skew or the index on LastName. Then the
--      "first caller wins" slide is wrong for your build. Use the STEP 10
--      receipts to see the skewness numbers it worked from.
-----








-----
-- STEP 8: Same procedure, empty cache, and the first caller supplies BOTH
-- DO: Run this step. It answers "can it track more than one parameter?"
ALTER DATABASE SCOPED CONFIGURATION CLEAR PROCEDURE_CACHE;
GO

SET STATISTICS IO ON;
GO

PRINT '--- First caller: last name AND email ---';
EXEC dbo.usp_OPPO_SixOptional @LastName = 'Yun', @Email = 'olivia.yun4242@example.net';
GO

PRINT '--- Then last name only ---';
EXEC dbo.usp_OPPO_SixOptional @LastName = 'Yun';
GO

PRINT '--- Then email only ---';
EXEC dbo.usp_OPPO_SixOptional @Email = 'olivia.yun4242@example.net';
GO

PRINT '--- Then city only (no index, no variant expected) ---';
EXEC dbo.usp_OPPO_SixOptional @City = 'Arlington';
GO

SET STATISTICS IO OFF;
GO

EXEC dbo.usp_OPPO_ShowVariants @Tag = N'OPPOv2Six';
GO

-- WHAT YOU SHOULD SEE
--    * Counts: 1, 10, 1, then 50,000 (Arlington is 1 of 20 cities, spread
--      evenly). The city count is derived from 00_Setup.sql.
--    * The city caller scans either way. City has no index, so there is no
--      better plan to switch to.
-----








-----
-- STEP 9: (Optional) The same variants in Query Store
-- DO: Run this step.
EXEC sys.sp_query_store_flush_db;
GO

SELECT
	query_store_query_variant.parent_query_id,
	query_store_query_variant.query_variant_query_id,
	query_store_query_variant.dispatcher_plan_id,
	query_store_query_text.query_sql_text
FROM sys.query_store_query_variant
INNER JOIN sys.query_store_query
	ON query_store_query.query_id = query_store_query_variant.query_variant_query_id
INNER JOIN sys.query_store_query_text
	ON query_store_query_text.query_text_id = query_store_query.query_text_id
WHERE query_store_query_text.query_sql_text LIKE N'%OPPOv2%'
ORDER BY
	query_store_query_variant.parent_query_id,
	query_store_query_variant.query_variant_query_id;
GO

-- WHAT YOU SHOULD SEE
--    * One row per variant, grouped under a parent query, with the
--      PLAN PER VALUE hint visible in query_sql_text.
--    * This is the view to use in production, because plan cache rows
--      disappear on every restart and every cache flush, as this script just
--      proved several times.
-----








-----
-- STEP 10: (Optional) Read OPPO's receipts
-- DO: Run this step if you ran STEP 3.
-- Give the session a moment to flush its buffer to the target.
WAITFOR DELAY '00:00:03';

DECLARE @TargetData XML;

SELECT @TargetData = CAST(dm_xe_session_targets.target_data AS XML)
FROM sys.dm_xe_sessions
INNER JOIN sys.dm_xe_session_targets
	ON dm_xe_session_targets.event_session_address = dm_xe_sessions.address
WHERE dm_xe_sessions.name = N'Demo06_OPPO_Receipts'
	AND dm_xe_session_targets.target_name = N'ring_buffer';

SELECT
	EventNodes.EventNode.value('@name', 'NVARCHAR(128)') AS event_name,
	EventNodes.EventNode.value('@timestamp', 'DATETIME2(3)') AS utc_time,
	DataNodes.DataNode.value('@name', 'NVARCHAR(128)') AS field_name,
	COALESCE(DataNodes.DataNode.value('(text)[1]', 'NVARCHAR(4000)'), DataNodes.DataNode.value('(value)[1]', 'NVARCHAR(4000)')) AS field_value
FROM @TargetData.nodes('/RingBufferTarget/event') AS EventNodes(EventNode)
CROSS APPLY EventNodes.EventNode.nodes('data') AS DataNodes(DataNode)
ORDER BY
	utc_time,
	event_name,
	field_name;
GO

-- WHAT YOU SHOULD SEE
--    * One query_with_optional_parameter_predicate event per compile. Read the
--      rows in groups that share a utc_time.
--    * optional_parameter_predicate_count: how many optional predicates the
--      optimizer found "interesting" for that compile. Compare it with the
--      optional_predicates column from STEPS 6 to 8.
--    * predicate_details: JSON with a Skewness value per predicate. Learn shows
--      the field but does not explain how it is used. If STEP 7 did NOT flip to
--      @Email, these numbers are the best clue to why.
-----








-----
-- STEP 11: Reset
-- DO: Run this step when you are finished.
SET STATISTICS IO OFF;

IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = N'Demo06_OPPO_Receipts')
	DROP EVENT SESSION Demo06_OPPO_Receipts ON SERVER;

DROP PROCEDURE IF EXISTS dbo.usp_OPPO_OneOptional;
DROP PROCEDURE IF EXISTS dbo.usp_OPPO_SixOptional;
DROP PROCEDURE IF EXISTS dbo.usp_OPPO_ShowVariants;
DROP INDEX IF EXISTS IX_Customers_Email ON dbo.Customers;

ALTER DATABASE SCOPED CONFIGURATION SET OPTIONAL_PARAMETER_OPTIMIZATION = ON;
GO

-- WHAT THAT DID
--    * Dropped the Extended Events session, the three procedures, and the
--      Email index, and left OPPO at its default (ON).
-----
