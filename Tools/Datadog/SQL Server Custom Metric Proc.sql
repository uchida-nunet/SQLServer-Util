USE [master]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_DataDog_SqlServer_Metric]
AS
BEGIN

  SET NOCOUNT ON;

	SELECT
		'sqlserver.' 
			+ REPLACE(LOWER(SUBSTRING(RTRIM(object_name), CHARINDEX(':', object_name) + 1, 100)), ' ', '_') 
			+ '.buffer_cache_hit' AS metric,
		'gauge' AS type,
		CONVERT(float, ratio.cntr_value * 1.0 / base.cntr_value) AS value,
		'db:master' AS tags
	FROM 
		sys.dm_os_performance_counters AS ratio
		CROSS JOIN
		(
			SELECT
				cntr_value
			FROM
				sys.dm_os_performance_counters
			WHERE
				counter_name = 'Buffer cache hit ratio base'
		) AS base
	WHERE
		counter_name = 'Buffer cache hit ratio'
	UNION 
	SELECT 
		'sqlserver.'
			+ REPLACE(LOWER(SUBSTRING(RTRIM(object_name), CHARINDEX(':', object_name) + 1, 100)), ' ', '_') +
			+ '.' 
			+ REPLACE(REPLACE(REPLACE(LOWER(RTRIM(counter_name)), ' ', '_'),'(', ''), ')','') AS metric,
		'gauge' AS type,
		cntr_value AS value,
		'db:master' AS tags 
	FROM 
		sys.dm_os_performance_counters 
	WHERE 
		object_name LIKE '%Memory Manager%'
	UNION
	SELECT 
		'sqlserver.' 
			+ REPLACE(LOWER(SUBSTRING(RTRIM(object_name), CHARINDEX(':', object_name) + 1, 100)), ' ', '_')
			+ '.' 
			+ REPLACE(REPLACE(REPLACE(LOWER(RTRIM(counter_name)), ' ', '_'),'(', ''), ')','') AS metric,
		'gauge' AS type,
		cntr_value AS value,
		'db:master' AS tags
	FROM 
		sys.dm_os_performance_counters 
	WHERE 
		object_name LIKE '%Buffer Manager%'
		AND
		counter_name IN ('Page lookups/sec', 'Readahead pages/sec', 'Page reads/sec', 'Readahead time/sec', 'Page reads/sec', 'Page writes/sec', 'Checkpoint pages/sec', 'Background writer pages/sec', 'Page life expectancy')
END

GRANT EXECUTE ON [dbo].[usp_DataDog_SqlServer_Metric] TO datadog
GO
EXEC  [dbo].[usp_DataDog_SqlServer_Metric]