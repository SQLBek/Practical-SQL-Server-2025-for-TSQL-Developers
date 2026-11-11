/*-----------------------------------------------------------------------------
-- 01_Regex.sql
--
-- Written By: Andy Yun
-- Created On: 2026-10-05
--
-- Adapted From: Bob Ward, "SQL Server 2025 Unveiled"
-- https://github.com/microsoft/bobsql (demos/sqlserver2025/regex)
--
-- SQL Server 2025 for T-SQL Developers: demo scripts
--
-- Feature : Regular expressions (REGEXP_LIKE and six more functions)
--
-- References
-- - Microsoft Learn, regular expressions overview:
--   https://learn.microsoft.com/en-us/sql/relational-databases/regular-expressions/overview
-- - Microsoft Learn, REGEXP_LIKE (compat level, SARGability, CHECK example):
--   https://learn.microsoft.com/en-us/sql/t-sql/functions/regexp-like-transact-sql
-- - Bob Ward, "SQL Server 2025 Unveiled" and his demo repo https://github.com/microsoft/bobsql 
-- - Brent Ozar, "Update: SQL Server 2025's REGEX Performance Isn't So Bad!"
--   https://www.brentozar.com/archive/2025/12/update-sql-server-2025s-regex-performance-isnt-so-bad/
-----------------------------------------------------------------------------*/

USE TSQL2025Demo;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
DROP TABLE IF EXISTS dbo.CustomerSignups;

IF (SELECT compatibility_level FROM sys.databases WHERE name = DB_NAME()) <> 170
	ALTER DATABASE TSQL2025Demo SET COMPATIBILITY_LEVEL = 170;
GO








-----
-- STEP 1: The phone number validator from Sebastian's pull request
-- DO: Run this step. Note the count.
-- Browse some phone numbers to see our data
SELECT TOP 1000 CustomerID, Phone
FROM dbo.Customers
ORDER BY CustomerID;
GO


-- Validate how many phone numbers in here are correct/valid
SELECT COUNT(*) AS valid_phones_the_old_way
FROM dbo.Customers
WHERE LEN(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Phone, '(', ''), ')', ''), '-', ''), '.', ''), ' ', '')) = 10
	AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Phone, '(', ''), ')', ''), '-', ''), '.', ''), ' ', '') NOT LIKE '%[^0-9]%'
OPTION(MAXDOP 1);
GO

-- WHAT YOU JUST SAW
--    * Expected count: 960,000 of the 1,000,000 rows.
--    * It is hard to read, and it is also wrong. It only counts digits, so it
--      accepts anything that happens to contain ten of them. STEP 3 shows what
--      slipped through.
-----








-----
-- Turn on STATISTICS IO and TIME
SET STATISTICS IO ON
SET STATISTICS TIME ON




-----
-- STEP 2: The same check as one regular expression
-- DO: Run this step. Compare the count with STEP 1.
SELECT COUNT(*) AS valid_phones_with_regex
FROM dbo.Customers
WHERE REGEXP_LIKE(Phone, '^\(?\d{3}\)?[-. ]?\d{3}[-. ]?\d{4}$')
OPTION(MAXDOP 1);
GO

-- WHAT YOU JUST SAW
--    * Reading the pattern left to right:
--        ^            start of the string
--        \(?          an optional opening parenthesis
--        \d{3}        three digits (the area code)
--        \)?          an optional closing parenthesis
--        [-. ]?       an optional separator: dash, dot, or space
--        \d{3}        three digits
--        [-. ]?       an optional separator
--        \d{4}        four digits
--        $            end of the string
--    * Expected count: 950,000. That is 10,000 fewer than STEP 1.
--    * REGEXP_LIKE returns true or false, so it goes wherever a predicate
--      goes: WHERE, CASE WHEN, a CHECK constraint. It needs compatibility
--      level 170.
-----








-----
-- STEP 3: What did the old validator let through?
-- DO: Run this step.
SELECT TOP 5
	CustomerID,
	Phone
FROM dbo.Customers
WHERE LEN(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Phone, '(', ''), ')', ''), '-', ''), '.', ''), ' ', '')) = 10
	AND REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(Phone, '(', ''), ')', ''), '-', ''), '.', ''), ' ', '') NOT LIKE '%[^0-9]%'
	AND NOT REGEXP_LIKE(Phone, '^\(?\d{3}\)?[-. ]?\d{3}[-. ]?\d{4}$')
ORDER BY CustomerID
OPTION(MAXDOP 1);
GO

-- WHAT YOU JUST SAW
--    * Values like 7-7-4-5-5-5-0039. Ten digits, so the old code calls it a
--      valid phone number. The regex describes the shape of the value, not
--      just what is left after stripping characters, so it rejects it.
-----








-----
-- STEP 4: REGEXP_REPLACE, clean the data up instead of just flagging it
-- DO: Run this step.
SELECT
	CustomerID,
	Phone AS phone_before,
	REGEXP_REPLACE(Phone, '^\(?(\d{3})\)?[-. ]?(\d{3})[-. ]?(\d{4})$', '(\1) \2-\3') AS phone_after
FROM dbo.Customers
WHERE CustomerID BETWEEN 10 AND 19
ORDER BY CustomerID
OPTION(MAXDOP 1);
GO

-- WHAT YOU JUST SAW
--    * Same pattern as STEP 2, with three pairs of parentheses added. Each
--      pair is a capture group. In the replacement string, \1, \2, and \3 put
--      the captured digits back in the order and format you want.
--    * Customers 10 to 18 arrive in four different formats and all leave as
--      (xxx) xxx-xxxx.
--    * Customer 19 is one of the junk rows (7 digits). The pattern does not
--      match, so REGEXP_REPLACE returns the original string untouched.
--    * SQL Server uses \1 for a captured group in the replacement, not $1.
-----








-----
-- STEP 5: REGEXP_SUBSTR, REGEXP_COUNT, and REGEXP_INSTR
--
--    * REGEXP_SUBSTR returns the text that matched. The arguments after the
--      pattern are positional: start position (1), which occurrence (1), flags
--      ('i' = case-insensitive), and which capture group to return (1 = the
--      part inside the parentheses, so the domain without the @).
--
--    * REGEXP_COUNT returns how many times the pattern matched. Here it counts
--      digits, which is the check Exhibit A needed ten REPLACE calls to do.
--
--    * REGEXP_INSTR returns the position of a match, or 0 when there is none.
--
SELECT TOP 8
	CustomerID,
	Email,
	REGEXP_SUBSTR(Email, '@(.+)$', 1, 1, 'i', 1) AS extract_email_domain,
	'||' AS '||',
	Phone,
	REGEXP_COUNT(Phone, '\d') AS get_digits_in_phone,
	REGEXP_INSTR(Phone, '\d') AS find_position_of_first_digit
FROM dbo.Customers
WHERE CustomerID BETWEEN 16 AND 23
ORDER BY CustomerID
OPTION(MAXDOP 1);
GO

-- WHAT YOU JUST SAW
--    * These three, plus REGEXP_REPLACE, work at ANY compatibility level. Only
--      REGEXP_LIKE and the two table-valued functions need 170.
-----








-----
-- STEP 6: REGEXP_MATCHES, one row per match
-- DO: Run this step.
--
--    * REGEXP_MATCHES is a table-valued function. It returns one row for each
--      match, with the position and the matched text.
DECLARE @Note VARCHAR(200) = 'Sebastian chewed order #A-1001, then #B-2002, and finally #C-3003.';

-- Find all orders #[A-Z]-#### in my @Note string
SELECT
	match_id,
	start_position,
	end_position,
	match_value,
	substring_matches AS substring_matches_as_JSON
FROM REGEXP_MATCHES(@Note, '#([A-Z])-(\d{4})')
OPTION(MAXDOP 1);
GO

-- WHAT YOU JUST SAW
--    * substring_matches is a json column: an array with one object per
--      capture group, each with value, start, and length. Three matches and
--      two groups means three rows, each with a two-element array.
-----








-----
-- STEP 7: REGEXP_SPLIT_TO_TABLE, STRING_SPLIT with a pattern for a delimiter
-- DO: Run this step.

-- Split MULTIPLE delimiters!!!
SELECT
	ordinal,
	value
FROM REGEXP_SPLIT_TO_TABLE('kibble, treats;squeaky toy | tennis ball', '\s*[,;|]\s*')
ORDER BY ordinal;
GO

-- WHAT YOU JUST SAW
--    * STRING_SPLIT takes one fixed separator. This takes a pattern, so one
--      call handles commas, semicolons, and pipes, and it swallows the spaces
--      around them too.
--    * Four rows: kibble, treats, squeaky toy, tennis ball.
-----








-----
-- STEP 8: (Optional) Regular expressions ignore collation
-- DO: Run this step.
SELECT
	CASE
		WHEN 'SEBASTIAN' = 'sebastian' THEN 'match'
		ELSE 'no match'
	END AS equals_operator,
	CASE
		WHEN 'SEBASTIAN' LIKE 'sebastian' THEN 'match'
		ELSE 'no match'
	END AS like_operator,
	CASE
		WHEN REGEXP_LIKE('SEBASTIAN', '^sebastian$') THEN 'match'
		ELSE 'no match'
	END AS regexp_like_default,
	CASE
		WHEN REGEXP_LIKE('SEBASTIAN', '^sebastian$', 'i') THEN 'match'
		ELSE 'no match'
	END AS regexp_like_i_flag;
GO

-- WHAT YOU JUST SAW
--    * This database has a case-insensitive collation, so = and LIKE say
--      "match".
--    * REGEXP_LIKE says "no match". Regular expressions do not follow
--      collation rules and are case-sensitive unless you pass the 'i' flag.
--    * This is the "Ignores collation rules" bullet on slide 10, and it is the
--      one most likely to surprise someone converting LIKE predicates to
--      regex.
-----








-----
-- STEP 9: DEMO SLIDE 9. Put the rule in the table: regex in a CHECK constraint
-- DO: Run this step to create the table.
DROP TABLE IF EXISTS dbo.CustomerSignups;

CREATE TABLE dbo.CustomerSignups (
	SignupID INT IDENTITY(1, 1) NOT NULL,
	FullName VARCHAR(60) NOT NULL,
	Email VARCHAR(100) NOT NULL,
	Phone VARCHAR(25) NOT NULL,
	CONSTRAINT PK_CustomerSignups PRIMARY KEY CLUSTERED (SignupID),
	CONSTRAINT CK_CustomerSignups_Email CHECK (REGEXP_LIKE(Email, '^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$')),
	CONSTRAINT CK_CustomerSignups_Phone CHECK (REGEXP_LIKE(Phone, '^\(\d{3}\) \d{3}-\d{4}$'))
);
GO

-- WHAT YOU JUST SAW
--    * Two CHECK constraints, each a single REGEXP_LIKE.
--    * Email: one or more characters that are not @ or whitespace, then @,
--      then more of the same, then a dot and at least two letters.
--      Deliberately loose. It catches typos, it does not try to implement the
--      email RFC.
--    * Phone: exactly (xxx) xxx-xxxx. One storage format, enforced by the
--      engine, no matter which application writes the row.
--    * Before 2025 this took a CLR function or a pile of LIKE patterns.
-----








-----
-- STEP 10: Insert a row that follows the rules
-- DO: Run this step.
INSERT INTO dbo.CustomerSignups (
	FullName,
	Email,
	Phone
)
SELECT 'Sebastian Yun', 'sebastian@example.com', '(617) 555-0142';

SELECT
	SignupID,
	FullName,
	Email,
	Phone
FROM dbo.CustomerSignups;
GO

-- WHAT YOU JUST SAW
--    * One row inserted. Both constraints evaluated to true.
-----








-----
-- STEP 11: Insert rows that break the rules
-- DO: Run this step. Each insert is expected to fail; the error comes back
--     as a result set so that it is easy to read on a projector.
--     (To show the raw red error text, highlight and run just one INSERT
--     statement by itself.)
BEGIN TRY
	INSERT INTO dbo.CustomerSignups (
		FullName,
		Email,
		Phone
	)
	SELECT 'Junior Developer', 'junior@example.com', '617.555.0199';

	SELECT 'The row was inserted. That was not supposed to happen.' AS bad_phone_result;
END TRY
BEGIN CATCH
	SELECT
		'Bad phone' AS attempt,
		ERROR_NUMBER() AS error_number,
		ERROR_MESSAGE() AS error_message;
END CATCH;

BEGIN TRY
	INSERT INTO dbo.CustomerSignups (
		FullName,
		Email,
		Phone
	)
	SELECT 'Junior Developer', 'junior at example dot com', '(617) 555-0199';

	SELECT 'The row was inserted. That was not supposed to happen.' AS bad_email_result;
END TRY
BEGIN CATCH
	SELECT
		'Bad email' AS attempt,
		ERROR_NUMBER() AS error_number,
		ERROR_MESSAGE() AS error_message;
END CATCH;
GO

-- WHAT YOU JUST SAW
--    * Error 547 twice, the ordinary CHECK constraint violation. The message
--      names the constraint, CK_CustomerSignups_Phone or
--      CK_CustomerSignups_Email, so the application can tell which rule was
--      broken.
--    * The first phone number is a perfectly good phone number. It is just not
--      in the one format the table accepts. That leads to the next step.
-----








-----
-- STEP 12: Fix the value on the way in, and let the constraint guard the door
-- DO: Run this step.
INSERT INTO dbo.CustomerSignups (
	FullName,
	Email,
	Phone
)
SELECT
	'Junior Developer',
	'junior@example.com',
	REGEXP_REPLACE('617.555.0199', '^\(?(\d{3})\)?[-. ]?(\d{3})[-. ]?(\d{4})$', '(\1) \2-\3');

SELECT
	SignupID,
	FullName,
	Email,
	Phone
FROM dbo.CustomerSignups
ORDER BY SignupID;
GO

-- WHAT YOU JUST SAW
--    * REGEXP_REPLACE reformatted 617.555.0199 to (617) 555-0199 inside the
--      INSERT, and the CHECK constraint accepted it.
--    * Two rows in the table now. SignupID skips some numbers because the
--      failed inserts in STEP 11 still used up identity values.
--    * This is the end of the slide 9 demo. Sebastian's bubble on that slide
--      asks "What could possibly go wrong?" STEPS 13 to 15 answer him and line
--      up with slide 10, the fine print.
-----








-----
-- STEP 13: Fine print, can a regex seek on an index?
-- DO: Turn on Include Actual Execution Plan with Ctrl+M first.
--     Click the Messages tab after running this step. The logical reads for
--     each query are the point. 
SET STATISTICS IO ON;
GO

PRINT '--- Query 1: LIKE with a fixed prefix (the baseline, an index seek) ---';
SELECT COUNT(*) AS like_prefix
FROM dbo.Customers
WHERE LastName LIKE 'Yun%';
GO

PRINT '--- Query 2: REGEXP_LIKE, pattern anchored with ^ ---';
SELECT COUNT(*) AS regex_anchored
FROM dbo.Customers
WHERE REGEXP_LIKE(LastName, '^Yun');
GO

PRINT '--- Query 3: REGEXP_LIKE, same search, pattern not anchored ---';
SELECT COUNT(*) AS regex_not_anchored
FROM dbo.Customers
WHERE REGEXP_LIKE(LastName, 'Yun');
GO

SET STATISTICS IO OFF;
GO

-- WHAT YOU SHOULD SEE
--    * All three queries return 10.
--    * Query 1 is the baseline: a handful of logical reads, an index seek on
--      IX_Customers_LastName.
--    * Query 3 reads the whole index, a few thousand pages, and runs the regex
--      against all 1,000,000 last names. A regex without ^ behaves like LIKE
--      '%Yun%', and it deserves the same suspicion in a code review.
--    * Query 2 is the question. Microsoft Learn says: "REGEXP_LIKE is SARGable
--      only when the pattern begins with the anchor ^." That predicts a seek,
--      with reads like Query 1. But on the RTM build, Brent Ozar's retest
--      (December 2025, in the references) still got a scan for an anchored
--      pattern, and Bob Ward commented on that post that index seek for
--      REGEXP_LIKE "is coming". Which cumulative update delivered it is not
--      something this script can tell you. Your build can.
--    * If Query 2 reads like Query 1: the slide 10 bullet "SARGable only when
--      the pattern starts with ^" is true as written.
--    * If Query 2 reads like Query 3: change that bullet before you present.
-----








-----
-- STEP 14: Fine print, a regex costs more CPU than LIKE
-- DO: Run this step, then read the CPU time lines on the Messages tab.
SET STATISTICS TIME ON;
GO

PRINT '--- Query 1: LIKE ---';
SELECT COUNT(*) AS contoso_emails_like
FROM dbo.Customers
WHERE Email LIKE '%@contoso.com';
GO

PRINT '--- Query 2: REGEXP_LIKE ---';
SELECT COUNT(*) AS contoso_emails_regex
FROM dbo.Customers
WHERE REGEXP_LIKE(Email, '@contoso\.com$');
GO

SET STATISTICS TIME OFF;
GO

-- WHAT YOU SHOULD SEE
--    * The same count from both queries, about 200,000.
--    * Both scan the table. Neither can seek, because both patterns are
--      open-ended at the front. Expect the regex to use noticeably more CPU.
--    * Talking point: regex is the right tool when LIKE cannot express the
--      rule. It is not a faster LIKE. See Brent Ozar's RTM retest in the
--      references for numbers at a larger scale.
-----







