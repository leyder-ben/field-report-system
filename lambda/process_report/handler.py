import json
import boto3
import uuid
import os
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
sns      = boto3.client('sns')
s3       = boto3.client('s3')
bedrock  = boto3.client('bedrock-runtime')

TABLE_NAME    = os.environ.get('DYNAMODB_TABLE', 'field-reports')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
PHOTOS_BUCKET = os.environ.get('PHOTOS_BUCKET', '')
MODEL_ID      = os.environ.get('BEDROCK_MODEL_ID', 'anthropic.claude-3-haiku-20240307-v1:0')

REPORT_TYPE_LABELS = {
    't_and_m':               'Time & Material',
    'pump_install_vt':       'Pump Installation — Vertical Turbine',
    'pump_install_sc':       'Pump Installation — Short Coupled',
    'pump_install_submersible': 'Pump Installation — Submersible',
    'pump_install_horizontal':  'Pump Installation — Horizontal',
    'fire_pump_test':        'Fire Pump Test',
    'well_cleaning':         'Well Cleaning',
    'pumping_test':          'Pumping Test',
    'observation_well':      'Observation Well',
    'timesheet':             'Weekly Timesheet',
}


def lambda_handler(event, context):
    method = event.get('httpMethod', 'GET')
    query  = event.get('queryStringParameters') or {}

    if method == 'GET' and query.get('action') == 'presigned_url':
        return get_presigned_url(query)
    elif method == 'GET':
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

    # Generate AI summary and append to record
    summary = ''
    try:
        summary = generate_summary(record)
        table.update_item(
            Key={'report_id': report_id, 'submitted_at': submitted_at},
            UpdateExpression='SET summary = :s',
            ExpressionAttributeValues={':s': summary},
        )
    except Exception as e:
        print(f"Bedrock summary failed: {e}")

    # Publish SNS notification
    if SNS_TOPIC_ARN:
        message = (
            f"New field report submitted\n\n"
            f"Tech: {record['tech_name']}\n"
            f"Site: {record['job_site']}\n"
            f"Type: {record['report_type']}\n"
            f"Equipment: {record['equipment']}\n"
            f"Notes: {record['notes']}\n"
        )
        if summary:
            message += f"\nSummary:\n{summary}\n"
        message += (
            f"\nSubmitted: {submitted_at}\n"
            f"Report ID: {report_id}"
        )
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"Field Report — {record['job_site']} — {record['report_type']}",
            Message=message,
        )

    return response(200, {'report_id': report_id, 'submitted_at': submitted_at})


def generate_summary(record):
    label = REPORT_TYPE_LABELS.get(record.get('report_type', ''), record.get('report_type', ''))
    prompt = (
        "Write a 2-3 sentence plain-English summary of this field report. "
        "Be specific and factual. No filler phrases.\n\n"
        f"Tech: {record.get('tech_name', '')}\n"
        f"Site: {record.get('job_site', '')}\n"
        f"Report type: {label}\n"
        f"Equipment: {record.get('equipment') or 'not specified'}\n"
        f"Notes: {record.get('notes') or 'none'}"
    )
    resp = bedrock.invoke_model(
        modelId=MODEL_ID,
        contentType='application/json',
        accept='application/json',
        body=json.dumps({
            'anthropic_version': 'bedrock-2023-05-31',
            'max_tokens': 200,
            'messages': [{'role': 'user', 'content': prompt}],
        })
    )
    result = json.loads(resp['body'].read())
    return result['content'][0]['text'].strip()


def get_presigned_url(query):
    if not PHOTOS_BUCKET:
        return response(500, {'error': 'Photos bucket not configured'})

    filename = query.get('filename', 'photo.jpg')
    ext = filename.rsplit('.', 1)[-1].lower() if '.' in filename else 'jpg'
    if ext not in ('jpg', 'jpeg', 'png', 'heic', 'heif', 'webp'):
        ext = 'jpg'

    photo_key = f"uploads/{uuid.uuid4()}.{ext}"

    presigned_url = s3.generate_presigned_url(
        'put_object',
        Params={'Bucket': PHOTOS_BUCKET, 'Key': photo_key},
        ExpiresIn=300
    )

    return response(200, {'presigned_url': presigned_url, 'photo_key': photo_key})


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
