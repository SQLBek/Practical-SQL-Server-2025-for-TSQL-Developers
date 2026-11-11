/*-----------------------------------------------------------------------------
-- 02_FuzzyStringMatching.sql
--
-- Written By: Andy Yun
-- Created On: 2026-10-05
--
-- SQL Server 2025 for T-SQL Developers: demo scripts
--
-- Feature : Fuzzy string matching (EDIT_DISTANCE, EDIT_DISTANCE_SIMILARITY,
--           JARO_WINKLER_DISTANCE, JARO_WINKLER_SIMILARITY)
--
-- References
-- - Microsoft Learn, fuzzy string matching overview (preview status,
--   collation support):
--   https://learn.microsoft.com/en-us/sql/relational-databases/fuzzy-string-match/overview
-- - Microsoft Learn, EDIT_DISTANCE:
--   https://learn.microsoft.com/en-us/sql/t-sql/functions/edit-distance-transact-sql
-- - Microsoft Learn, ALTER DATABASE SCOPED CONFIGURATION (PREVIEW_FEATURES):
--   https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-database-scoped-configuration-transact-sql
-----------------------------------------------------------------------------*/


USE TSQL2025Demo;
GO

DROP TABLE IF EXISTS dbo.MailingList;
GO








-----
-- STEP 1: The cost of admission, turn on preview features for this database
-- DO: Run this step.
ALTER DATABASE SCOPED CONFIGURATION 
	SET PREVIEW_FEATURES = ON;
GO

SELECT
	name,
	value,
	is_value_default
FROM sys.database_scoped_configurations
WHERE name = N'PREVIEW_FEATURES';
GO

-- WHAT YOU JUST SAW
--    * PREVIEW_FEATURES is a per-database switch, OFF by default. It enables
--      every preview feature in the database at once, not just this one.
-----








-----
-- STEP 2: What we had before: SOUNDEX() & DIFFERENCE()
--
--    * SOUNDEX() reduces a string to a letter and three digits based on how it
--      sounds in English. 
--
--    * DIFFERENCE() compares two SOUNDEX codes and returns 0 to 4, where 4 is the best match.
SELECT
	SOUNDEX('Jon Smith') AS soundex_jon_smith,
	SOUNDEX('John Smyth') AS soundex_john_smyth,
	SOUNDEX('Jan Smith') AS soundex_jan_smith,
	SOUNDEX('Jon Zimmerman') AS soundex_jon_zimmerman,
	'||' AS '||',
	DIFFERENCE('Jon Smith', 'John Smyth') AS difference_jon_vs_john,
	DIFFERENCE('Jon Smith', 'Jan Smith') AS difference_jon_vs_jan;
GO

-- WHAT YOU SHOULD SEE
--    * All three names get the same code, so both comparisons score a perfect
--      4. SOUNDEX cannot tell Jon Smith from Jan Smith.
--    * SOUNDEX stops at the first space, so it never read the last name 
--      at all. 'Jon Smith' and 'Jon Zimmerman' also score 4.
-----








-----
-- STEP 3: The four new functions on the same pair
-- DO: Run this step.
SELECT
	EDIT_DISTANCE('Jon Smith', 'John Smyth') AS edit_distance,
	EDIT_DISTANCE_SIMILARITY('Jon Smith', 'John Smyth') AS edit_distance_similarity,
	JARO_WINKLER_DISTANCE('Jon Smith', 'John Smyth') AS jaro_winkler_distance,
	JARO_WINKLER_SIMILARITY('Jon Smith', 'John Smyth') AS jaro_winkler_similarity;
GO

-- WHAT YOU SHOULD SEE
--    * EDIT_DISTANCE = 2. Two single-character edits turn one string into the
--      other: insert the h, and change the i to a y.
--    * EDIT_DISTANCE_SIMILARITY = 80. Documented formula: (1 - edit_distance /
--      length of the longer string) * 100 = (1 - 2/10) * 100.
--
--    * JARO_WINKLER_DISTANCE is a float where 0 means identical.
--    * JARO_WINKLER_SIMILARITY is an int from 0 to 100 where 100 means
--      identical. 
--
--      Jaro-Winkler gives extra credit when the strings start the same way, 
--      which suits names.
--
--    * The two similarity functions are the easy ones to explain: 0 to 100,
--      higher is closer.
-----








-----
-- STEP 4: A few pairs side by side
-- DO: Run this step.
WITH Pairs_CTE (row_no, name_1, name_2) AS (
	SELECT 1, 'Sebastian', 'Sebastian' UNION ALL		-- identical
	SELECT 2, 'Sebastian', 'Sebastain' UNION ALL		-- two letters swapped
	SELECT 3, 'Sebastian', 'Sebastien' UNION ALL		-- one letter different
	SELECT 4, 'Sebastian', 'SEBASTIAN' UNION ALL		-- case only
	SELECT 5, 'Sebastian', 'bastian' UNION ALL		-- missing the first two letters
	SELECT 6, 'Sebastian', 'Sebasti' UNION ALL		-- missing the last two letters
	SELECT 7, 'Sebastian', 'Tennis ball'			-- nothing alike
)
SELECT
	row_no,
	name_1,
	name_2,
	EDIT_DISTANCE(name_1, name_2) AS edit_distance,
	EDIT_DISTANCE_SIMILARITY(name_1, name_2) AS edit_similarity,
	JARO_WINKLER_SIMILARITY(name_1, name_2) AS jaro_winkler_similarity
FROM Pairs_CTE
ORDER BY row_no;
GO

-- WHAT YOU SHOULD SEE
--    * Row 2: the swapped letters count as ONE edit, not two. EDIT_DISTANCE
--      uses the Damerau-Levenshtein algorithm (optimal string alignment),
--      which counts a transposition of two adjacent characters as a single
--      edit.
--    * Row 4: distance 0. Unlike the regex functions, the fuzzy functions DO
--      follow the collation of their inputs, and this database is
--      case-insensitive. 
--    * Row 5 loses its first two letters, row 6 its last two. 
--		   - EDIT_DISTANCE scores them the same. 
--		   - Jaro-Winkler scores row 6 higher, because it gives a bonus when 
--           two strings START the same way. That bias toward the front of the 
--           string is why it suits names.
-----








-----
-- STEP 5: A practical example, finding probable duplicates
-- DO: Run this step.
DROP TABLE IF EXISTS dbo.MailingList;

CREATE TABLE dbo.MailingList (
	ContactID INT NOT NULL,
	FullName VARCHAR(60) NOT NULL,
	CONSTRAINT PK_MailingList PRIMARY KEY CLUSTERED (ContactID)
);

INSERT INTO dbo.MailingList (
	ContactID,
	FullName
)
SELECT 1, 'Jon Smith' UNION ALL
SELECT 2, 'John Smyth' UNION ALL
SELECT 3, 'Jan Smith' UNION ALL
SELECT 4, 'Sebastian Yun' UNION ALL
SELECT 5, 'Sebastain Yun' UNION ALL
SELECT 6, 'Sebastien Yun' UNION ALL
SELECT 7, 'Olivia Martinez' UNION ALL
SELECT 8, 'Olivia Martines' UNION ALL
SELECT 9, 'Liam Nguyen' UNION ALL
SELECT 10, 'Liam Ngyuen' UNION ALL
SELECT 11, 'Emma Zimmerman' UNION ALL
SELECT 12, 'Noah Patel' UNION ALL
SELECT 13, 'Ava Jackson' UNION ALL
SELECT 14, 'Mason Rivera' UNION ALL
SELECT 15, 'Mason Riviera' UNION ALL
SELECT 16, 'Harper Quinn';

SELECT
	MailingList.ContactID AS contact_id_1,
	MailingList.FullName AS name_1,
	PossibleDuplicates.ContactID AS contact_id_2,
	PossibleDuplicates.FullName AS name_2,
	EDIT_DISTANCE(MailingList.FullName, PossibleDuplicates.FullName) AS edit_distance,
	JARO_WINKLER_SIMILARITY(MailingList.FullName, PossibleDuplicates.FullName) AS jaro_winkler_similarity
FROM dbo.MailingList
INNER JOIN dbo.MailingList AS PossibleDuplicates
	ON PossibleDuplicates.ContactID > MailingList.ContactID
WHERE JARO_WINKLER_SIMILARITY(MailingList.FullName, PossibleDuplicates.FullName) >= 90
ORDER BY
	jaro_winkler_similarity DESC,
	MailingList.ContactID;
GO

-- WHAT YOU SHOULD SEE
--    * Tune the threshold if needed.
--    * The near-duplicate pairs: the Sebastians, the Olivias, the Liams, the
--      Masons, and the Smiths. The people who are on the list once should not
--      show up.
--    * 90 is a starting threshold, not a rule. Raise it and you miss real
--      duplicates. Lower it and you start merging different people. Somebody
--      still has to review the matches.
--    * This is a self-join that compares every row with every other row. 16
--      rows is 120 comparisons. 1,000,000 customers would be about 500
--      billion. In real code, narrow the candidates first (same postal code,
--      same first letter, same SOUNDEX) and only then run the fuzzy function.
-----








-----
-- STEP 8: Reset
-- DO: Run this step when you are finished.
DROP TABLE IF EXISTS dbo.MailingList;

ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = OFF;
GO


