//+------------------------------------------------------------------+
//|                                  SMC_Liquidity_ReEntry_EA.mq5    |
//|               Smart Money Concepts - Sweep + CHoCH + FVG Re-Entry|
//+------------------------------------------------------------------+
#property copyright "Smart Money Systems"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

#include 
CTrade trade;

//--- INPUT PARAMETERS
input group "=== Risk Management ==="
input double   InpRiskPercent     = 1.0;       // Risk Per Trade (%)
input double   InpRiskRewardRatio = 2.0;       // Risk to Reward Ratio (1:N)
input ulong    InpMagicNumber     = 888222;    // EA Magic Number

input group "=== Structure & Setup Settings ==="
input int      InpSwingLookback   = 20;        // Swing High/Low Lookback Bars
input bool     InpUseBodyClose    = true;      // Require Body Close for CHoCH/BOS

input group "=== Re-Entry / Secondary Order Settings ==="
input bool     InpEnableReEntry   = true;      // Enable FVG/OB Secondary Entry
input int      InpMaxPendingBars  = 15;        // Cancel Pending Order after N Bars
input double   InpFVGRetestLevel  = 0.5;       // FVG Entry Level (0.0=Edge, 0.5=50% Mid)

//--- GLOBAL VARIABLES
datetime g_lastBarTime;
struct SMC_Setup
{
   bool     active;
   int      direction;      // +1 for Bullish, -1 for Bearish
   double   swingLow;
   double   swingHigh;
   double   chochLevel;
   double   bosLevel;
   double   fvgHigh;
   double   fvgLow;
   datetime setupTime;
};

SMC_Setup currentSetup;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   g_lastBarTime = 0;
   ResetSetup();
   Print("SMC Liquidity & Re-Entry EA Initialized Successfully.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Execute only on new candle close/open
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == g_lastBarTime) return;
   g_lastBarTime = currentBarTime;

   // 1. Manage existing pending orders (Expiry cleanup)
   CleanExpiredPendingOrders();

   // 2. Scan Market Structure & Identify Sweeps
   DetectStructureAndSignals();
}

//+------------------------------------------------------------------+
//| Detect Structure, Sweeps, CHoCH, and Generate Entries           |
//+------------------------------------------------------------------+
void DetectStructureAndSignals()
{
   // Fetch price data for analysis
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 0, InpSwingLookback + 5, rates) < InpSwingLookback) return;

   // Find local Swing Low and Swing High (excluding recent 2 bars)
   int highestIdx = iHighest(_Symbol, _Period, MODE_HIGH, InpSwingLookback, 2);
   int lowestIdx  = iLowest(_Symbol, _Period, MODE_LOW,  InpSwingLookback, 2);

   double swingHigh = rates[highestIdx].high;
   double swingLow  = rates[lowestIdx].low;

   // --- BULLISH SWEEP + CHoCH DETECTION ---
   // Candle 1 swept below Swing Low, but closed back above (Liquidity Sweep)
   bool isBullishSweep = (rates[1].low < swingLow) && (rates[1].close > swingLow);
   
   // Check CHoCH (reclaim of previous short-term high)
   double priorLowerHigh = rates[2].high;
   bool isCHoCH = rates[1].close > priorLowerHigh;

   if(isBullishSweep && isCHoCH && GetOpenPositionsCount() == 0)
   {
      Print("BULLISH CHoCH & SWEEP DETECTED at ", rates[1].close);
      
      // Calculate Stop Loss (Below Sweep Low) & Take Profit
      double sl = rates[1].low - (10 * _Point); // 10 points buffer
      double riskPips = rates[1].close - sl;
      double tp = rates[1].close + (riskPips * InpRiskRewardRatio);
      
      // Calculate Lot Size
      double lotSize = CalculateLotSize(MathAbs(riskPips));

      // Execution 1: Direct Market Order (Primary Entry)
      if(trade.Buy(lotSize, _Symbol, rates[0].open, sl, tp, "SMC Primary Sweep Entry"))
      {
         Print("Primary Market Buy Order Executed.");
      }

      // Execution 2: FVG Secondary Re-Entry Order (If enabled)
      if(InpEnableReEntry)
      {
         // FVG Identification between Candle 3 High and Candle 1 Low
         if(rates[1].low > rates[3].high) 
         {
            double fvgTop    = rates[1].low;
            double fvgBottom = rates[3].high;
            double fvgEntry  = fvgBottom + ((fvgTop - fvgBottom) * InpFVGRetestLevel);

            double reEntrySL = sl; // Same structural stop
            double reEntryTP = fvgEntry + ((fvgEntry - reEntrySL) * InpRiskRewardRatio);
            double reEntryLots = CalculateLotSize(MathAbs(fvgEntry - reEntrySL));

            // Place Buy Limit Order at FVG
            trade.BuyLimit(reEntryLots, fvgEntry, _Symbol, reEntrySL, reEntryTP, ORDER_TIME_GTC, 0, "SMC FVG Re-Entry");
            Print("Secondary FVG Buy Limit Placed at: ", fvgEntry);
         }
      }
   }

   // --- BEARISH SWEEP + CHoCH DETECTION ---
   bool isBearishSweep = (rates[1].high > swingHigh) && (rates[1].close < swingHigh);
   double priorHigherLow = rates[2].low;
   bool isBearishCHoCH = rates[1].close < priorHigherLow;

   if(isBearishSweep && isBearishCHoCH && GetOpenPositionsCount() == 0)
   {
      Print("BEARISH CHoCH & SWEEP DETECTED at ", rates[1].close);

      double sl = rates[1].high + (10 * _Point);
      double riskPips = sl - rates[1].close;
      double tp = rates[1].close - (riskPips * InpRiskRewardRatio);
      double lotSize = CalculateLotSize(MathAbs(riskPips));

      // Execution 1: Direct Market Order
      if(trade.Sell(lotSize, _Symbol, rates[0].open, sl, tp, "SMC Primary Sweep Entry"))
      {
         Print("Primary Market Sell Order Executed.");
      }

      // Execution 2: Secondary Re-entry Order
      if(InpEnableReEntry)
      {
         if(rates[1].high < rates[3].low)
         {
            double fvgTop    = rates[3].low;
            double fvgBottom = rates[1].high;
            double fvgEntry  = fvgTop - ((fvgTop - fvgBottom) * InpFVGRetestLevel);

            double reEntrySL = sl;
            double reEntryTP = fvgEntry - ((reEntrySL - fvgEntry) * InpRiskRewardRatio);
            double reEntryLots = CalculateLotSize(MathAbs(reEntrySL - fvgEntry));

            trade.SellLimit(reEntryLots, fvgEntry, _Symbol, reEntrySL, reEntryTP, ORDER_TIME_GTC, 0, "SMC FVG Re-Entry");
            Print("Secondary FVG Sell Limit Placed at: ", fvgEntry);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Dynamic Position Size Based on Account Risk           |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskInPrice)
{
   if(riskInPrice <= 0) return _Point;

   double accBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accBalance * (InpRiskPercent / 100.0);
   
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tickSize == 0 || tickValue == 0) return 0.01;

   double riskInTicks = riskInPrice / tickSize;
   double lotSize     = riskAmount / (riskInTicks * tickValue);

   // Round to broker volume steps
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   return MathMin(maxLot, MathMax(minLot, lotSize));
}

//+------------------------------------------------------------------+
//| Clean Expired Pending Limit Orders                              |
//+------------------------------------------------------------------+
void CleanExpiredPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket > 0)
      {
         if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber)
         {
            datetime orderTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
            int barsPassed = iBarShift(_Symbol, _Period, orderTime);

            // Cancel Limit Order if it hasn't filled within N bars
            if(barsPassed >= InpMaxPendingBars)
            {
               trade.OrderDelete(ticket);
               Print("Pending Re-Entry Order #", ticket, " canceled due to expiry (", barsPassed, " bars elapsed).");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count Active Open Positions for this EA                         |
//+------------------------------------------------------------------+
int GetOpenPositionsCount()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
      {
         count++;
      }
   }
   return count;
}
//+------------------------------------------------------------------+
