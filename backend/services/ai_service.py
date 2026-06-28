"""
FraudLens AI - AI Integration Service
Purpose: The core engine that orchestrates MySQL data retrieval, Prompt formatting, and Gemini API calls.
"""

import os
import json
import logging
import requests
from ..prompts.templates import (
    TRANSACTION_INVESTIGATION_PROMPT,
    EXECUTIVE_SUMMARY_PROMPT,
    CUSTOMER_INVESTIGATION_PROMPT,
    DASHBOARD_INSIGHT_PROMPT
)

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
# Using the standard gemini-1.5-pro or similar text endpoint
GEMINI_URL = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro-latest:generateContent?key={GEMINI_API_KEY}"

def call_gemini_api(prompt: str) -> str:
    """Lightweight, resilient wrapper for the Gemini REST API."""
    if not GEMINI_API_KEY:
        raise ValueError("GEMINI_API_KEY environment variable is missing.")

    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.2, # Low temperature ensures analytical, deterministic responses
            "maxOutputTokens": 1000
        }
    }
    headers = {"Content-Type": "application/json"}
    
    try:
        response = requests.post(GEMINI_URL, headers=headers, json=payload, timeout=15)
        response.raise_for_status()
        data = response.json()
        
        # Parse the structured text from Gemini
        try:
            return data["candidates"][0]["content"]["parts"][0]["text"]
        except (KeyError, IndexError):
            return "Error: Unexpected response format from Gemini API."
            
    except requests.exceptions.Timeout:
        logging.error("Gemini API Timeout.")
        return "Error: AI Copilot timed out. Please try again or review raw data."
    except requests.exceptions.RequestException as e:
        logging.error(f"Gemini API Request Failed: {e}")
        return "Error: AI Copilot is currently unavailable."

def analyze_transaction(txn_data: dict) -> str:
    """Injects structured MySQL data into the Transaction Prompt."""
    prompt = TRANSACTION_INVESTIGATION_PROMPT.format(
        txn_id=txn_data.get("transaction_id"),
        amount=txn_data.get("amount"),
        risk_score=txn_data.get("risk_score"),
        priority=txn_data.get("priority"),
        type=txn_data.get("type"),
        account_drained=txn_data.get("account_drained"),
        historic_fraud_rate=txn_data.get("fraud_percentage", 0.0)
    )
    return call_gemini_api(prompt)

def generate_executive_report(kpi_data: dict) -> str:
    """Injects macro health metrics into the Executive Summary Prompt."""
    prompt = EXECUTIVE_SUMMARY_PROMPT.format(
        date=kpi_data.get("day"),
        total_txns=kpi_data.get("total_transactions"),
        fraud_txns=kpi_data.get("fraud_transactions"),
        fraud_rate=kpi_data.get("fraud_percentage"),
        fraud_exposure=kpi_data.get("fraud_amount"),
        highest_fraud=kpi_data.get("highest_fraud_amount")
    )
    return call_gemini_api(prompt)

def analyze_customer(cust_data: dict) -> str:
    """Injects customer lifetime behavior into the Profile Prompt."""
    prompt = CUSTOMER_INVESTIGATION_PROMPT.format(
        customer_id=cust_data.get("customer_id"),
        total_txns=cust_data.get("total_transactions"),
        fraud_txns=cust_data.get("fraud_transactions"),
        fraud_rate=cust_data.get("fraud_percentage"),
        avg_amount=cust_data.get("average_amount"),
        drains=cust_data.get("account_drained_count"),
        high_risk_flag=cust_data.get("high_risk_customer_flag")
    )
    return call_gemini_api(prompt)

def generate_dashboard_insights(kpi_json: dict) -> str:
    """Passes arbitrary Power BI filter context to the Insight Prompt."""
    prompt = DASHBOARD_INSIGHT_PROMPT.format(
        kpi_json_dump=json.dumps(kpi_json, indent=2)
    )
    return call_gemini_api(prompt)
