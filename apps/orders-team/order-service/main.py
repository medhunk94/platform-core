import os
import json
import logging
import signal
import sys
from kafka import KafkaConsumer
from kafka.errors import KafkaError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Environment variables
KAFKA_BROKER = os.getenv("KAFKA_BROKER", "kafka.kafka.svc.cluster.local:9092")
KAFKA_TOPIC = os.getenv("KAFKA_TOPIC", "order-topic")
CONSUMER_GROUP = os.getenv("CONSUMER_GROUP", "order-processor-group")

# Global consumer for graceful shutdown
consumer = None
shutdown_requested = False

def signal_handler(sig, frame):
    """Handle graceful shutdown on SIGTERM/SIGINT"""
    global shutdown_requested
    logger.info(f"Received signal {sig}, initiating graceful shutdown...")
    shutdown_requested = True

def process_order(message):
    """Process an order message from Kafka"""
    try:
        order = json.loads(message.value.decode('utf-8'))
        
        logger.info(
            f"📦 Processing Order: {order.get('order_id')} | "
            f"Customer: {order.get('customer_id')} | "
            f"Amount: ${order.get('amount', 0):.2f} | "
            f"Items: {len(order.get('items', []))}"
        )
        
        # Log item details
        for item in order.get('items', []):
            logger.info(
                f"  └─ Item: {item.get('product_id')} | "
                f"Qty: {item.get('quantity')} | "
                f"Price: ${item.get('price', 0):.2f}"
            )
        
        # Simulate processing time
        import time
        time.sleep(0.1)
        
        logger.info(f"✅ Order {order.get('order_id')} processed successfully")
        
    except json.JSONDecodeError as e:
        logger.error(f"❌ Failed to decode message: {e}")
    except Exception as e:
        logger.error(f"❌ Error processing order: {e}")

def main():
    """Main consumer loop"""
    global consumer
    
    logger.info("🚀 Starting Order Service Consumer")
    logger.info(f"📡 Kafka broker: {KAFKA_BROKER}")
    logger.info(f"📨 Topic: {KAFKA_TOPIC}")
    logger.info(f"👥 Consumer group: {CONSUMER_GROUP}")
    
    # Register signal handlers
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    try:
        # Create Kafka consumer
        consumer = KafkaConsumer(
            KAFKA_TOPIC,
            bootstrap_servers=KAFKA_BROKER,
            group_id=CONSUMER_GROUP,
            auto_offset_reset='latest',
            enable_auto_commit=True,
            value_deserializer=None  # We'll handle deserialization manually
        )
        
        logger.info("✅ Consumer is ready and waiting for messages...")
        
        # Consume messages
        for message in consumer:
            if shutdown_requested:
                logger.info("Shutdown requested, stopping consumer...")
                break
                
            process_order(message)
        
    except KafkaError as e:
        logger.error(f"❌ Kafka error: {e}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"❌ Unexpected error: {e}")
        sys.exit(1)
    finally:
        if consumer:
            logger.info("Closing consumer...")
            consumer.close()
            logger.info("Consumer closed successfully")

if __name__ == "__main__":
    main()
