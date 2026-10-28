#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define configuration variables
PROJECT_DIR="$HOME/openalgo"
DATA_DIR="$PROJECT_DIR/openalgo_data"
CONTAINER_NAME="openalgo_app"
PORT=5000
TIMEZONE="Africa/Johannesburg"

echo "===================================================="
echo "🚀 Starting OpenAlgo Automated Docker Setup..."
echo "===================================================="

# 1. Create directory structure
echo "📁 Creating application directories..."
mkdir -p "$DATA_DIR"

# 2. Write the docker-compose.yml file directly into the directory
echo "📝 Generating docker-compose.yml configuration..."
cat << EOF > "$PROJECT_DIR/docker-compose.yml"
version: '3.8'

services:
  openalgo:
    image: openalgo/openalgo:latest
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "${PORT}:${PORT}"
    volumes:
      - ./openalgo_data:/app/data
    environment:
      - TZ=${TIMEZONE}
      - PORT=${PORT}
      
      # =====================================================================
      # HOW TO GET SIGNALS WITHOUT TRADING (ALERTS ONLY):
      # =====================================================================
      # 1. Keep your broker configuration inside the dashboard turned OFF 
      #    or strictly connected to a "Sandbox/Demo" account.
      # 2. Uncomment the three lines below by removing the '#' characters.
      # 3. Insert your unique Telegram Bot Token and Chat ID.
      # =====================================================================
      # - TELEGRAM_BOT_TOKEN=your_bot_token_here
      # - TELEGRAM_CHAT_ID=your_chat_id_here
      # - NOTIFICATION_EVENTS=SIGNAL_TRIGGERED,ERROR
EOF

# 3. Adjust storage permissions to prevent database locking or access issues
echo "🔒 Fixing data directory permissions..."
chmod -R 775 "$DATA_DIR"

# 4. Navigate and launch the container
echo "🐳 Launching OpenAlgo via Docker Compose..."
cd "$PROJECT_DIR"
docker compose down --remove-orphans 2>/dev/null || true
docker compose up -d

echo "===================================================="
echo "✅ Setup Complete!"
echo "===================================================="
echo "🌐 OpenAlgo is running in the background."
echo "🔗 Access your local dashboard at: http://localhost:${PORT}"
echo "🪵 To view logs in real-time, run: docker logs -f ${CONTAINER_NAME}"
echo "===================================================="
echo ""
echo "===================================================="
echo "💡 USAGE GUIDE: HOW TO SEND SIGNALS TO THIS SETUP"
echo "===================================================="
echo "1. Webhook Destination URL:"
echo "   Point your TradingView or Python script alerts to:"
echo "   http://<YOUR_IP_ADDRESS>:${PORT}/webhook"
echo ""
echo "2. JSON Signal Payload Format:"
echo "   Configure your indicator script to output this exact text format"
echo "   when a Buy or Sell setup triggers:"
echo ""
echo "   {"
echo "     \"api_key\": \"YOUR_OPENALGO_DASHBOARD_API_KEY\","
echo "     \"action\": \"BUY\","
echo "     \"symbol\": \"BTCUSD\","
echo "     \"quantity\": 0.01,"
echo "     \"strategy\": \"AI_Lorentzian_Classification\","
echo "     \"stop_loss\": 62100,"
echo "     \"take_profit\": 65400"
echo "   }"
echo "===================================================="
