"""
FraudLens AI - FastAPI Application
Purpose: Exposes the deterministic AI capabilities to Power BI and internal web applications.
Follows a strictly typed, lightweight REST architectural pattern.
"""

from fastapi import FastAPI, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from .database import db
from .services import ai_service

app = FastAPI(
    title="FraudLens AI - GenAI Investigation API",
    description="Deterministic AI Layer for American Express Fraud Analytics",
    version="1.0.0"
)

# --- Pydantic Data Models (Input Validation) ---
class TransactionRequest(BaseModel):
    transaction_id: str

class ExecutiveRequest(BaseModel):
    day: int

class CustomerRequest(BaseModel):
    customer_id: str

class DashboardInsightRequest(BaseModel):
    kpi_payload: dict


# --- REST Endpoints ---

@app.post("/api/investigate", tags=["AI Copilot"])
def investigate_transaction(request: TransactionRequest, session: Session = Depends(db.get_db)):
    """Generates an AI Investigation Dossier for a specific transaction."""
    # 1. Retrieve Deterministic Facts
    txn_data = db.get_transaction_details(session, request.transaction_id)
    if not txn_data:
        raise HTTPException(status_code=404, detail="Transaction not found in Data Warehouse.")
    
    # 2. Generate Explainable AI Narrative
    ai_response = ai_service.analyze_transaction(txn_data)
    
    # 3. Return Structured Response
    return {"transaction_id": request.transaction_id, "ai_investigation_card": ai_response}


@app.post("/api/executive-summary", tags=["AI Copilot"])
def generate_executive_summary(request: ExecutiveRequest, session: Session = Depends(db.get_db)):
    """Generates a C-Level macro summary of the day's fraud health."""
    kpi_data = db.get_executive_kpis(session, request.day)
    if not kpi_data:
        raise HTTPException(status_code=404, detail="No aggregated data found for the requested day.")
        
    ai_response = ai_service.generate_executive_report(kpi_data)
    
    return {"day": request.day, "executive_summary": ai_response}


@app.post("/api/customer-summary", tags=["AI Copilot"])
def investigate_customer(request: CustomerRequest, session: Session = Depends(db.get_db)):
    """Generates a behavioral risk profile for a specific customer."""
    cust_data = db.get_customer_details(session, request.customer_id)
    if not cust_data:
        raise HTTPException(status_code=404, detail="Customer not found in Customer Summary table.")
        
    ai_response = ai_service.analyze_customer(cust_data)
    
    return {"customer_id": request.customer_id, "customer_profile": ai_response}


@app.post("/api/dashboard-insights", tags=["AI Copilot"])
def dashboard_insights(request: DashboardInsightRequest):
    """Generates dynamic business recommendations based on active Power BI filters."""
    # No SQL required here. Power BI passes its aggregated visual context directly.
    if not request.kpi_payload:
        raise HTTPException(status_code=400, detail="Empty dashboard context payload.")
        
    ai_response = ai_service.generate_dashboard_insights(request.kpi_payload)
    
    return {"ai_insights": ai_response}
