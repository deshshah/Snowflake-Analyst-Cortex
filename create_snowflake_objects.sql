/*--
• Database, schema, warehouse, and stage creation
--*/

USE ROLE SECURITYADMIN;

CREATE ROLE IF NOT EXISTS cortex_user_role;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE cortex_user_role;

-- Grant role to current user
SET current_user = (SELECT CURRENT_USER());
GRANT ROLE cortex_user_role TO USER IDENTIFIER($current_user);

USE ROLE sysadmin;

-- Create demo database
CREATE OR REPLACE DATABASE cortex_analyst_demo;

-- Create schema
CREATE OR REPLACE SCHEMA cortex_analyst_demo.revenue_timeseries;

-- Create warehouse
CREATE OR REPLACE WAREHOUSE cortex_analyst_wh
    WAREHOUSE_SIZE = 'large'
    WAREHOUSE_TYPE = 'standard'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
COMMENT = 'Warehouse for Cortex Analyst demo';

GRANT USAGE ON WAREHOUSE cortex_analyst_wh TO ROLE cortex_user_role;
GRANT OPERATE ON WAREHOUSE cortex_analyst_wh TO ROLE cortex_user_role;

GRANT OWNERSHIP ON SCHEMA cortex_analyst_demo.revenue_timeseries TO ROLE cortex_user_role;
GRANT OWNERSHIP ON DATABASE cortex_analyst_demo TO ROLE cortex_user_role;

ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_US';

-- Use the created warehouse/database/schema/role.
USE WAREHOUSE cortex_analyst_wh;
USE DATABASE cortex_analyst_demo;
USE SCHEMA cortex_analyst_demo.revenue_timeseries;
USE ROLE cortex_user_role;


-- Create stage for raw data
CREATE OR REPLACE STAGE raw_data DIRECTORY = (ENABLE = TRUE);

/*--
• Fact and Dimension Table Creation
--*/

-- Fact table: daily_revenue
CREATE OR REPLACE TABLE cortex_analyst_demo.revenue_timeseries.daily_revenue (
    date DATE,
    revenue FLOAT,
    cogs FLOAT,
    forecasted_revenue FLOAT,
    product_id INT,
    region_id INT
);

-- Dimension table: product_dim
CREATE OR REPLACE TABLE cortex_analyst_demo.revenue_timeseries.product_dim (
    product_id INT,
    product_line VARCHAR
);

-- Dimension table: region_dim
CREATE OR REPLACE TABLE cortex_analyst_demo.revenue_timeseries.region_dim (
    region_id INT,
    sales_region VARCHAR,
    state VARCHAR
);

-- Create the search service.
CREATE OR REPLACE CORTEX SEARCH SERVICE product_line_search_service
  ON product_dimension
  WAREHOUSE = cortex_analyst_wh
  TARGET_LAG = '1 hour'
  AS (
      SELECT DISTINCT product_line AS product_dimension FROM product_dim
  );

USE ROLE accountadmin;

-- Create a Git API integration for Snowflake Labs
-- This integration allows access to GitHub repositories under Snowflake-Labs
-- It is used for accessing demo data and scripts from the Snowflake Labs GitHub organization
CREATE OR REPLACE API INTEGRATION snowflake_labs_git_integration
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/Snowflake-Labs/')
  ENABLED = TRUE;

USE ROLE cortex_user_role;
-- Create a schema for Git repositories
-- This schema will contain Git repositories for the Cortex Analyst demo
CREATE OR REPLACE SCHEMA cortex_analyst_demo.git_repos;

USE SCHEMA git_repos;

-- Create a Git repository for the Cortex Analyst demo
-- This repository contains scripts and data for the Cortex Analyst demo
CREATE OR REPLACE GIT REPOSITORY getting_started_with_cortex_analyst
  API_INTEGRATION = snowflake_labs_git_integration
  ORIGIN = 'https://github.com/Snowflake-Labs/sfguide-getting-started-with-cortex-analyst';

-- Fetch the latest content from the Git repository
ALTER GIT REPOSITORY getting_started_with_cortex_analyst FETCH;

-- Copy that data from git into a staging area.
COPY FILES INTO @cortex_analyst_demo.revenue_timeseries.raw_data
FROM @getting_started_with_cortex_analyst/branches/main/revenue_timeseries.yaml;

COPY FILES INTO @cortex_analyst_demo.revenue_timeseries.raw_data
FROM @getting_started_with_cortex_analyst/branches/main/data;

USE SCHEMA revenue_timeseries;

-- Define the CSV file format.
CREATE OR REPLACE FILE FORMAT demo_data_csv_format
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_DELIMITER = ','
    TRIM_SPACE = FALSE
    FIELD_OPTIONALLY_ENCLOSED_BY = NONE
    REPLACE_INVALID_CHARACTERS = TRUE
    DATE_FORMAT = AUTO
    TIME_FORMAT = AUTO
    TIMESTAMP_FORMAT = AUTO
    EMPTY_FIELD_AS_NULL = FALSE
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

-- Ingest the CSV data.
COPY INTO daily_revenue
FROM @raw_data
FILES = ('data/daily_revenue.csv')
FILE_FORMAT = demo_data_csv_format
ON_ERROR = ABORT_STATEMENT
FORCE = TRUE;

COPY INTO product_dim
FROM @raw_data
FILES = ('data/product.csv')
FILE_FORMAT = demo_data_csv_format
ON_ERROR = ABORT_STATEMENT
FORCE = TRUE;

COPY INTO region_dim
FROM @raw_data
FILES = ('data/region.csv')
FILE_FORMAT = demo_data_csv_format
ON_ERROR = ABORT_STATEMENT
FORCE = TRUE;

/*--
• Setup Validation
--*/

SELECT 'Table' as "TYPE", table_name AS created
FROM cortex_analyst_demo.information_schema.tables
WHERE table_schema = 'REVENUE_TIMESERIES'
UNION ALL
SELECT 'Git Repository', git_repository_name
FROM cortex_analyst_demo.information_schema.git_repositories
WHERE git_repository_name = 'GETTING_STARTED_WITH_CORTEX_ANALYST'
UNION ALL
SELECT 'Search Service', service_name
FROM cortex_analyst_demo.information_schema.cortex_search_services
UNION ALL
SELECT 'Table rows: Revenue days', CAST(count(*) as STRING) FROM cortex_analyst_demo.revenue_timeseries.daily_revenue
UNION ALL
SELECT 'Table rows: Products', CAST(count(*) as STRING) FROM cortex_analyst_demo.revenue_timeseries.product_dim
UNION ALL
SELECT 'Table rows: Regions', CAST(count(*) as STRING) FROM cortex_analyst_demo.revenue_timeseries.region_dim
ORDER BY 1, 2;
