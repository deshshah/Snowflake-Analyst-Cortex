
"""
Cortex Analyst App (External Version)
======================================
This app allows users to interact with Snowflake Cortex Analyst using natural language.
Run locally or on Streamlit Cloud.
"""

import json
import time
from datetime import datetime
from typing import Dict, List, Optional, Tuple, Union

import pandas as pd
import requests
import streamlit as st
import snowflake.connector

# ---------------- CONFIG ----------------
DATABASE = "CORTEX_ANALYST_DEMO"
SCHEMA = "REVENUE_TIMESERIES"
STAGE = "RAW_DATA"
FILE = "revenue_timeseries.yaml"
API_ENDPOINT = "/api/v2/cortex/analyst/message"
FEEDBACK_API_ENDPOINT = "/api/v2/cortex/analyst/feedback"
API_TIMEOUT = 50  # seconds

# ---------------- SNOWFLAKE CONNECTION ----------------
if "CONN" not in st.session_state or st.session_state.CONN is None:
    st.session_state.CONN = snowflake.connector.connect(
        user=st.secrets["user"],  # Use Streamlit secrets for security
        password=st.secrets["password"],
        account=st.secrets["account"],  # e.g., "rnb41345.eu-west-1"
        warehouse="CORTEX_ANALYST_WH",
        role="CORTEX_USER_ROLE",
        database=DATABASE,
        schema=SCHEMA,
    )

# ---------------- SESSION STATE INIT ----------------
def reset_session_state():
    st.session_state.messages = []
    st.session_state.active_suggestion = None
    st.session_state.warnings = []
    st.session_state.form_submitted = {}

if "messages" not in st.session_state:
    reset_session_state()

# ---------------- UI HEADER ----------------
st.title("Cortex Analyst")
st.markdown("Ask questions about your data using natural language.")

with st.sidebar:
    st.selectbox(
        "Selected semantic model:",
        [f"{DATABASE}.{SCHEMA}.{STAGE}/{FILE}"],
        format_func=lambda s: s.split("/")[-1],
        key="selected_semantic_model_path",
        on_change=reset_session_state,
    )
    st.divider()
    if st.button("Clear Chat History"):
        reset_session_state()

# ---------------- API CALL ----------------
def get_analyst_response(messages: List[Dict]) -> Tuple[Dict, Optional[str]]:
    request_body = {
        "messages": messages,
        "semantic_model_file": f"@{st.session_state.selected_semantic_model_path}",
    }

    url = f"https://{st.secrets['account']}.snowflakecomputing.com{API_ENDPOINT}"
    headers = {
        "Authorization": f'Snowflake Token="{st.session_state.CONN.rest.token}"',
        "Content-Type": "application/json",
    }

    try:
        resp = requests.post(url, json=request_body, headers=headers, timeout=API_TIMEOUT)
        parsed_content = resp.json()
        if resp.status_code < 400:
            return parsed_content, None
        else:
            
    error_msg = f"""
    🚨 Analyst API Error 🚨
    * Status: `{resp.status_code}`
    * Request ID: `{parsed_content.get('request_id')}`
    * Error Code: `{parsed_content.get('error_code')}`
    Message:

