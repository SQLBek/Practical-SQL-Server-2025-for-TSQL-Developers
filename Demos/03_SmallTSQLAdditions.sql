/*-----------------------------------------------------------------------------
-- 03_SmallTSQLAdditions.sql
--
-- Written By: Andy Yun
-- Created On: 2026-10-05
--
-- SQL Server 2025 for T-SQL Developers: demo scripts
--
-- Feature : The "petty crimes": PRODUCT, || and ||=, CURRENT_DATE, 
--           SUBSTRING without a length, UNISTR,
--           and DATEADD with a bigint
--           BASE64_ENCODE and BASE64_DECODE included as optional
--
-- Each topic shows the old way first, then the 2025 way. STEPS 1 to 3
-- (PRODUCT) belong together, because STEP 1 creates the table the other two
-- read. Every other step stands alone.
--
-- References (all Microsoft Learn, https://learn.microsoft.com/en-us/sql/t-sql/...)
-- - PRODUCT:        functions/product-aggregate-transact-sql
-- - ||:             language-elements/string-concatenation-pipes-transact-sql
-- - ||=:            language-elements/compound-assignment-pipes-transact-sql
-- - CURRENT_DATE:   functions/current-date-transact-sql
-- - SUBSTRING:      functions/substring-transact-sql
-- - UNISTR:         functions/unistr-transact-sql
-- - DATEADD:        functions/dateadd-transact-sql
-- - BASE64_ENCODE:  functions/base64-encode-transact-sql
-- - BASE64_DECODE:  functions/base64-decode-transact-sql
-----------------------------------------------------------------------------*/


USE TSQL2025Demo;
GO








-----
-- STEP 1: SUBSTRING without a length
-- DO: Run this step.
SELECT TOP 3
	TrackingNumber,
	SUBSTRING(TrackingNumber, 4, LEN(TrackingNumber)) AS the_old_way,
	SUBSTRING(TrackingNumber, 4, 8000) AS the_lazy_old_way,
	-- The 2025 way!!!
	SUBSTRING(TrackingNumber, 4) AS the_2025_way
FROM dbo.Orders
ORDER BY OrderID;
GO

-- WHAT YOU JUST SAW
--    * No more LEN() calls, and no more magic numbers like 8000 or 2147483647.
-----








-----
-- STEP 2: UNISTR, Unicode escape sequences
-- DO: Run this step. If the emoji shows as an empty box in the grid, the
--     result is still correct; it is a font issue. Switch to Results to Text
--     (Ctrl+T) or paste the value somewhere else.
SELECT
	N'Good dog ' + NCHAR(55357) + NCHAR(56374) AS the_old_way,
	UNISTR(N'Good dog \+01F436') AS the_2025_way,
	UNISTR(N'Caf\00E9 for dogs') AS four_digit_escape,
	UNISTR(N'Caf#00E9 for dogs', '#') AS custom_escape_character;
GO

-- WHAT YOU JUST SAW
--    * Both of the first two columns end with the dog face emoji, U+1F436.
--    * The old way: work out the two UTF-16 surrogate halves by hand (55357
--      and 56374) and glue them together with NCHAR.
-- 
--    * UNISTR: type the code point. \xxxx takes four hex digits, and \+xxxxxx
--      takes six for characters above U+FFFF. If backslashes are awkward in
--      your string, the second argument picks a different escape character.
--    * Use the N prefix. With a varchar argument, UNISTR needs a UTF-8
--      collation.
-----








-----
-- STEP 3: (Optional) || and ||=, string concatenation with pipes
-- DO: Run this step.
DECLARE
	@First VARCHAR(20) = 'Sebastian',
	@Middle VARCHAR(20) = NULL,
	@Last VARCHAR(20) = 'Yun';

SELECT
	@First + ' ' + @Last AS with_plus,
	@First || ' ' || @Last AS with_pipes,
	@First || @Middle || @Last AS pipes_with_a_null,
	CONCAT(@First, @Middle, @Last) AS concat_with_a_null,
	'Order ' || CAST(42 AS VARCHAR(10)) AS numbers_still_need_a_cast;

DECLARE @Bark VARCHAR(50) = 'Woof';
SET @Bark ||= '!';
SET @Bark ||= ' Woof!';
SELECT @Bark AS bark;
GO

-- WHAT YOU JUST SAW
--    * || is the ANSI SQL concatenation operator. PostgreSQL and Oracle have
--      always had it. Code and developers arriving from those platforms now
--      work without a rewrite.
--    * A NULL operand makes the whole result NULL, always. || ignores the SET
--      CONCAT_NULL_YIELDS_NULL session option; Microsoft Learn calls that the
--      primary difference from +. Use CONCAT when NULLs should be treated as
--      empty strings.
--    * ||= appends to a variable, the same idea as +=.
-----








-----
-- STEP 4: (Optional)  CURRENT_DATE
-- DO: Run this step.
SELECT
	CAST(GETDATE() AS DATE) AS today_the_old_way,
	CURRENT_DATE AS today_2025,
	SQL_VARIANT_PROPERTY(CURRENT_DATE, 'BaseType') AS data_type;

SELECT
	MAX(OrderDate) AS newest_order,
	DATEDIFF(DAY, MAX(OrderDate), CURRENT_DATE) AS days_since_newest_order
FROM dbo.Orders;
GO

-- WHAT YOU JUST SAW
--    * CURRENT_DATE returns a date, not a datetime. No parentheses, the same
--      as CURRENT_TIMESTAMP.
--    * It is the ANSI spelling of CAST(GETDATE() AS date), so it is one less
--      thing to fix when a query comes over from another database platform.
-----








-----
-- STEP 5: (Optional)  DATEADD accepts a bigint
-- DO: Run this step.
-- Milliseconds since 1970-01-01 is how JavaScript and most APIs send a
-- timestamp. It does not fit in an int.
DECLARE @EpochMS BIGINT = 1791158400250;

SELECT
	DATEADD(MILLISECOND, @EpochMS % 1000, DATEADD(SECOND, @EpochMS / 1000, CAST('1970-01-01' AS DATETIME2(3)))) AS the_old_way,
	DATEADD(MILLISECOND, @EpochMS, CAST('1970-01-01' AS DATETIME2(3))) AS the_2025_way;
GO

-- WHAT YOU JUST SAW
--    * Both columns return 2026-10-05 00:00:00.250.
--    * Before 2025, the second argument of DATEADD was an int. Passing this
--      value directly failed with error 8115, "Arithmetic overflow error
--      converting expression to data type int." The workaround was to split it
--      into seconds and leftover milliseconds and call DATEADD twice.
--    * DATEDIFF_BIG arrived in SQL Server 2016. It took until 2025 for DATEADD
--      to accept what DATEDIFF_BIG returns.
-----








-----
-- STEP 6: (Optional) PRODUCT, set up a small table of yearly returns
-- DO: Run this step.
DROP TABLE IF EXISTS dbo.Returns;

CREATE TABLE dbo.Returns (
	Fund VARCHAR(20) NOT NULL,
	Year SMALLINT NOT NULL,
	Rate DECIMAL(9, 4) NULL,
	CONSTRAINT PK_Returns PRIMARY KEY CLUSTERED (Fund, Year)
);

INSERT INTO dbo.Returns (
	Fund,
	Year,
	Rate
)
SELECT 'Kibble Fund', 2021, 0.1000 UNION ALL
SELECT 'Kibble Fund', 2022, -0.0500 UNION ALL
SELECT 'Kibble Fund', 2023, 0.2000 UNION ALL
SELECT 'Kibble Fund', 2024, NULL UNION ALL		-- no data for this year
SELECT 'Kibble Fund', 2025, 0.0800 UNION ALL
SELECT 'Squirrel Futures', 2021, 0.5000 UNION ALL
SELECT 'Squirrel Futures', 2022, -1.0000 UNION ALL	-- lost everything this year
SELECT 'Squirrel Futures', 2023, 0.3000 UNION ALL
SELECT 'Squirrel Futures', 2024, 0.1000 UNION ALL
SELECT 'Squirrel Futures', 2025, 0.2000;

SELECT
	Fund,
	Year,
	Rate
FROM dbo.Returns
ORDER BY
	Fund,
	Year;
GO

-- WHAT YOU JUST SAW
--    * Two funds, five years each. To get the compounded return you multiply
--      (1 + Rate) across the years. SQL Server has had SUM since the beginning
--      and never had a way to multiply.
--    * Two traps are planted in the data: a NULL, and a year with a -100
--      percent return, which makes one of the factors zero.
-----








-----
-- STEP 7: (Optional) PRODUCT, the old workaround
-- DO: Run this step. The second query is expected to fail; the error comes
--     back as a result set.
SELECT
	Fund,
	EXP(SUM(LOG(1 + Rate))) AS growth_factor_the_old_way
FROM dbo.Returns
WHERE Fund = 'Kibble Fund'
GROUP BY Fund;

DECLARE @Growth FLOAT;

BEGIN TRY
	SELECT @Growth = EXP(SUM(LOG(1 + Rate)))
	FROM dbo.Returns
	WHERE Fund = 'Squirrel Futures';

	SELECT
		'Squirrel Futures' AS Fund,
		@Growth AS growth_factor_the_old_way;
END TRY
BEGIN CATCH
	SELECT
		'Squirrel Futures, the old way' AS attempt,
		ERROR_NUMBER() AS error_number,
		ERROR_MESSAGE() AS error_message;
END CATCH;
GO

-- WHAT YOU SHOULD SEE
--    * Kibble Fund: about 1.35432, as a float. This is the trick on slide 13:
--      add up the logarithms, then raise e to that power. It works because
--      log(a) + log(b) = log(a * b), and nobody remembers that when they read
--      the code a year later.
--    * Squirrel Futures: "An invalid floating point operation occurred." 
--      The -100 percent year makes a factor of zero, and the logarithm of zero
--      does not exist. The workaround also fails on negative factors. The
--      real-world versions of this trick are wrapped in NULLIF and CASE for
--      that reason.
-----








-----
-- STEP 8: (Optional) PRODUCT, the 2025 way
-- DO: Run this step.
SELECT
	Fund,
	PRODUCT(1 + Rate) AS growth_factor,
	COUNT(*) AS years_in_table,
	COUNT(Rate) AS years_with_a_rate
FROM dbo.Returns
GROUP BY Fund
ORDER BY Fund;

SELECT
	Fund,
	Year,
	Rate,
	PRODUCT(1 + Rate) OVER (PARTITION BY Fund ORDER BY Year) AS running_growth_factor
FROM dbo.Returns
ORDER BY
	Fund,
	Year;
GO

-- WHAT YOU SHOULD SEE
--    * Kibble Fund 1.354320, Squirrel Futures 0.000000. No error, and the
--      result is a decimal, not a float.
--    * PRODUCT ignores NULLs, the same way SUM does. Kibble Fund has five rows
--      and four rates, and the answer uses the four.
--    * Second result: PRODUCT works as a window function, so a running
--      compounded return is one line. Watch Squirrel Futures go to zero in
--      2022 and stay there.
-----








-----
-- STEP 9: (Optional) BASE64, the old way and the 2025 way
-- DO: Run this step.
DECLARE @Bin VARBINARY(100) = CAST('Woof' AS VARBINARY(100));

SELECT
	CAST(N'' AS XML).value('xs:base64Binary(sql:variable("@Bin"))', 'VARCHAR(200)') AS encode_the_old_way,
	BASE64_ENCODE(@Bin) AS encode_2025,
	CAST(BASE64_DECODE('V29vZg==') AS VARCHAR(10)) AS decode_2025;
GO

-- WHAT YOU JUST SAW
--    * All roads lead to V29vZg==, which is Base64 for "Woof".
--    * The old way borrows the XML engine: cast an empty string to xml, then
--      call an XQuery function on a T-SQL variable. Everybody copied it from
--      the same forum post.
--    * BASE64_ENCODE takes varbinary and returns varchar. Strings have to be
--      cast to varbinary first. BASE64_DECODE goes the other way and returns
--      varbinary, which is why the example casts the result back to varchar.
-----








-----
-- STEP 10: (Optional) BASE64, the URL-safe option and bad input
-- DO: Run this step. The last statement is expected to fail; the error
--     comes back as a result set.
SELECT
	BASE64_ENCODE(0xFBFF) AS standard_alphabet,
	BASE64_ENCODE(0xFBFF, 1) AS url_safe_alphabet,
	BASE64_DECODE('-_8') AS url_safe_decodes_too;

DECLARE
	@BadInput VARCHAR(50) = 'not base64!',
	@Decoded VARBINARY(50);

BEGIN TRY
	SET @Decoded = BASE64_DECODE(@BadInput);

	SELECT
		'It decoded. That was not supposed to happen.' AS bad_input_result,
		@Decoded AS decoded;
END TRY
BEGIN CATCH
	SELECT
		'Decode bad input' AS attempt,
		ERROR_NUMBER() AS error_number,
		ERROR_MESSAGE() AS error_message;
END CATCH;
GO

-- WHAT YOU SHOULD SEE
--    * Standard: +/8=   URL-safe: -_8 The standard alphabet uses + and /,
--      which both mean something in a URL. Pass 1 as the second argument and
--      you get - and _ instead, with no = padding. That is the format JWTs and
--      most web APIs use.
--    * BASE64_DECODE accepts either alphabet and returns 0xFBFF.
--    * Bad input raises error 9803, "Invalid data for type". It does not
--      quietly return NULL, so wrap it in TRY...CATCH when the input comes
--      from outside.
-----





-----
-- STEP 11: Reset
-- DO: Run this step when you are finished.
DROP TABLE IF EXISTS dbo.Returns;
GO

