/*-----------------------------------------------------------------------------
-- 07_OptimizedLocking.sql
--
-- Written By: Andy Yun
-- Created On: 2026-10-05
--
-- Adapted From: Bob Ward, "SQL Server 2025 Unveiled" 
-- https://github.com/microsoft/bobsql (demos/sqlserver2025/optimized_locking)
--
-- SQL Server 2025 for T-SQL Developers: demo scripts
-- 07_OptimizedLocking.sql
--
-- Feature : Optimized locking: transaction ID (TID) locking and lock after
--           qualification (LAQ)
-- Badge   : SWITCH. Off by default in SQL Server 2025, on per database.
--           Needs accelerated database recovery (ADR). LAQ also needs read
--           committed snapshot isolation (RCSI).
-- Needs   : 00_Setup.sql.
-- Rerun   : Safe. Run it top to bottom or step by step, any number of times.
--           Pressing F5 on the whole file runs every step without the second
--           window; nothing blocks and no transaction is left open.
--
-- Heads-up: this script changes database options with ROLLBACK IMMEDIATE,
-- which disconnects every other session that is using TSQL2025Demo. The
-- Window 2 file parks itself in tempdb (its STEP 0, and again after each
-- step) so that it is not one of them. Close other tabs that point at
-- TSQL2025Demo before you start.
--
-- References
-- - Microsoft Learn, optimized locking 
--   https://learn.microsoft.com/en-us/sql/relational-databases/performance/optimized-locking
-- - Microsoft Learn, ALTER DATABASE SET options:
--   https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-transact-sql-set-options
-- - Bob Ward, "SQL Server 2025 Unveiled" and his demo repo https://github.com/microsoft/bobsql 
-----------------------------------------------------------------------------*/



USE TSQL2025Demo;
GO

IF @@TRANCOUNT > 0
	ROLLBACK TRANSACTION;
GO




-----
-- Order matters. Optimized locking has to be turned off before anything else
-- is changed, and ADR has to be on before optimized locking can be turned on.
IF (SELECT is_optimized_locking_on FROM sys.databases WHERE name = N'TSQL2025Demo') = 1
	ALTER DATABASE TSQL2025Demo SET OPTIMIZED_LOCKING = OFF WITH ROLLBACK IMMEDIATE;
GO

IF (SELECT is_read_committed_snapshot_on FROM sys.databases WHERE name = N'TSQL2025Demo') = 1
	ALTER DATABASE TSQL2025Demo SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;
GO

IF (SELECT is_accelerated_database_recovery_on FROM sys.databases WHERE name = N'TSQL2025Demo') = 0
	ALTER DATABASE TSQL2025Demo SET ACCELERATED_DATABASE_RECOVERY = ON WITH ROLLBACK IMMEDIATE;
GO


-----
-- Helper view using sys.dm_tran_locks. 
-- It counts the locks in this database 
-- by session, resource type, and mode.
CREATE OR ALTER VIEW dbo.Demo07_LockSummary
AS
SELECT
	request_session_id AS session_id,
	resource_type,
	request_mode,
	request_status,
	COUNT(*) AS lock_count
FROM sys.dm_tran_locks
WHERE resource_database_id = DB_ID()
	AND resource_type <> N'DATABASE'
GROUP BY
	request_session_id,
	resource_type,
	request_mode,
	request_status;
GO

SELECT
	name,
	is_accelerated_database_recovery_on AS adr_on,
	is_optimized_locking_on AS optimized_locking_on,
	is_read_committed_snapshot_on AS rcsi_on
FROM sys.databases
WHERE name = N'TSQL2025Demo';
GO

-- WHAT YOU JUST SAW
--    * Starting point: ADR on, optimized locking OFF, RCSI off. With optimized
--      locking off, locking behaves the way it has for 25 years, whether or
--      not ADR is on.
--    * ADR is switched on now, because it is the prerequisite. Optimized
--      locking uses the transaction ID that ADR stamps on every row version.
--      STEP 17 switches it back off.
--    * Each ALTER DATABASE is its own statement. These three options cannot be
--      combined in one, and each needs to be the only connection in the
--      database, which is what WITH ROLLBACK IMMEDIATE arranges.
-----








-----
-- STEP 1: Update 2,500 rows the classic way and count the locks
-- DO: Run this step.
IF @@TRANCOUNT > 0
	ROLLBACK TRANSACTION;

BEGIN TRANSACTION;

	UPDATE dbo.Orders
	SET Amount = Amount + 1
	WHERE OrderID <= 2500;

	SELECT
		resource_type,
		request_mode,
		request_status,
		lock_count
	FROM dbo.Demo07_LockSummary
	WHERE session_id = @@SPID
	ORDER BY
		lock_count DESC,
		resource_type;

ROLLBACK TRANSACTION;
GO

-- WHAT YOU SHOULD SEE
--    * About 2,500 KEY locks in X mode: one for every row, held until the
--      transaction ends. Plus a few intent locks (IX) on the pages and one on
--      the table (OBJECT).
--    * Every one of those locks costs memory, and every one is something
--      another session can trip over.
-----








-----
-- STEP 2: Update 10,000 rows the classic way
-- DO: Run this step.
IF @@TRANCOUNT > 0
	ROLLBACK TRANSACTION;

BEGIN TRANSACTION;

	UPDATE dbo.Orders
	SET Amount = Amount + 1
	WHERE OrderID <= 10000;

	SELECT
		resource_type,
		request_mode,
		request_status,
		lock_count
	FROM dbo.Demo07_LockSummary
	WHERE session_id = @@SPID
	ORDER BY
		lock_count DESC,
		resource_type;

ROLLBACK TRANSACTION;
GO

-- WHAT YOU SHOULD SEE
--    * Lock escalation!  One OBJECT lock in X mode: the whole table.
-----








-----
-- STEP 3: Flip the switch
-- DO: Run this step.
IF @@TRANCOUNT > 0
	ROLLBACK TRANSACTION;
GO

ALTER DATABASE TSQL2025Demo SET OPTIMIZED_LOCKING = ON WITH ROLLBACK IMMEDIATE;
GO

SELECT
	name,
	is_accelerated_database_recovery_on AS adr_on,
	is_optimized_locking_on AS optimized_locking_on,
	is_read_committed_snapshot_on AS rcsi_on,
	DATABASEPROPERTYEX(name, 'IsOptimizedLockingOn') AS from_databasepropertyex
FROM sys.databases
WHERE name = N'TSQL2025Demo';
GO

-- WHAT YOU JUST SAW
--    * One ALTER DATABASE. No application change, no query change.
-----








-----
-- STEP 4: The same 10,000-row update, then 250,000 rows
-- DO: Run this step.
IF @@TRANCOUNT > 0
	ROLLBACK TRANSACTION;

BEGIN TRANSACTION;
	-- Update 10,000 rows
	UPDATE dbo.Orders
	SET Amount = Amount + 1
	WHERE OrderID <= 10000;

	SELECT '10,000 rows' AS updated,
		resource_type,
		request_mode,
		request_status,
		lock_count
	FROM dbo.Demo07_LockSummary
	WHERE session_id = @@SPID
	ORDER BY
		lock_count DESC,
		resource_type;

ROLLBACK TRANSACTION;

BEGIN TRANSACTION;
	-- Update 250,000 rows
	UPDATE dbo.Orders
	SET Amount = Amount + 1
	WHERE OrderID <= 250000;

	SELECT '250,000 rows' AS updated,
		resource_type,
		request_mode,
		request_status,
		lock_count
	FROM dbo.Demo07_LockSummary
	WHERE session_id = @@SPID
	ORDER BY
		lock_count DESC,
		resource_type;

ROLLBACK TRANSACTION;
GO

-- WHAT YOU SHOULD SEE
--    * Both results look the same: one XACT lock in X mode and an intent lock
--      (IX) on the table. No KEY locks. No table X lock. Half the table was
--      just updated while holding one lock that matters.
--    * XACT is the transaction ID (TID) lock. Row and page locks are still
--      taken while each row is modified, but they are released right away. The
--      transaction keeps a single lock on its own ID, and every row it touched
--      is stamped with that ID.
-----





-----
-- STEP 17: Reset
-- DO: Run this step when you are finished.
IF @@TRANCOUNT > 0
	ROLLBACK TRANSACTION;
GO


DECLARE @Tries INT = 0;

WHILE @Tries < 10
	AND EXISTS(
		SELECT 1
		FROM sys.dm_exec_sessions
		WHERE database_id = DB_ID()
			AND session_id <> @@SPID
			AND is_user_process = 1
			AND program_name NOT LIKE N'%IntelliSense%'
	)
BEGIN
	WAITFOR DELAY '00:00:00.500';
	SET @Tries += 1;
END;
GO

IF (SELECT is_optimized_locking_on FROM sys.databases WHERE name = N'TSQL2025Demo') = 1
	ALTER DATABASE TSQL2025Demo SET OPTIMIZED_LOCKING = OFF WITH ROLLBACK IMMEDIATE;
GO

IF (SELECT is_read_committed_snapshot_on FROM sys.databases WHERE name = N'TSQL2025Demo') = 1
	ALTER DATABASE TSQL2025Demo SET READ_COMMITTED_SNAPSHOT OFF WITH ROLLBACK IMMEDIATE;
GO




-----
-- ADR goes last. It cannot be turned off while optimized locking is on.
IF (SELECT is_accelerated_database_recovery_on FROM sys.databases WHERE name = N'TSQL2025Demo') = 1
	ALTER DATABASE TSQL2025Demo SET ACCELERATED_DATABASE_RECOVERY = OFF WITH ROLLBACK IMMEDIATE;
GO

DROP VIEW IF EXISTS dbo.Demo07_LockSummary;
GO

SELECT
	name,
	is_accelerated_database_recovery_on AS adr_on,
	is_optimized_locking_on AS optimized_locking_on,
	is_read_committed_snapshot_on AS rcsi_on
FROM sys.databases
WHERE name = N'TSQL2025Demo';
GO

-- WHAT THAT DID
--    * All three flags are 0 again and the helper view is gone, so the
--      database is the way 00_Setup.sql left it.
--    * The order is the reverse of turning them on: optimized locking off
--      first, ADR off last.
-----








