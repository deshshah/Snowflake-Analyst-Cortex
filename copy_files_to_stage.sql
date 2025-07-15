use role cortex_user_role;
use database cortex_analyst_demo;
use schema revenue_timeseries;

-- Pull the latest changes from the git repository
ALTER GIT REPOSITORY cortex_analyst_demo.git_repos.getting_started_with_cortex_analyst FETCH;

-- Copy files from the git repository to the stage
COPY FILES
    INTO @raw_data/
    FROM @cortex_analyst_demo.git_repos.getting_started_with_cortex_analyst/branches/main/data/;

-- copy the semantic model file to the stage
COPY FILES
    INTO @raw_data/
    FROM @cortex_analyst_demo.git_repos.getting_started_with_cortex_analyst/branches/main/revenue_timeseries.yaml;