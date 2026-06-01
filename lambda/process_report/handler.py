import json
import boto3
import uuid
import os
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

TABLE_NAME = os.environ.get('DYNAMODB_TABLE', 'field-reports')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')


def lambda_handler(event, context):
    method = event.get('httpMethod', 'GET')

    if method == 'GET':
        return get_reports(event)
    elif method == 'POST':
        return submit_report(event)
    else:
        return response(405, {'error': 'Method not allowed'})


def submit_report(event):
    try:
        body = json.loads(event.get('body', '{}'))
    except json.JSONDecodeError:
        return response(400, {'error': 'Invalid JSON body'})

    # Validate required fields
    required = ['tech_name', 'job_site', 'report_type']
    missing = [f for f in required if not body.get(f)]
    if missing:
        return response(400, {'error': f'Missing required fields: {missing}'})

    # Build record
    report_id = str(uuid.uuid4())
    submitted_at = datetime.now(timezone.utc).isoformat()

    record = {
        'report_id': report_id,
        'submitted_at': submitted_at,
        'source': 'form',
        'tech_name': body.get('tech_name'),
        'job_site': body.get('job_site'),
        'report_type': body.get('report_type'),
        'equipment': body.get('equipment', ''),
        'notes': body.get('notes', ''),
        'photo_key': body.get('photo_key', ''),
    }

    # Write to DynamoDB
    table = dynamodb.Table(TABLE_NAME)
    table.put_item(Item=record)

    # Publish SNS notification
    if SNS_TOPIC_ARN:
        message = (
            f"New field report submitted\n\n"
            f"Tech: {record['tech_name']}\n"
            f"Site: {record['job_site']}\n"
            f"Type: {record['report_type']}\n"
            f"Equipment: {record['equipment']}\n"
            f"Notes: {record['notes']}\n"
            f"Submitted: {submitted_at}\n"
            f"Report ID: {report_id}"
        )
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"Field Report — {record['job_site']} — {record['report_type']}",
            Message=message
        )

    return response(200, {'report_id': report_id, 'submitted_at': submitted_at})


def get_reports(event):
    table = dynamodb.Table(TABLE_NAME)
    result = table.scan(Limit=50)
    items = result.get('Items', [])
    return response(200, {'reports': items, 'count': len(items)})


def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        },
        'body': json.dumps(body, default=str)
    }
