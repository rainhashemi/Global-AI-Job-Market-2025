---------------------------------------------------------------
-- 💼 Job Seeker’s Perspective: Finding the Most Rewarding Opportunities
-- Purpose: Identify the Top 5 highest-paying job titles per country 
-- while showing salary variation and stability for informed career planning.
---------------------------------------------------------------

-- Step 1️: Load the dataset
SELECT * 
FROM ai_job.dbo.ai_job_dataset;

---------------------------------------------------------------
-- Step 2️: Compute Top 5 Highest-Paying Job Titles per Country
---------------------------------------------------------------
WITH BaseStats AS (
    -- Step 2.1: Filter dataset for valid salary entries
    SELECT 
        company_location,
        job_title,
        salary_usd
    FROM ai_job.dbo.ai_job_dataset
    WHERE salary_usd IS NOT NULL
),

Aggregated AS (
    -- Step 2.2: Aggregate average salary, job count, and salary deviation
    SELECT 
        company_location,
        job_title,
        COUNT(*) AS total_jobs,
        ROUND(AVG(salary_usd), 2) AS avg_salary,
        ROUND(STDEV(salary_usd), 2) AS std_dev,
        ROUND((STDEV(salary_usd) / NULLIF(AVG(salary_usd), 0)) * 100, 2) AS std_dev_percent
    FROM BaseStats
    GROUP BY company_location, job_title
),

Ranked AS (
    -- Step 2.3: Rank job titles by highest average salary per country
    SELECT 
        company_location,
        job_title,
        total_jobs,
        avg_salary,
        std_dev,
        std_dev_percent,
        ROW_NUMBER() OVER (PARTITION BY company_location ORDER BY avg_salary DESC) AS rank_in_country
    FROM Aggregated
)

-- Step 2.4: Select final Top 5 results per country
SELECT 
    company_location,
    rank_in_country,          
    job_title,
    total_jobs,
    FORMAT(avg_salary, 'N2') AS avg_salary,
    FORMAT(std_dev, 'N2') AS std_dev,
    -- ✅ Display standard deviation as percentage with 2 decimals
    FORMAT(std_dev_percent / 100.0, 'P2') AS std_dev_percent
FROM Ranked
WHERE rank_in_country <= 5
ORDER BY company_location, avg_salary DESC;

---------------------------------------------------------------
-- 🧠 Skill Competitiveness Index (SCI v2 – Demand-Weighted)
-- Purpose: Identify skills that combine high demand, strong pay, and low volatility.
---------------------------------------------------------------
-- Step 3️: Calculate SCI score for top 20 skills

SELECT TOP 20
    TRIM(value) AS skill,
    COUNT(*) AS demand_count,
    ROUND(AVG(salary_usd), 2) AS avg_salary,
    ROUND(STDEV(salary_usd), 2) AS salary_stddev,

    -- Step 3.1: Show volatility as percentage
    FORMAT((STDEV(salary_usd) / NULLIF(AVG(salary_usd), 0)), 'P2') AS stddev_percent,

    -- Step 3.2: Compute Skill Competitiveness Index
    ROUND(
        (AVG(salary_usd) * POWER(COUNT(*), 0.4)) /
        NULLIF((STDEV(salary_usd) / NULLIF(AVG(salary_usd), 0)) * 100, 0),
        2
    ) AS skill_competitiveness_index

FROM ai_job.dbo.ai_job_dataset
CROSS APPLY STRING_SPLIT(required_skills, ',')

WHERE TRIM(value) <> '' 
  AND salary_usd IS NOT NULL

GROUP BY TRIM(value)
HAVING COUNT(*) > 30

ORDER BY skill_competitiveness_index DESC;

---------------------------------------------------------------
-- 📈 Monthly Salary Growth by Job Title (Final – Clean Formatting)
-- Purpose: Detect roles showing the strongest salary growth trends in 2025.
---------------------------------------------------------------
WITH MonthlySalary AS (
    -- Step 4.1: Calculate average monthly salary for each job title
    SELECT 
        job_title,
        DATEPART(MONTH, posting_date) AS month_number,
        AVG(CAST(salary_usd AS FLOAT)) AS avg_salary_raw
    FROM ai_job.dbo.ai_job_dataset
    WHERE YEAR(posting_date) = 2025
    GROUP BY job_title, DATEPART(MONTH, posting_date)
),

GrowthCalc AS (
    -- Step 4.2: Measure growth between first and last months
    SELECT 
        job_title,
        MIN(month_number) AS first_month,
        MAX(month_number) AS last_month,
        MIN(avg_salary_raw) AS first_salary,
        MAX(avg_salary_raw) AS last_salary,
        ROUND(
            ((MAX(avg_salary_raw) - MIN(avg_salary_raw)) / NULLIF(MIN(avg_salary_raw), 0)) * 100, 
            2
        ) AS avg_monthly_growth,
        FORMAT(
            ((MAX(avg_salary_raw) - MIN(avg_salary_raw)) / NULLIF(MIN(avg_salary_raw), 0)), 
            'P2'
        ) AS salary_growth_percent
    FROM MonthlySalary
    GROUP BY job_title
),

Volatility AS (
    -- Step 4.3: Calculate salary variability and yearly average
    SELECT 
        job_title,
        ROUND(AVG(avg_salary_raw), 2) AS yearly_avg_salary,
        ROUND(STDEV(avg_salary_raw), 2) AS salary_stddev,
        ROUND((STDEV(avg_salary_raw) / NULLIF(AVG(avg_salary_raw), 0)) * 100, 2) AS volatility_percent
    FROM MonthlySalary
    GROUP BY job_title
),

JobCount AS (
    -- Step 4.4: Count total job listings in 2025
    SELECT 
        job_title,
        COUNT(*) AS total_jobs
    FROM ai_job.dbo.ai_job_dataset
    WHERE YEAR(posting_date) = 2025
    GROUP BY job_title
),

TrendSlope AS (
    -- Step 4.5: Compute slope to assess growth trend direction
    SELECT 
        m.job_title,
        ROUND(
            SUM((m.month_number - a.x_mean) * (m.avg_salary_raw - a.y_mean)) /
            NULLIF(SUM(POWER(m.month_number - a.x_mean, 2)), 0), 
            2
        ) AS trend_slope
    FROM MonthlySalary m
    JOIN (
        SELECT 
            job_title,
            AVG(month_number * 1.0) AS x_mean,
            AVG(avg_salary_raw * 1.0) AS y_mean
        FROM MonthlySalary
        GROUP BY job_title
    ) a ON m.job_title = a.job_title
    GROUP BY m.job_title
)

-- Step 4.6: Final result combining growth, volatility, and slope
SELECT 
    j.job_title,
    j.total_jobs,
    FORMAT(v.yearly_avg_salary, 'N2') AS yearly_avg_salary,
    FORMAT(v.volatility_percent, 'N2') AS volatility_percent,
    FORMAT(100.0 * j.total_jobs / SUM(j.total_jobs) OVER() / 100.0, 'P2') AS market_share_percent,
    FORMAT(t.trend_slope, 'N2') AS trend_slope,
    FORMAT(g.avg_monthly_growth, 'N2') AS avg_monthly_growth,
    g.salary_growth_percent,
    FORMAT(
        ((ISNULL(t.trend_slope, 0) * 0.4) + (ISNULL(g.avg_monthly_growth, 0) * 0.6))
        / NULLIF(v.volatility_percent, 0),
        'P2'
    ) AS composite_growth_index
FROM JobCount j
LEFT JOIN Volatility v ON j.job_title = v.job_title
LEFT JOIN TrendSlope t ON j.job_title = t.job_title
LEFT JOIN GrowthCalc g ON j.job_title = g.job_title
ORDER BY j.total_jobs DESC;


--------------------------------------------------------------- 
-- 🌐 Remote Work Potential & Compensation by Job Title
-- Purpose: Evaluate remote flexibility and salary stability across AI roles.
---------------------------------------------------------------
WITH BaseData AS (
    -- Step 5.1: Prepare dataset for remote analysis
    SELECT 
        job_title,
        remote_ratio,
        salary_usd
    FROM ai_job.dbo.ai_job_dataset
    WHERE job_title IS NOT NULL AND salary_usd IS NOT NULL
),
Aggregated AS (
    -- Step 5.2: Aggregate average salary, salary risk, and remote ratios
    SELECT 
        job_title,
        COUNT(*) AS total_jobs,
        ROUND(AVG(CAST(remote_ratio AS FLOAT)), 2) AS avg_remote_score,
        ROUND(AVG(salary_usd), 2) AS avg_salary,
        ROUND(STDEV(salary_usd), 2) AS salary_stddev,
        ROUND((STDEV(salary_usd) / NULLIF(AVG(salary_usd), 0)) * 100, 2) AS salary_risk_percent,
        ROUND(SUM(CASE WHEN remote_ratio = 100 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS fully_remote_percent,
        ROUND(SUM(CASE WHEN remote_ratio BETWEEN 1 AND 99 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS hybrid_percent,
        ROUND(SUM(CASE WHEN remote_ratio = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS onsite_percent
    FROM BaseData
    GROUP BY job_title
),
Ranked AS (
    -- Step 5.3: Calculate composite Remote Readiness Score
    SELECT 
        job_title,
        total_jobs,
        avg_salary,
        salary_risk_percent,
        avg_remote_score,
        fully_remote_percent,
        hybrid_percent,
        onsite_percent,
        ROUND((
            (avg_remote_score * 0.5) + 
            (fully_remote_percent * 0.3) + 
            ((100 - salary_risk_percent) * 0.2)
        ), 2) AS remote_readiness_score
    FROM Aggregated
)

-- Step 5.4: Final output ordered by readiness and salary
SELECT 
    job_title,
    total_jobs,
    FORMAT(avg_salary, 'N2') AS avg_salary,
    FORMAT(salary_risk_percent / 100.0, 'P2') AS salary_risk_percent,
    avg_remote_score,
    FORMAT(fully_remote_percent / 100.0, 'P2') AS fully_remote_percent,
    FORMAT(hybrid_percent / 100.0, 'P2') AS hybrid_percent,
    FORMAT(onsite_percent / 100.0, 'P2') AS onsite_percent,
    remote_readiness_score
FROM Ranked
ORDER BY remote_readiness_score DESC, avg_salary DESC;


---------------------------------------------------------------
-- 📊 Salary Growth by Experience Level
-- Purpose: Compare salary growth, volatility, and progression across
-- Entry, Mid, Senior, and Expert experience tiers.
---------------------------------------------------------------
WITH LevelStats AS (
    -- Step 6.1: Aggregate salary metrics by experience level
    SELECT 
        experience_level,
        COUNT(*) AS total_jobs,
        ROUND(AVG(CAST(salary_usd AS FLOAT)), 2) AS avg_salary,
        ROUND(MIN(CAST(salary_usd AS FLOAT)), 2) AS min_salary,
        ROUND(MAX(CAST(salary_usd AS FLOAT)), 2) AS max_salary,
        ROUND(STDEV(CAST(salary_usd AS FLOAT)), 2) AS std_dev,
        ROUND((STDEV(CAST(salary_usd AS FLOAT)) / NULLIF(AVG(CAST(salary_usd AS FLOAT)), 0)) * 100, 2) AS volatility_pct
    FROM ai_job.dbo.ai_job_dataset
    WHERE salary_usd IS NOT NULL AND experience_level IS NOT NULL
    GROUP BY experience_level
),
MedianStats AS (
    -- Step 6.2: Compute median salary per experience level
    SELECT DISTINCT
        experience_level,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_usd)
            OVER (PARTITION BY experience_level) AS median_salary
    FROM ai_job.dbo.ai_job_dataset
    WHERE salary_usd IS NOT NULL AND experience_level IS NOT NULL
),
Merged AS (
    -- Step 6.3: Merge median and average salary data
    SELECT 
        L.experience_level,
        L.total_jobs,
        L.avg_salary,
        M.median_salary,
        L.min_salary,
        L.max_salary,
        L.std_dev,
        L.volatility_pct
    FROM LevelStats L
    JOIN MedianStats M ON L.experience_level = M.experience_level
),
Ordered AS (
    -- Step 6.4: Assign ordering for experience hierarchy
    SELECT 
        experience_level,
        total_jobs,
        avg_salary,
        median_salary,
        min_salary,
        max_salary,
        std_dev,
        volatility_pct,
        CASE 
            WHEN experience_level = 'EN' THEN 1
            WHEN experience_level = 'MI' THEN 2
            WHEN experience_level = 'SE' THEN 3
            WHEN experience_level = 'EX' THEN 4
            ELSE 5
        END AS exp_order
    FROM Merged
),
GrowthCalc AS (
    -- Step 6.5: Calculate salary growth relative to previous level
    SELECT 
        experience_level,
        total_jobs,
        avg_salary,
        median_salary,
        min_salary,
        max_salary,
        std_dev,
        volatility_pct,
        exp_order,
        LAG(avg_salary) OVER (ORDER BY exp_order) AS prev_avg_salary
    FROM Ordered
)

-- Step 6.6: Final output showing salary evolution by experience level
SELECT 
    experience_level,
    total_jobs,
    FORMAT(avg_salary, 'N2') AS avg_salary,
    FORMAT(median_salary, 'N2') AS median_salary,
    FORMAT(min_salary, 'N2') AS min_salary,
    FORMAT(max_salary, 'N2') AS max_salary,
    FORMAT(std_dev, 'N2') AS std_dev,
    FORMAT((std_dev / NULLIF(avg_salary, 0)), 'P2') AS std_dev_percent,  -- ✅ New column: Standard Deviation as %
    FORMAT(volatility_pct, 'N2') AS volatility_pct,
    CASE 
        WHEN prev_avg_salary IS NULL THEN 'Base Level'
        ELSE CONCAT(
            CASE 
                WHEN ((avg_salary - prev_avg_salary) / NULLIF(prev_avg_salary, 0) * 100) > 0 THEN '+'
                ELSE ''
            END,
            FORMAT(((avg_salary - prev_avg_salary) / NULLIF(prev_avg_salary, 0) * 100), 'N2'),
            '%'
        )
    END AS growth_from_previous
FROM GrowthCalc
ORDER BY exp_order;
