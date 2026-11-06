#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# ALL-IN-ONE UBUNTU AI TRADING AGENT SETUP & EXECUTION SCRIPT
# Handles: Ollama installation, model pulling, Python environment configuration,
# and writing the complete MT5/Ollama integration script.
# ==============================================================================

PROJECT_DIR="${HOME}/ai_trading_agent"
MODEL_NAME="llama3.1"
SYMBOL="EURUSD"

echo "=============================================================================="
echo " 🐧 Starting All-in-One Ubuntu AI Trading Agent Setup"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# 1. INSTALL OLLAMA IF MISSING
# ------------------------------------------------------------------------------
if ! command -v ollama &> /dev/null; then
    echo "==> Ollama is not installed. Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "==> Ollama is already installed."
fi

# Ensure Ollama daemon is running in the background
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "==> Starting Ollama server in the background..."
    ollama serve > /dev/null 2>&1 &
    sleep 4
else
    echo "==> Ollama server is already running."
fi

echo "==> Pulling local AI model '${MODEL_NAME}' (this may take a few minutes if not cached)..."
ollama pull "${MODEL_NAME}"

# ------------------------------------------------------------------------------
# 2. CREATE WORKSPACE & PYTHON VIRTUAL ENVIRONMENT
# ------------------------------------------------------------------------------
echo "==> Creating project workspace at: ${PROJECT_DIR}"
mkdir -p "${PROJECT_DIR}"
cd "${PROJECT_DIR}"

echo "==> Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

echo "==> Upgrading pip and installing required libraries (mt5linux, ollama, pandas, pydantic)..."
pip install --upgrade pip
pip install ollama pandas pydantic mt5linux

# ------------------------------------------------------------------------------
# 3. GENERATE THE COMPLETE TRADING AGENT SCRIPT
# ------------------------------------------------------------------------------
echo "==> Generating 'ai_trading_agent.py'..."

cat << 'EOF' > ai_trading_agent.py
import json
import sys
from mt5linux import MetaTrader5
import ollama
from pydantic import BaseModel, Field

# ============================================================
# 1. DEFINE STRUCTURED AI OUTPUT SCHEMA
# ============================================================
class TradeSignal(BaseModel):
    action: str = Field(description="BUY, SELL, or HOLD")
    confidence: float = Field(description="Signal confidence score between 0.0 and 1.0")
    reasoning: str = Field(description="Technical analysis summary")
    entry_price: float = Field(description="Target entry price")
    stop_loss: float = Field(description="Calculated Stop Loss price")
    tp1: float = Field(description="Take Profit 1 level")
    tp2: float = Field(description="Take Profit 2 level")
    tp3: float = Field(description="Take Profit 3 level")

# ============================================================
# 2. FETCH MARKET CONTEXT VIA LINUX-MT5 BRIDGE
# ============================================================
def get_market_context(symbol: str, num_bars: int = 20):
    # Connects to MT5 running in Docker/Wine container via mt5linux (RPyC)
    mt5 = MetaTrader5(host="localhost", port=18812)
    
    if not mt5.initialize():
        print(f"❌ MT5 Bridge initialization failed. Ensure your MT5 container/server is running on port 18812.")
        return None

    rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M15, 0, num_bars)
    symbol_info = mt5.symbol_info(symbol)

    if rates is None or symbol_info is None:
        print(f"❌ Failed to fetch data for symbol: {symbol}")
        mt5.shutdown()
        return None

    candles_summary = []
    for rate in rates[-5:]:
        candles_summary.append(
            f"Open: {rate['open']}, High: {rate['high']}, Low: {rate['low']}, Close: {rate['close']}"
        )

    context = {
        "symbol": symbol,
        "current_ask": symbol_info.ask,
        "current_bid": symbol_info.bid,
        "digits": symbol_info.digits,
        "recent_candles": "\n".join(candles_summary)
    }
    
    mt5.shutdown()
    return context

# ============================================================
# 3. QUERY LOCAL OLLAMA MODEL FOR SIGNALS
# ============================================================
def analyze_market_with_ollama(context: dict, model_name: str = "llama3.1") -> TradeSignal:
    prompt = f"""
    You are an expert quantitative trading engine analyzing {context['symbol']}.
    Current Market State:
    - Current Ask: {context['current_ask']}
    - Current Bid: {context['current_bid']}
    
    Recent 15-Minute Candles:
    {context['recent_candles']}

    Task:
    Analyze price structure and momentum. Decide if there is a high-probability trade.
    Calculate SL, TP1 (1:1 R/R), TP2 (1:1.5 R/R), and TP3 (1:2.5 R/R) based on volatility.
    If market conditions are uncertain or ranging, set action to 'HOLD'.
    """

    try:
        response = ollama.chat(
            model=model_name,
            messages=[{"role": "user", "content": prompt}],
            format=TradeSignal.model_json_schema(),
            options={"temperature": 0.1}
        )
        signal_data = json.loads(response['message']['content'])
        return TradeSignal(**signal_data)
    except Exception as exc:
        print(f"❌ Ollama analysis failed: {exc}")
        return TradeSignal(
            action="HOLD", confidence=0.0, reasoning="AI processing error",
            entry_price=0.0, stop_loss=0.0, tp1=0.0, tp2=0.0, tp3=0.0
        )

# ============================================================
# 4. EXECUTE TRADE WITH MULTI-TP SCALING VIA MT5 BRIDGE
# ============================================================
def execute_ai_trade(symbol: str, signal: TradeSignal, total_lot: float = 0.03):
    if signal.action not in ["BUY", "SELL"] or signal.confidence < 0.70:
        print(f"[{symbol}] No execution triggered: Action={signal.action}, Confidence={signal.confidence:.2f}")
        return

    mt5 = MetaTrader5(host="localhost", port=18812)
    if not mt5.initialize():
        print(f"❌ MT5 Bridge initialization failed.")
        return

    order_type = mt5.ORDER_TYPE_BUY if signal.action == "BUY" else mt5.ORDER_TYPE_SELL
    sub_lot = round(total_lot / 3.0, 2)
    targets = [signal.tp1, signal.tp2, signal.tp3]

    print(f"\n🚀 AI SIGNAL CONFIRMED: {signal.action} @ {signal.entry_price}")
    print(f"Reasoning: {signal.reasoning}")
    print(f"SL: {signal.stop_loss} | TP1: {signal.tp1} | TP2: {signal.tp2} | TP3: {signal.tp3}")

    for idx, tp in enumerate(targets, start=1):
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": sub_lot,
            "type": order_type,
            "price": signal.entry_price,
            "sl": signal.stop_loss,
            "tp": tp,
            "deviation": 20,
            "magic": 999888,
            "comment": f"Ollama_AI_TP{idx}",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
            error_comment = result.comment if result else "Unknown error"
            print(f"❌ Failed to place TP{idx} Order: {error_comment}")
        else:
            print(f"✅ Position split {idx}/3 placed successfully!")

    mt5.shutdown()

# ============================================================
# MAIN EXECUTION ENTRY POINT
# ============================================================
if __name__ == "__main__":
    target_symbol = "EURUSD"
    ai_model = "llama3.1"
    
    print(f"\n--- Running AI Trading Cycle for {target_symbol} ---")
    market_data = get_market_context(target_symbol)
    
    if market_data:
        print("Analyzing market with local Ollama model...")
        ai_signal = analyze_market_with_ollama(market_data, model_name=ai_model)
        execute_ai_trade(target_symbol, ai_signal, total_lot=0.03)
EOF

echo "=============================================================================="
echo " ✅ All-in-One Setup Complete!"
echo " Workspace: ${PROJECT_DIR}"
echo " Script:    ${PROJECT_DIR}/ai_trading_agent.py"
echo ""
echo " To run your agent anytime:"
echo "   cd ~/ai_trading_agent"
echo "   source venv/bin/activate"
echo "   python ai_trading_agent.py"
echo "=============================================================================="

