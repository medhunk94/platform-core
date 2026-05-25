from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from typing import List
import logging
import os
import json
from kafka import KafkaProducer
from kafka.errors import KafkaError
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Pydantic models
class Item(BaseModel):
    product_id: str = Field(..., description="Product identifier")
    quantity: int = Field(..., ge=1, description="Quantity ordered")
    price: float = Field(..., ge=0, description="Price per unit")

class CheckoutRequest(BaseModel):
    order_id: str = Field(..., description="Unique order identifier")
    customer_id: str = Field(..., description="Customer identifier")
    amount: float = Field(..., ge=0, description="Total order amount")
    items: List[Item] = Field(..., min_items=1, description="List of items")

class CheckoutResponse(BaseModel):
    status: str
    message: str
    order_id: str

# Environment variables
PORT = int(os.getenv("PORT", "8080"))
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "kafka.kafka.svc.cluster.local:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "order-topic")

# Initialize FastAPI app
app = FastAPI(
    title="Checkout Service",
    description="HTTP API for processing checkout requests and publishing to Kafka",
    version="1.0.0"
)

# Kafka producer (initialized on startup)
kafka_producer = None

@app.on_event("startup")
async def startup_event():
    """Initialize Kafka producer on application startup"""
    global kafka_producer
    try:
        kafka_producer = KafkaProducer(
            bootstrap_servers=KAFKA_BROKER,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            acks='all',
            retries=5,
            max_in_flight_requests_per_connection=1
        )
        logger.info(f"✅ Kafka producer connected to {KAFKA_BROKER}")
    except Exception as e:
        logger.warning(f"⚠️  Failed to connect to Kafka: {e}")
        logger.warning("Continuing without Kafka (will log orders only)")

@app.on_event("shutdown")
async def shutdown_event():
    """Close Kafka producer on shutdown"""
    global kafka_producer
    if kafka_producer:
        kafka_producer.close()
        logger.info("Kafka producer closed")

@app.post("/api/checkout", response_model=CheckoutResponse)
async def checkout(request: CheckoutRequest):
    """Process a checkout request and publish to Kafka"""
    logger.info(
        f"📦 Processing checkout - Order: {request.order_id}, "
        f"Customer: {request.customer_id}, Amount: ${request.amount:.2f}, "
        f"Items: {len(request.items)}"
    )

    # Send to Kafka if available
    if kafka_producer:
        try:
            order_data = request.dict()
            future = kafka_producer.send(KAFKA_TOPIC, value=order_data, key=request.order_id.encode('utf-8'))
            future.get(timeout=10)  # Wait for confirmation
            logger.info(f"✅ Order {request.order_id} sent to Kafka topic: {KAFKA_TOPIC}")
        except KafkaError as e:
            logger.error(f"❌ Failed to send to Kafka: {e}")
            raise HTTPException(status_code=500, detail="Failed to process order")
    else:
        logger.info(f"ℹ️  Kafka unavailable - Order {request.order_id} logged only")

    return CheckoutResponse(
        status="success",
        message="Order placed successfully",
        order_id=request.order_id
    )

@app.get("/health")
async def health():
    """Liveness probe"""
    return {"status": "healthy", "service": "checkout-service"}

@app.get("/ready")
async def ready():
    """Readiness probe"""
    return {"status": "ready"}

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "checkout-service",
        "version": "1.0.0",
        "endpoints": {
            "checkout": "POST /api/checkout",
            "health": "GET /health",
            "ready": "GET /ready",
            "docs": "GET /docs"
        }
    }

if __name__ == "__main__":
    logger.info(f"🚀 Starting Checkout Service on port {PORT}")
    logger.info(f"📡 Kafka broker: {KAFKA_BROKER}")
    logger.info(f"📨 Kafka topic: {KAFKA_TOPIC}")
    uvicorn.run(app, host="0.0.0.0", port=PORT)
