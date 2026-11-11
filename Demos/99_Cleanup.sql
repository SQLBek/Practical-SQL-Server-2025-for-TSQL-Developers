/*-----------------------------------------------------------------------------
-- 99_Cleanup.sql
--
-- Written By: Andy Yun
-- Created On: 2026-10-05
--
-- SQL Server 2025 for T-SQL Developers: demo scripts
--
-- Purpose : Remove everything the demo scripts create, on this instance.
-- Removes : - Extended Events sessions Demo06_OPPO_Receipts and
--             Demo10_CatchSlowQuery
--           - The tempdb limit on the default workload group, but ONLY if it
--             carries the .6171875 tag that 09_TempdbLimit_Error1138.sql uses
--           - The TSQL2025Demo database
--
-- What it does NOT touch
-- - Resource Governor's enabled or disabled state. If STEP 2 removes a
--   leftover limit while Resource Governor is on, it prints the one-line
--   command to turn it off, in case it was off before the demo.
-- - Any tempdb limit, workload group, or classifier that you created
--   yourself.
-----------------------------------------------------------------------------*/




-----
-- STEP 0: Pre-flight
-- DO: Run this step.
SET NOEXEC OFF;
GO

USE master;
GO

-- WHAT THAT DID
--    * Turned execution back on, in case an earlier script stopped itself in
--      this window, and moved to master. A database cannot be dropped by a
--      session that is sitting in it.
-----








-----
-- STEP 1: Drop the demo Extended Events sessions
-- DO: Run this step.
IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = N'Demo06_OPPO_Receipts')
	DROP EVENT SESSION Demo06_OPPO_Receipts ON SERVER;

IF EXISTS(SELECT 1 FROM sys.server_event_sessions WHERE name = N'Demo10_CatchSlowQuery')
	DROP EVENT SESSION Demo10_CatchSlowQuery ON SERVER;
GO

SELECT name AS demo_sessions_still_defined
FROM sys.server_event_sessions
WHERE name LIKE N'Demo[0-9][0-9][_]%';
GO

-- WHAT YOU SHOULD SEE
--    * An empty result. No demo sessions are left.
-----








-----
-- STEP 2: Remove a leftover demo tempdb limit, if there is one
-- DO: Run this step.
DECLARE
	@LimitMB FLOAT,
	@LimitPercent FLOAT;

-- This catalog view has had rows for the default group since Resource
-- Governor was introduced, but the tempdb columns are new in SQL Server 2025.
-- Dynamic SQL keeps this batch from failing to compile on an older version.
IF CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 17
BEGIN
	EXEC sys.sp_executesql
		N'SELECT @LimitMB = group_max_tempdb_data_mb, @LimitPercent = group_max_tempdb_data_percent FROM sys.resource_governor_workload_groups WHERE name = N''default'';',
		N'@LimitMB FLOAT OUTPUT, @LimitPercent FLOAT OUTPUT',
		@LimitMB = @LimitMB OUTPUT,
		@LimitPercent = @LimitPercent OUTPUT;

	IF @LimitMB IS NOT NULL AND ABS((@LimitMB - FLOOR(@LimitMB)) - 0.6171875) < 0.00001
	BEGIN
		EXEC sys.sp_executesql N'ALTER WORKLOAD GROUP [default] WITH (GROUP_MAX_TEMPDB_DATA_MB = NULL);';

		PRINT 'Removed the demo tempdb limit from the default workload group.';

		-- RECONFIGURE would switch Resource Governor ON if it is off, so only
		-- use it when Resource Governor is already on.
		IF (SELECT is_enabled FROM sys.resource_governor_configuration) = 1
		BEGIN
			ALTER RESOURCE GOVERNOR RECONFIGURE;
			PRINT 'Resource Governor is on. If it was off before the demo, run: ALTER RESOURCE GOVERNOR DISABLE;';
		END;
	END
	ELSE IF @LimitMB IS NOT NULL OR @LimitPercent IS NOT NULL
	BEGIN
		PRINT 'The default workload group has a tempdb limit that the demo did not set. Left alone.';
	END
	ELSE
	BEGIN
		PRINT 'No tempdb limit on the default workload group. Nothing to do.';
	END;
END;
GO

-- WHAT THAT DID
--    * Read the Messages tab. In the normal case it says there was nothing to
--      do, because 09_TempdbLimit_Error1138.sql removes its own limit.
--    * A limit is only removed when its value ends in .6171875, the tag that
--      the demo script puts on the limits it creates.
-----








-----
-- STEP 3: Drop the demo database
-- DO: Run this step. Other query windows that are using TSQL2025Demo will be
--     disconnected.
IF DB_ID(N'TSQL2025Demo') IS NOT NULL
BEGIN
	ALTER DATABASE TSQL2025Demo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
	DROP DATABASE TSQL2025Demo;
END;
GO

SELECT
	CASE
		WHEN DB_ID(N'TSQL2025Demo') IS NULL THEN 'TSQL2025Demo is gone.'
		ELSE 'TSQL2025Demo still exists. Check the Messages tab.'
	END AS result;
GO

-- WHAT THAT DID
--    * Dropped the database and everything in it: the two base tables and any
--      demo tables, procedures, and views that were still around.
--    * Run 00_Setup.sql to build it again.
-----
