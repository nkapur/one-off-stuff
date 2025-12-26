"""
Order Event Processor

This Lambda function processes order events from Kinesis.
It automatically scales to zero when no events are available.
"""

import base64
import json
import logging
import os
from typing import Any
from datetime import datetime

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "INFO")
logger = logging.getLogger()
logger.setLevel(log_level)


def process_event(event: dict, context: Any) -> dict:
    """
    Process order events from Kinesis stream.
    
    Args:
        event: Kinesis event containing records
        context: Lambda context object
    
    Returns:
        Processing result with success/failure details
    """
    logger.info(f"Processing {len(event.get('Records', []))} order records")
    
    successful_records = 0
    failed_records = []
    order_alerts = os.environ.get("ENABLE_ORDER_ALERTS", "false").lower() == "true"
    
    for record in event.get("Records", []):
        kinesis_data = None
        try:
            # Decode the Kinesis record
            kinesis_data = record["kinesis"]
            sequence_number = kinesis_data["sequenceNumber"]
            
            # Decode base64 data
            raw_data = base64.b64decode(kinesis_data["data"])
            payload = json.loads(raw_data.decode("utf-8"))
            
            logger.debug(f"Processing order record {sequence_number}")
            
            # ============================================================
            # ORDER PROCESSING LOGIC
            # ============================================================
            order_id = payload.get("order_id")
            customer_id = payload.get("customer_id")
            order_type = payload.get("type")  # created, updated, cancelled, fulfilled
            items = payload.get("items", [])
            total_amount = payload.get("total_amount", 0)
            currency = payload.get("currency", "USD")
            timestamp = payload.get("timestamp", datetime.utcnow().isoformat())
            
            # Validate required fields
            if not order_id:
                raise ValueError("order_id is required")
            if not customer_id:
                raise ValueError("customer_id is required")
            
            # Process based on order type
            if order_type == "created":
                _handle_order_created(order_id, customer_id, items, total_amount, currency)
            elif order_type == "updated":
                _handle_order_updated(order_id, payload.get("updates", {}))
            elif order_type == "cancelled":
                _handle_order_cancelled(order_id, payload.get("reason"))
            elif order_type == "fulfilled":
                _handle_order_fulfilled(order_id, payload.get("fulfillment_details", {}))
            else:
                logger.warning(f"Unknown order type: {order_type}")
            
            # Send alerts for high-value orders
            if order_alerts and total_amount > 1000:
                _send_high_value_alert(order_id, total_amount, currency)
            
            logger.info(f"Processed order: id={order_id}, type={order_type}, amount={total_amount}")
            
            # ============================================================
            
            successful_records += 1
            
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in order record: {e}")
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
            logger.exception(f"Error processing order record: {e}")
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
    
    logger.info(f"Order batch complete: {successful_records} succeeded, {len(failed_records)} failed")
    
    if failed_records:
        return {
            "batchItemFailures": [
                {"itemIdentifier": f["sequenceNumber"]} 
                for f in failed_records 
                if f.get("sequenceNumber")
            ]
        }
    
    return result


def _handle_order_created(order_id: str, customer_id: str, items: list, total: float, currency: str):
    """Handle new order creation."""
    logger.info(f"New order created: {order_id} for customer {customer_id}")
    # TODO: Implement order creation logic
    # - Store in database
    # - Reserve inventory
    # - Send confirmation email


def _handle_order_updated(order_id: str, updates: dict):
    """Handle order updates."""
    logger.info(f"Order updated: {order_id}")
    # TODO: Implement order update logic


def _handle_order_cancelled(order_id: str, reason: str):
    """Handle order cancellation."""
    logger.info(f"Order cancelled: {order_id}, reason: {reason}")
    # TODO: Implement cancellation logic
    # - Release inventory
    # - Process refund if applicable
    # - Send cancellation notification


def _handle_order_fulfilled(order_id: str, fulfillment_details: dict):
    """Handle order fulfillment."""
    logger.info(f"Order fulfilled: {order_id}")
    # TODO: Implement fulfillment logic
    # - Update order status
    # - Send shipment notification


def _send_high_value_alert(order_id: str, amount: float, currency: str):
    """Send alert for high-value orders."""
    logger.info(f"High-value order alert: {order_id} - {currency} {amount}")
    # TODO: Implement alerting logic (SNS, Slack, etc.)

