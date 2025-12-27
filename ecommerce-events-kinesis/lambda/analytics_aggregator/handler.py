"""
Analytics Aggregator - Multi-Stream Consumer

This Lambda function consumes from BOTH user_activity and payments streams,
correlating user behavior with payment events for analytics purposes.
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
    Process events from multiple Kinesis streams (user_activity + payments).
    
    The event source ARN tells us which stream the record came from.
    
    Args:
        event: Kinesis event containing records from one of the source streams
        context: Lambda context object
    
    Returns:
        Processing result with success/failure details
    """
    records = event.get("Records", [])
    logger.info(f"Processing {len(records)} records from multi-stream consumer")
    
    successful_records = 0
    failed_records = []
    
    # Group records by source stream
    user_activity_records = []
    payment_records = []
    unknown_records = []
    
    for record in records:
        kinesis_data = None
        try:
            # Determine source stream from event source ARN
            event_source_arn = record.get("eventSourceARN", "")
            kinesis_data = record["kinesis"]
            sequence_number = kinesis_data["sequenceNumber"]
            
            # Decode the record
            raw_data = base64.b64decode(kinesis_data["data"])
            payload = json.loads(raw_data.decode("utf-8"))
            
            # Route based on source stream
            if "user_activity" in event_source_arn.lower():
                user_activity_records.append({
                    "sequence_number": sequence_number,
                    "payload": payload,
                    "timestamp": kinesis_data.get("approximateArrivalTimestamp")
                })
            elif "payments" in event_source_arn.lower():
                payment_records.append({
                    "sequence_number": sequence_number,
                    "payload": payload,
                    "timestamp": kinesis_data.get("approximateArrivalTimestamp")
                })
            else:
                unknown_records.append({
                    "sequence_number": sequence_number,
                    "source": event_source_arn
                })
                logger.warning(f"Unknown source stream: {event_source_arn}")
            
            successful_records += 1
            
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in record: {e}")
            failed_records.append({
                "sequenceNumber": kinesis_data.get("sequenceNumber") if kinesis_data else None,
                "error": f"Invalid JSON: {str(e)}"
            })
        except Exception as e:
            logger.exception(f"Error processing record: {e}")
            failed_records.append({
                "sequenceNumber": kinesis_data.get("sequenceNumber") if kinesis_data else None,
                "error": str(e)
            })
    
    # ============================================================
    # ANALYTICS AGGREGATION LOGIC
    # ============================================================
    
    # Process user activity events
    if user_activity_records:
        _process_user_activity_batch(user_activity_records)
    
    # Process payment events
    if payment_records:
        _process_payment_batch(payment_records)
    
    # Correlate user activity with payments
    if user_activity_records and payment_records:
        _correlate_activity_and_payments(user_activity_records, payment_records)
    
    # ============================================================
    
    result = {
        "batchSize": len(records),
        "successfulRecords": successful_records,
        "failedRecords": len(failed_records),
        "breakdown": {
            "userActivityRecords": len(user_activity_records),
            "paymentRecords": len(payment_records),
            "unknownRecords": len(unknown_records)
        }
    }
    
    logger.info(
        f"Batch complete: {len(user_activity_records)} user_activity, "
        f"{len(payment_records)} payments, {len(failed_records)} failed"
    )
    
    if failed_records:
        return {
            "batchItemFailures": [
                {"itemIdentifier": f["sequenceNumber"]} 
                for f in failed_records 
                if f.get("sequenceNumber")
            ]
        }
    
    return result


def _process_user_activity_batch(records: list):
    """
    Process a batch of user activity records for analytics.
    
    Example aggregations:
    - Count page views per user
    - Track session durations
    - Identify popular actions
    """
    logger.info(f"Aggregating {len(records)} user activity records")
    
    # Example: Count actions by type
    action_counts = {}
    for record in records:
        action = record["payload"].get("action", "unknown")
        action_counts[action] = action_counts.get(action, 0) + 1
    
    logger.info(f"Action counts: {action_counts}")
    
    # TODO: Store aggregations in:
    # - DynamoDB for real-time dashboards
    # - S3 for batch analytics
    # - Timestream for time-series analysis
    # - OpenSearch for searchable analytics


def _process_payment_batch(records: list):
    """
    Process a batch of payment records for analytics.
    
    Example aggregations:
    - Total revenue per time window
    - Payment success/failure rates
    - Average transaction value
    """
    logger.info(f"Aggregating {len(records)} payment records")
    
    total_amount = 0
    payment_types = {}
    
    for record in records:
        payload = record["payload"]
        amount = payload.get("amount", 0)
        payment_type = payload.get("type", "unknown")
        
        total_amount += amount
        payment_types[payment_type] = payment_types.get(payment_type, 0) + 1
    
    logger.info(f"Payment totals: {total_amount}, types: {payment_types}")
    
    # TODO: Store aggregations


def _correlate_activity_and_payments(activity_records: list, payment_records: list):
    """
    Correlate user activity with payment events.
    
    Example insights:
    - Which user journeys lead to purchases?
    - Time from first activity to payment
    - Conversion funnel analysis
    """
    logger.info(
        f"Correlating {len(activity_records)} activities with "
        f"{len(payment_records)} payments"
    )
    
    # Build user activity map
    activity_by_user = {}
    for record in activity_records:
        user_id = record["payload"].get("user_id")
        if user_id:
            if user_id not in activity_by_user:
                activity_by_user[user_id] = []
            activity_by_user[user_id].append(record)
    
    # Build payment map by customer
    payments_by_customer = {}
    for record in payment_records:
        customer_id = record["payload"].get("customer_id")
        if customer_id:
            if customer_id not in payments_by_customer:
                payments_by_customer[customer_id] = []
            payments_by_customer[customer_id].append(record)
    
    # Find correlations (assuming user_id == customer_id for demo)
    correlated_users = set(activity_by_user.keys()) & set(payments_by_customer.keys())
    
    if correlated_users:
        logger.info(f"Found {len(correlated_users)} users with both activity and payments")
        # TODO: Emit correlation events for downstream processing
    
    # TODO: Store correlation data for funnel analysis

