//+------------------------------------------------------------------+
//| Mirage Liquidity Sweep EA Pro.mq5                                |
//| Fully Automated Trading System based on Liquidity Sweep Strategy  |
//+------------------------------------------------------------------+
#property copyright "WillyAlgoTrader"
#property version   "1.00"
#property script_show_inputs

#include 

//--- Main Strategy Inputs
input group "=== Strategy Parameters ==="
input int      InpSwingLength       = 21;    // Swing Length
input int      InpMaxSweepDistance  = 80;    // Max Sweep Distance (Bars)
input int      InpMinSweepScore     = 50;    // Minimum Sweep Score Threshold

//--- Filters
input group "=== Filters ==="
input bool     InpUseVolume         = true;  // Filter by Volume Spike
input int      InpVolumeMALength    = 21;    // Volume MA Length
input double   InpVolumeSpike       = 1.5;   // Volume Spike Factor
input bool     InpUseHTFBias        = true;  // Filter by HTF Trend
input ENUM_TIMEFRAMES InpHTF        = PERIOD_H4; // HTF Reference
input int      InpHTFEMALength      = 50;    // HTF EMA Length

//--- Risk & Position Sizing
input group "=== Risk Management ==="
input double   InpRiskPercent       = 1.0;   // Risk per trade (% of Equity)
input double   InpFixedLot          = 0.0;   // Fixed Lot Size (If > 0, overrides % Risk)
input int      InpATRLength         = 14;    // ATR Length for SL
input double   InpSLBufferATR       = 0.25;  // SL Buffer (ATR Multiple)
input double   InpTP1R              = 1.5;   // Risk:Reward Ratio for TP
input bool     InpMoveBEOnTP1       = true;  // Move SL to Entry on TP1

//--- Execution Settings
input group "=== Execution Settings ==="
input ulong    InpMagicNumber       = 888123;// Magic Number
input ulong    InpSlippage          = 10;    // Max Slippage (Points)
input string   InpTradeComment      = "Mirage Sweep EA";

//--- Dynamic Global Variables
CTrade         trade;
int            ATRHandle            = INVALID_HANDLE;
int            HTFEMAHandle         = INVALID_HANDLE;
datetime       LastBarTime          = 0;

struct SwingPoint
{
   double   price;
   datetime time;
   bool     used;
};

SwingPoint Highs[];
SwingPoint Lows[];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   ATRHandle = iATR(_Symbol, _Period, InpATRLength);
   HTFEMAHandle = iMA(_Symbol, InpHTF, InpHTFEMALength, 0, MODE_EMA, PRICE_CLOSE);

   if(ATRHandle == INVALID_HANDLE || HTFEMAHandle == INVALID_HANDLE)
   {
      Print("[Error] Failed to create indicator handles.");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ATRHandle != INVALID_HANDLE) IndicatorRelease(ATRHandle);
   if(HTFEMAHandle != INVALID_HANDLE) IndicatorRelease(HTFEMAHandle);
}

//+------------------------------------------------------------------+
//| OnTick Processing                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   // Manage Break-Even on active positions
   ManagePositions();

   // Check for New Bar before running logic
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == LastBarTime) return;
   LastBarTime = currentBarTime;

   // Evaluate Trading Logic on Bar Close
   ProcessStrategy();
}

//+------------------------------------------------------------------+
//| Position & Lot Size Calculation                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(const double entryPrice, const double stopLoss)
{
   if(InpFixedLot > 0.0) return InpFixedLot;

   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent / 100.0);
   double slDistance = MathAbs(entryPrice - stopLoss);
   if(slDistance <= 0.0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0 || tickValue <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lossPerLot = (slDistance / tickSize) * tickValue;
   double lotSize = riskAmount / lossPerLot;

   // Normalize Lot Size to broker requirements
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = MathFloor(lotSize / stepLot) * stepLot;
   return MathMin(MathMax(lotSize, minLot), maxLot);
}

//+------------------------------------------------------------------+
//| Strategy Evaluation Logic                                       |
//+------------------------------------------------------------------+
void ProcessStrategy()
{
   int need = MathMax(300, InpSwingLength * 3 + InpMaxSweepDistance);
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, _Period, 0, need, r) < need) return;

   const int sh = 1;
   const MqlRates &b = r[sh];

   // Register Swing Points
   int pivotShift = InpSwingLength + 1;
   if(IsPivotHigh(r, pivotShift)) AddHigh(r[pivotShift].high, r[pivotShift].time);
   if(IsPivotLow(r, pivotShift))  AddLow(r[pivotShift].low, r[pivotShift].time);

   // HTF & Volume Conditions
   double atr = GetATR(sh);
   double volComp = VolumeComponent(r, sh);
   
   double htfClose = GetHTFClose();
   double htfEma   = GetHTFEMA(sh);
   bool htfBull    = (htfClose > htfEma);
   bool htfBear    = (htfClose < htfEma);

   bool bullSweep = false;
   bool bearSweep = false;
   double bullLvl = 0.0, bearLvl = 0.0;

   // Check Highs Sweep
   for(int j = ArraySize(Highs) - 1; j >= 0; j--)
   {
      if(Highs[j].used) continue;
      int highShift = iBarShift(_Symbol, _Period, Highs[j].time);
      if(highShift < 0 || (highShift - sh) > InpMaxSweepDistance) { Highs[j].used = true; continue; }

      double lvl = Highs[j].price;
      if(b.close > lvl) Highs[j].used = true;
      else if(b.high > lvl && b.close < lvl)
      {
         Highs[j].used = true;
         bearSweep = true; bearLvl = lvl;
         break;
      }
   }

   // Check Lows Sweep
   for(int j = ArraySize(Lows) - 1; j >= 0; j--)
   {
      if(Lows[j].used) continue;
      int lowShift = iBarShift(_Symbol, _Period, Lows[j].time);
      if(lowShift < 0 || (lowShift - sh) > InpMaxSweepDistance) { Lows[j].used = true; continue; }

      double lvl = Lows[j].price;
      if(b.close < lvl) Lows[j].used = true;
      else if(b.low < lvl && b.close > lvl)
      {
         Lows[j].used = true;
         bullSweep = true; bullLvl = lvl;
         break;
      }
   }

   // Calculate Scores
   double bullScore = bullSweep ? SweepScore(1, bullLvl, b, atr, volComp, htfBull ? 1.0 : 0.0) : 0;
   double bearScore = bearSweep ? SweepScore(-1, bearLvl, b, atr, volComp, htfBear ? 1.0 : 0.0) : 0;

   // Check Open Position Limits
   if(HasOpenPosition()) return;

   // Execution
   if(bullSweep && bullScore >= InpMinSweepScore && (!InpUseHTFBias || htfBull))
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = b.low - (atr * InpSLBufferATR);
      double tp  = ask + ((ask - sl) * InpTP1R);
      double lot = CalculateLotSize(ask, sl);

      trade.Buy(lot, _Symbol, ask, sl, tp, InpTradeComment);
   }
   else if(bearSweep && bearScore >= InpMinSweepScore && (!InpUseHTFBias || htfBear))
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = b.high + (atr * InpSLBufferATR);
      double tp  = bid - ((sl - bid) * InpTP1R);
      double lot = CalculateLotSize(bid, sl);

      trade.Sell(lot, _Symbol, bid, sl, tp, InpTradeComment);
   }
}

//+------------------------------------------------------------------+
//| Management & Trail Logic                                         |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(!InpMoveBEOnTP1) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!PositionGetTicket(i)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long posType     = PositionGetInteger(POSITION_TYPE);

      if(posType == POSITION_TYPE_BUY)
      {
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double distanceR    = openPrice + ((openPrice - currentSL) * 0.5); // Midway to TP1
         if(currentPrice >= distanceR && currentSL < openPrice)
         {
            trade.PositionModify(PositionGetTicket(i), openPrice, currentTP);
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double distanceR    = openPrice - ((currentSL - openPrice) * 0.5); // Midway to TP1
         if(currentPrice <= distanceR && (currentSL > openPrice || currentSL == 0))
         {
            trade.PositionModify(PositionGetTicket(i), openPrice, currentTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Utilities & Helpers                                             |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            return true;
   }
   return false;
}

bool IsPivotHigh(const MqlRates &r[], const int shift)
{
   double p = r[shift].high;
   for(int i = 1; i <= InpSwingLength; i++)
      if(r[shift - i].high >= p || r[shift + i].high > p) return false;
   return true;
}

bool IsPivotLow(const MqlRates &r[], const int shift)
{
   double p = r[shift].low;
   for(int i = 1; i <= InpSwingLength; i++)
      if(r[shift - i].low <= p || r[shift + i].low < p) return false;
   return true;
}

void AddHigh(const double price, const datetime time)
{
   int n = ArraySize(Highs);
   ArrayResize(Highs, n + 1);
   Highs[n].price = price; Highs[n].time = time; Highs[n].used = false;
   if(ArraySize(Highs) > 25) ArrayRemove(Highs, 0, 1);
}

void AddLow(const double price, const datetime time)
{
   int n = ArraySize(Lows);
   ArrayResize(Lows, n + 1);
   Lows[n].price = price; Lows[n].time = time; Lows[n].used = false;
   if(ArraySize(Lows) > 25) ArrayRemove(Lows, 0, 1);
}

double GetATR(const int shift)
{
   double b[]; ArraySetAsSeries(b, true);
   return (CopyBuffer(ATRHandle, 0, shift, 1, b) == 1) ? b[0] : 0.0;
}

double GetHTFEMA(const int shift)
{
   double b[]; ArraySetAsSeries(b, true);
   return (CopyBuffer(HTFEMAHandle, 0, shift, 1, b) == 1) ? b[0] : 0.0;
}

double GetHTFClose()
{
   MqlRates r[]; ArraySetAsSeries(r, true);
   return (CopyRates(_Symbol, InpHTF, 1, 1, r) == 1) ? r[0].close : 0.0;
}

double VolumeComponent(const MqlRates &r[], const int shift)
{
   if(!InpUseVolume || r[shift].tick_volume <= 0) return 0.5;
   double sum = 0.0;
   for(int i = shift + 1; i <= shift + InpVolumeMALength; i++) sum += (double)r[i].tick_volume;
   double ma = sum / InpVolumeMALength;
   return (ma <= 0) ? 0.5 : MathMin(MathMax((((double)r[shift].tick_volume / ma) - 1.0) / (InpVolumeSpike - 1.0), 0.0), 1.0);
}

double SweepScore(const int dir, const double lvl, const MqlRates &b, const double atr, const double volComp, const double htfComp)
{
   if(atr <= 0 || lvl <= 0) return 0.0;
   double range = b.high - b.low;
   if(range <= 0) return 0.0;

   double wick = (dir == 1) ? MathMin(b.open, b.close) - b.low : b.high - MathMax(b.open, b.close);
   double reclaim = (dir == 1) ? b.close - lvl : lvl - b.close;
   double cpComp = (dir == 1) ? (b.close - b.low) / range : 1.0 - ((b.close - b.low) / range);

   return ((MathMin(wick / atr, 1.0) * 0.30) + (MathMin(reclaim / atr, 1.0) * 0.25) + (cpComp * 0.20) + (volComp * 0.15) + (htfComp * 0.10)) * 100.0;
}
