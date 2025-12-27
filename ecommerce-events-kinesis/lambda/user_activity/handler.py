"""
User Activity Event Processor

This Lambda function processes user activity events from Kinesis.
It automatically scales to zero when no events are available.
"""

import base64
import json
import logging
import os
from typing import Any

# Configure logging
log_level = os.environ.get("LOG_LEVEL", "INFO")
logger = logging.getLogger()
logger.setLevel(log_level)


def process_event(event: dict, context: Any) -> dict:
    """
    Process user activity events from Kinesis stream.
    
    Args:
        event: Kinesis event containing records
        context: Lambda context object
    
    Returns:
        Processing result with success/failure details
    """
    logger.info(f"Processing {len(event.get('Records', []))} records")
    
    successful_records = 0
    failed_records = []
    
    for record in event.get("Records", []):
        try:
            # Decode the Kinesis record
            kinesis_data = record["kinesis"]
            sequence_number = kinesis_data["sequenceNumber"]
            partition_key = kinesis_data["partitionKey"]
            
            # Decode base64 data
            raw_data = base64.b64decode(kinesis_data["data"])
            payload = json.loads(raw_data.decode("utf-8"))
            
            logger.debug(f"Processing record {sequence_number}: {json.dumps(payload)}")
            
            # ============================================================
            # YOUR BUSINESS LOGIC HERE
            # ============================================================
            # Example: Extract and process user activity data
            user_id = payload.get("user_id")
            action = payload.get("action")
            timestamp = payload.get("timestamp")
            metadata = payload.get("metadata", {})
            
            # Example processing:
            # - Store in database
            # - Update analytics
            # - Trigger downstream workflows
            # - Send notifications
            
            logger.info(f"Processed user activity: user={user_id}, action={action}")
            
            # ============================================================
            
            successful_records += 1
            
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in record: {e}")
            failed_records.append({
                "sequenceNumber": kinesis_data.get("sequenceNumber"),
                "error": f"Invalid JSON: {str(e)}"
            })
            
        except KeyError as e:
            logger.error(f"Missing required field: {e}")
            failed_records.append({
                "sequenceNumber": kinesis_data.get("sequenceNumber"),
                "error": f"Missing field: {str(e)}"
            })
            
        except Exception as e:
            logger.exception(f"Error processing record: {e}")
            failed_records.append({
                "sequenceNumber": record.get("kinesis", {}).get("sequenceNumber"),
                "error": str(e)
            })
    
    result = {
        "batchSize": len(event.get("Records", [])),
        "successfulRecords": successful_records,
        "failedRecords": len(failed_records),
        "failures": failed_records
    }
    
    logger.info(f"Batch complete: {successful_records} succeeded, {len(failed_records)} failed")
    
    # If any records failed, return failure response for retry logic
    if failed_records:
        # Return batch item failures for partial batch response
        # Lambda will retry only the failed records
        return {
            "batchItemFailures": [
                {"itemIdentifier": f["sequenceNumber"]} 
                for f in failed_records 
                if f.get("sequenceNumber")
            ]
        }
    
    return result

