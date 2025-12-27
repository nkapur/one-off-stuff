"""
Payment Event Processor

This Lambda function processes payment events from Kinesis.
It automatically scales to zero when no events are available.

NOTE: Payment processing requires careful error handling and idempotency.
"""

import base64
import json
import logging
import os
from typing import Any
from datetime import datetime
import hashlib

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "INFO")
logger = logging.getLogger()
logger.setLevel(log_level)

# Simulated processed payment cache (use DynamoDB in production)
_processed_payments = set()


def process_event(event: dict, context: Any) -> dict:
    """
    Process payment events from Kinesis stream.
    
    Args:
        event: Kinesis event containing records
        context: Lambda context object
    
    Returns:
        Processing result with success/failure details
    """
    logger.info(f"Processing {len(event.get('Records', []))} payment records")
    
    successful_records = 0
    failed_records = []
    
    for record in event.get("Records", []):
        kinesis_data = None
        try:
            # Decode the Kinesis record
            kinesis_data = record["kinesis"]
            sequence_number = kinesis_data["sequenceNumber"]
            
            # Decode base64 data
            raw_data = base64.b64decode(kinesis_data["data"])
            payload = json.loads(raw_data.decode("utf-8"))
            
            logger.debug(f"Processing payment record {sequence_number}")
            
            # ============================================================
            # PAYMENT PROCESSING LOGIC
            # ============================================================
            payment_id = payload.get("payment_id")
            order_id = payload.get("order_id")
            customer_id = payload.get("customer_id")
            payment_type = payload.get("type")  # initiated, authorized, captured, refunded, failed
            amount = payload.get("amount", 0)
            currency = payload.get("currency", "USD")
            payment_method = payload.get("payment_method")
            timestamp = payload.get("timestamp", datetime.utcnow().isoformat())
            
            # Validate required fields
            if not payment_id:
                raise ValueError("payment_id is required")
            if not order_id:
                raise ValueError("order_id is required")
            if amount <= 0:
                raise ValueError("amount must be positive")
            
            # Idempotency check - prevent duplicate processing
            idempotency_key = _generate_idempotency_key(payment_id, payment_type)
            if _is_already_processed(idempotency_key):
                logger.info(f"Payment already processed (idempotent): {payment_id}")
                successful_records += 1
                continue
            
            # Process based on payment type
            if payment_type == "initiated":
                _handle_payment_initiated(payment_id, order_id, customer_id, amount, currency)
            elif payment_type == "authorized":
                _handle_payment_authorized(payment_id, order_id, amount)
            elif payment_type == "captured":
                _handle_payment_captured(payment_id, order_id, amount)
            elif payment_type == "refunded":
                _handle_payment_refunded(payment_id, order_id, amount, payload.get("refund_reason"))
            elif payment_type == "failed":
                _handle_payment_failed(payment_id, order_id, payload.get("failure_reason"))
            else:
                raise ValueError(f"Unknown payment type: {payment_type}")
            
            # Mark as processed
            _mark_as_processed(idempotency_key)
            
            logger.info(
                f"Processed payment: id={payment_id}, type={payment_type}, "
                f"amount={amount} {currency}"
            )
            
            # ============================================================
            
            successful_records += 1
            
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in payment record: {e}")
            failed_records.append({
                "sequenceNumber": kinesis_data.get("sequenceNumber") if kinesis_data else None,
                "error": f"Invalid JSON: {str(e)}"
            })
            
        except ValueError as e:
            logger.error(f"Validation error: {e}")
            failed_records.append({
                "sequenceNumber": kinesis_data.get("sequenceNumber") if kinesis_data else None,
                "error": f"Validation error: {str(e)}"
            })
            
        except Exception as e:
            logger.exception(f"Error processing payment record: {e}")
            failed_records.append({
                "sequenceNumber": kinesis_data.get("sequenceNumber") if kinesis_data else None,
                "error": str(e)
            })
    
    result = {
        "batchSize": len(event.get("Records", [])),
        "successfulRecords": successful_records,
        "failedRecords": len(failed_records),
        "failures": failed_records
    }
    
    logger.info(f"Payment batch complete: {successful_records} succeeded, {len(failed_records)} failed")
    
    if failed_records:
        return {
            "batchItemFailures": [
                {"itemIdentifier": f["sequenceNumber"]} 
                for f in failed_records 
                if f.get("sequenceNumber")
            ]
        }
    
    return result


def _generate_idempotency_key(payment_id: str, payment_type: str) -> str:
    """Generate idempotency key for payment processing."""
    key = f"{payment_id}:{payment_type}"
    return hashlib.sha256(key.encode()).hexdigest()


def _is_already_processed(idempotency_key: str) -> bool:
    """Check if payment was already processed (use DynamoDB in production)."""
    return idempotency_key in _processed_payments


def _mark_as_processed(idempotency_key: str):
    """Mark payment as processed (use DynamoDB in production)."""
    _processed_payments.add(idempotency_key)


def _handle_payment_initiated(
    payment_id: str, 
    order_id: str, 
    customer_id: str, 
    amount: float, 
    currency: str
):
    """Handle payment initiation."""
    logger.info(f"Payment initiated: {payment_id} for order {order_id}")
    # TODO: Implement payment initiation logic
    # - Create payment record
    # - Call payment gateway
    # - Update order status


def _handle_payment_authorized(payment_id: str, order_id: str, amount: float):
    """Handle payment authorization."""
    logger.info(f"Payment authorized: {payment_id}")
    # TODO: Implement authorization logic
    # - Update payment status
    # - Reserve funds
    # - Proceed with fulfillment


def _handle_payment_captured(payment_id: str, order_id: str, amount: float):
    """Handle payment capture."""
    logger.info(f"Payment captured: {payment_id}")
    # TODO: Implement capture logic
    # - Finalize payment
    # - Update accounting records
    # - Send receipt


def _handle_payment_refunded(payment_id: str, order_id: str, amount: float, reason: str):
    """Handle payment refund."""
    logger.info(f"Payment refunded: {payment_id}, reason: {reason}")
    # TODO: Implement refund logic
    # - Process refund with gateway
    # - Update payment and order status
    # - Send refund notification


def _handle_payment_failed(payment_id: str, order_id: str, failure_reason: str):
    """Handle payment failure."""
    logger.error(f"Payment failed: {payment_id}, reason: {failure_reason}")
    # TODO: Implement failure handling
    # - Update payment status
    # - Send failure notification
    # - Trigger retry or escalation

