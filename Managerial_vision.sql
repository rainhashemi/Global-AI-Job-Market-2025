ِ-- 📊 Global AI Job Market Analysis (2025)
-- 👔 Manager’s Perspective: Salary, Benefits, and Hiring Insights
-- Author: [Baran Hashemi]
-- Tools: SQL Server 2022


-- Preview data
SELECT * 
FROM ai_job.dbo.ai_job_dataset;

---------------------------------------------------------------
-- Median, P75, and Average Salary by Job Title & Country (Top 5 per Country)
---------------------------------------------------------------
;WITH SalaryStats AS (
    -- Step 1: Calculate Median, P75, and Average salary per job title and country
    SELECT 
        company_location,
        job_title,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_usd) 
            OVER (PARTITION BY company_location, job_title) AS median_salary,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_usd) 
            OVER (PARTITION BY company_location, job_title) AS p75_salary,
        AVG(salary_usd) OVER (PARTITION BY company_location, job_title) AS avg_salary
    FROM ai_job.dbo.ai_job_dataset
),
DistinctStats AS (
    -- Step 2: Remove duplicate rows caused by window functions
    SELECT DISTINCT
        company_location,
        job_title,
        median_salary,
        p75_salary,
        avg_salary
    FROM SalaryStats
),
RankedStats AS (
    -- Step 3: Rank job titles within each country by median salary
    SELECT 
        company_location,
        job_title,
        median_salary,
        p75_salary,
        avg_salary,
        ROW_NUMBER() OVER (PARTITION BY company_location ORDER BY median_salary DESC) AS rank_in_country
    FROM DistinctStats
)
-- Step 4: Select only Top 5 highest-paying job titles per country
SELECT 
    company_location,
    job_title,
    median_salary,
    p75_salary,
    avg_salary
FROM RankedStats
WHERE rank_in_country <= 5
ORDER BY company_location, median_salary DESC;

GO

---------------------------------------------------------------
-- Average Salary and Job Count by Country
---------------------------------------------------------------
SELECT 
    company_location,
    COUNT(*) AS total_jobs,                                -- Total number of job postings
    ROUND(AVG(COALESCE(salary_usd, 0)), 2) AS avg_salary,  -- Handle NULL salaries safely
    MAX(COALESCE(salary_usd, 0)) AS max_salary,            -- Highest salary per country
    MIN(COALESCE(salary_usd, 0)) AS min_salary             -- Lowest salary per country
FROM ai_job.dbo.ai_job_dataset
WHERE company_location IS NOT NULL
GROUP BY company_location
ORDER BY avg_salary DESC;

GO

---------------------------------------------------------------
-- Top 20 Most Demanded Skills in the AI Job Market
---------------------------------------------------------------
;WITH SkillData AS (
    -- Step 1: Split the required_skills column into individual skill records
    SELECT 
        TRIM(value) AS skill,
        salary_usd
    FROM ai_job.dbo.ai_job_dataset
    CROSS APPLY STRING_SPLIT(required_skills, ',')
    WHERE TRIM(value) <> '' AND salary_usd IS NOT NULL
),
SkillStats AS (
    -- Step 2: Aggregate salary and demand data for each skill
    SELECT 
        skill,
        COUNT(*) AS frequency,
        ROUND(AVG(salary_usd), 2) AS avg_salary,
        MAX(salary_usd) AS max_salary,
        MIN(salary_usd) AS min_salary
    FROM SkillData
    GROUP BY skill
)
-- Step 3: Return the Top 20 most demanded skills
SELECT TOP 20
    skill,
    frequency,
    avg_salary,
    max_salary,
    min_salary
FROM SkillStats
ORDER BY frequency DESC;

GO

---------------------------------------------------------------
-- Average Benefits Score by Industry
---------------------------------------------------------------
SELECT 
    industry,
    ROUND(AVG(benefits_score), 2) AS avg_benefit_score,
    COUNT(*) AS total_companies
FROM ai_job.dbo.ai_job_dataset
GROUP BY industry
ORDER BY avg_benefit_score DESC;

GO


-- Skills with Highest Average Salary per Posting
SELECT TOP 20
    TRIM(value) AS skill,
    COUNT(*) AS demand_count,
    ROUND(AVG(salary_usd), 2) AS avg_salary,
    ROUND(STDEV(salary_usd), 2) AS salary_stddev,
    ROUND((AVG(salary_usd) / COUNT(*)), 2) AS salary_per_job_weight
FROM ai_job.dbo.ai_job_dataset
CROSS APPLY STRING_SPLIT(required_skills, ',')
WHERE TRIM(value) <> '' AND salary_usd IS NOT NULL
GROUP BY TRIM(value)
ORDER BY avg_salary DESC;
