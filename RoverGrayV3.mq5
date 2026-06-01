//+------------------------------------------------------------------+
//|                                                   RoverGray.mq5 |
//|                                  Copyright 2026, RoverDogWithin  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, RoverDogWithin"
#property link      "https://www.mql5.com"
#property version   "1.07"

// Include standard library trade classes
#include <Trade\Trade.mqh>

CTrade trade;

// --- INPUT PARAMETERS ---
input group "--- Master Pattern ---"
input ENUM_TIMEFRAMES   InpMasterTF       = PERIOD_H1;       // Master Pattern TF
input ENUM_TIMEFRAMES   InpTrend4H        = PERIOD_H4;       // Medium Trend
input ENUM_TIMEFRAMES   InpTrend1H        = PERIOD_H1;       // Short Trend
input ENUM_TIMEFRAMES   InpTrend5M        = PERIOD_M5;       // Execution Trend

input group "--- Risk Management ---"
input double            InpLotSize        = 0.1;             // Fixed Lot Size
input bool              InpAllowTrades    = true;            // Allow Live Execution
input bool              InpSendAlerts     = true;            // Enable Terminal Alerts

input group "--- VIDYA Settings ---"
input int                InpVidyaPeriod    = 10;              // VIDYA Length
input int                InpVidyaMom       = 20;              // VIDYA Momentum
input double            InpBandDistance   = 2.0;             // Distance Factor

input group "--- Profit Securing Engine ---"
input bool              InpUseBreakEven   = true;            // Enable Break-Even
input double            InpBETriggerATR   = 1.5;             // Move to BE after price moves X * ATR
input bool              InpUseTrailing    = true;            // Enable Trailing Stop
input double            InpTrailDistanceATR = 2.5;           // Trail distance (X * ATR)

// --- GLOBAL VARIABLES ---
int      hEma1H, hEma4H, hEma5M, hAtr;
datetime lastAlertTime = 0;
string   dashboardName = "MP_HUD_Dashboard";
string   levelsPrefix  = "MP_HUD_Level_";
string   arrowPrefix   = "MP_HUD_Arrow_";
string   visualsPrefix = "MP_HUD_Visual_";

// Variables tracked for state-change logging
string   lastLoggedPhase = "";
string   lastLoggedDir   = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[MP HUD LOG] Initializing Expert Advisor...");

   // Initialize Moving Average and ATR Indicators
   hEma1H = iMA(_Symbol, InpTrend1H, 20, 0, MODE_EMA, PRICE_CLOSE);
   hEma4H = iMA(_Symbol, InpTrend4H, 20, 0, MODE_EMA, PRICE_CLOSE);
   hEma5M = iMA(_Symbol, InpTrend5M, 20, 0, MODE_EMA, PRICE_CLOSE);
   hAtr   = iATR(_Symbol, InpTrend5M, 14); // Optimized ATR window for tracking live structural volatility

   if(hEma1H == INVALID_HANDLE || hEma4H == INVALID_HANDLE || hEma5M == INVALID_HANDLE || hAtr == INVALID_HANDLE)
   {
      Print("[MP HUD LOG] Fatal: Failed to initialize indicator handles.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(20260531);
   EventSetTimer(1);
   
   Print("[MP HUD LOG] Initialization Successful. Magic Number set to 20260531.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, dashboardName);
   ObjectsDeleteAll(0, levelsPrefix);
   ObjectsDeleteAll(0, visualsPrefix);
   
   Print(StringFormat("[MP HUD LOG] Deinitializing EA. Reason Code: %d. UI Objects cleaned up.", reason));
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // --- FETCH MULTI-TIMEFRAME DATA ---
   double closeCurrent = iClose(_Symbol, PERIOD_CURRENT, 0);
   
   // 1W & 1D Biases
   double wOpen = iOpen(_Symbol, PERIOD_W1, 0);
   double dOpen = iOpen(_Symbol, PERIOD_D1, 0);
   string wBias = (closeCurrent > wOpen) ? "BULLISH" : "BEARISH";
   string dBias = (closeCurrent > dOpen) ? "BULLISH" : "BEARISH";

   // HTF EMA Trend Checks
   double ema1hVal[1], ema4hVal[1], ema5mVal[1], atrVal[1];
   CopyBuffer(hEma1H, 0, 0, 1, ema1hVal);
   CopyBuffer(hEma4H, 0, 0, 1, ema4hVal);
   CopyBuffer(hEma5M, 0, 0, 1, ema5mVal);
   CopyBuffer(hAtr, 0, 0, 1, atrVal);

   string t_1h = (closeCurrent > ema1hVal[0]) ? "BULLISH" : "BEARISH";
   string t_4h = (closeCurrent > ema4hVal[0]) ? "BULLISH" : "BEARISH";
   string t_5m = (closeCurrent > ema5mVal[0]) ? "BULLISH" : "BEARISH";

   // --- 1H FIBONACCI FORECAST LOGIC ---
   MqlRates rates1H[];
   ArraySetAsSeries(rates1H, true);
   if(CopyRates(_Symbol, InpMasterTF, 0, 20, rates1H) < 20) 
   {
      Print("[MP HUD LOG] Warning: Insufficient 1H history to build Master Pattern data.");
      return;
   }

   double h1_high = rates1H[0].high;
   double h1_low  = rates1H[0].low;
   for(int i=1; i<20; i++)
   {
      if(rates1H[i].high > h1_high) h1_high = rates1H[i].high;
      if(rates1H[i].low  < h1_low)  h1_low  = rates1H[i].low;
   }

   double fib_entry_50  = h1_high - (h1_high - h1_low) * 0.50;
   double fib_entry_618 = h1_high - (h1_high - h1_low) * 0.618;

   string forecast_dir = (closeCurrent > ema1hVal[0]) ? "BUY" : "SELL";
   
   double final_entry   = (forecast_dir == "BUY") ? fib_entry_618 : fib_entry_50;
   double range         = h1_high - h1_low;
   
   double final_tp1     = (forecast_dir == "BUY") ? h1_high + (range * 0.272) : h1_low - (range * 0.272);
   double final_tp2     = (forecast_dir == "BUY") ? h1_high + (range * 0.618) : h1_low - (range * 0.618);
   double final_tp3     = (forecast_dir == "BUY") ? h1_high + (range * 1.000) : h1_low - (range * 1.000);
   double final_sl      = (forecast_dir == "BUY") ? h1_low - (range * 0.1)     : h1_high + (range * 0.1);

   // Log Direction/Forecast modifications
   if(forecast_dir != lastLoggedDir)
   {
      Print(StringFormat("[MP HUD LOG] Forecast Shift! Mode: %s | Entry Target: %s | SL: %s | TP1: %s", 
                         forecast_dir, DoubleToString(final_entry, _Digits), DoubleToString(final_sl, _Digits), DoubleToString(final_tp1, _Digits)));
      lastLoggedDir = forecast_dir;
   }

   // --- MASTER PATTERN PHASE (5M EXECUTION WINDOW) ---
   MqlRates rates5M[];
   ArraySetAsSeries(rates5M, true);
   if(CopyRates(_Symbol, InpTrend5M, 0, 2, rates5M) < 2) return;

   // Pull Structural HTF Bounds (1H Previous Bar as reference)
   double htf_high = rates1H[1].high;
   double htf_low  = rates1H[1].low;
   datetime htf_time = rates1H[1].time;

   bool is_accumulation = (rates5M[0].high <= htf_high && rates5M[0].low >= htf_low);
   bool is_expansion    = (rates5M[0].high > htf_high || rates5M[0].low < htf_low);
   
   static bool in_trend_up = false;
   static bool in_trend_down = false;

   if(is_expansion) { in_trend_up = false; in_trend_down = false; }
   if(rates5M[0].close > htf_low && rates5M[1].close <= htf_low && !is_accumulation)   in_trend_up = true;
   if(rates5M[0].close < htf_high && rates5M[1].close >= htf_high && !is_accumulation) in_trend_down = true;

   string phase_text = "Accumulation";
   if(is_expansion)     phase_text = "Manipulation";
   else if(in_trend_up) phase_text = "Dist. Long";
   else if(in_trend_down)phase_text = "Dist. Short";

   // Log Market Phase Changes
   if(phase_text != lastLoggedPhase)
   {
      Print(StringFormat("[MP HUD LOG] Market Phase Transition -> %s (Current Close: %s)", phase_text, DoubleToString(closeCurrent, _Digits)));
      lastLoggedPhase = phase_text;
   }

   // --- ACTIVE POSITION MANAGMENT (PROFIT SECURING ENGINE) ---
   if(PositionsTotal() > 0)
   {
      SecureActiveProfits(atrVal[0]);
   }

   // --- ALERTS & MONITORING ENGINE ---
   datetime currentTime = TimeCurrent();
   if(InpSendAlerts && currentTime - lastAlertTime > 300) // 5 Min cooldown limit
   {
      if(forecast_dir == "BUY" && rates5M[0].low <= final_entry && rates5M[1].low > final_entry)
      {
         Print(StringFormat("[MP HUD LOG] Trigger Condition Hit! Buy zone processed at price %s", DoubleToString(closeCurrent, _Digits)));
         Alert(StringFormat("[5M HUD] Buy Limit entry zone reached! Entry: %s", DoubleToString(final_entry, _Digits)));
         AddExecutionArrow(true, rates5M[0].time, final_entry);
         lastAlertTime = currentTime;
         
         if(InpAllowTrades)
         {
            if(PositionsTotal() == 0)
            {
               Print(StringFormat("[MP HUD LOG] Routing BUY Order -> Lot: %s | SL: %s | TP: %s", DoubleToString(InpLotSize, 2), DoubleToString(final_sl, _Digits), DoubleToString(final_tp1, _Digits)));
               trade.Buy(InpLotSize, _Symbol, 0, final_sl, final_tp1);
            }
         }
      }
      if(forecast_dir == "SELL" && rates5M[0].high >= final_entry && rates5M[1].high < final_entry)
      {
         Print(StringFormat("[MP HUD LOG] Trigger Condition Hit! Sell zone processed at price %s", DoubleToString(closeCurrent, _Digits)));
         Alert(StringFormat("[5M HUD] Sell Limit entry zone reached! Entry: %s", DoubleToString(final_entry, _Digits)));
         AddExecutionArrow(false, rates5M[0].time, final_entry);
         lastAlertTime = currentTime;
         
         if(InpAllowTrades)
         {
            if(PositionsTotal() == 0)
            {
               Print(StringFormat("[MP HUD LOG] Routing SELL Order -> Lot: %s | SL: %s | TP: %s", DoubleToString(InpLotSize, 2), DoubleToString(final_sl, _Digits), DoubleToString(final_tp1, _Digits)));
               trade.Sell(InpLotSize, _Symbol, 0, final_sl, final_tp1);
            }
         }
      }
   }

   // --- RENDERS THE TRADING HUD DISPLAY ---
   UpdateDashboard(phase_text, forecast_dir, wBias, dBias, t_4h, t_1h, t_5m, final_entry, final_tp1, final_tp2, final_tp3, final_sl);
   
   // --- DRAW MACRO STRUCTURAL RANGE BACKGROUND BOX ---
   color boxColor = (forecast_dir == "BUY") ? C'24,40,32' : C'45,20,30'; 
   UpdateStructuralBox("HTF_RangeBox", htf_time, htf_high, currentTime + 7200, htf_low, boxColor);

   // --- REFLECT TARGET LEVELS ON THE CHART WITH LABELS ---
   color entryColor = (forecast_dir == "BUY") ? clrMediumAquamarine : clrDeepPink;
   string entryTag  = (forecast_dir == "BUY") ? "ENTRY (61.8%)" : "ENTRY (50.0%)";
   
   UpdateChartLine("ENTRY", final_entry, entryColor, STYLE_DOT, entryTag);
   UpdateChartLine("TP1",   final_tp1,   clrLightSkyBlue,    STYLE_DASH,    "TP1 (0.272)");
   UpdateChartLine("TP2",   final_tp2,   clrAqua,            STYLE_DASH,    "TP2 (0.618)");
   UpdateChartLine("TP3",   final_tp3,   clrMediumPurple,    STYLE_DASH,    "TP3 (1.000)");
   UpdateChartLine("SL",    final_sl,    clrCrimson,         STYLE_DOT,     "STOP LOSS");
}

//+------------------------------------------------------------------+
//| Profit Securing Logic Core                                       |
//+------------------------------------------------------------------+
void SecureActiveProfits(double currentAtr)
{
   if(currentAtr <= 0) return;

   // Loop backwards through open positions to ensure safety across indices
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == 20260531)
      {
         ulong  ticket     = PositionGetInteger(POSITION_TICKET);
         double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL  = PositionGetDouble(POSITION_SL);
         double currentTP  = PositionGetDouble(POSITION_TP);
         double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         long posType = PositionGetInteger(POSITION_TYPE);
         
         // --- BREAK-EVEN ENGINE ---
         if(InpUseBreakEven)
         {
            double triggerDistance = InpBETriggerATR * currentAtr;
            
            if(posType == POSITION_TYPE_BUY)
            {
               // If price moved up far enough and SL is still below entry
               if((currentBid - entryPrice) >= triggerDistance && (currentSL < entryPrice || currentSL == 0))
               {
                  double breakEvenSL = entryPrice + (20 * _Point); // Adds small friction padding
                  trade.PositionModify(ticket, breakEvenSL, currentTP);
                  Print(StringFormat("[PROFIT ENGINE] Buy Position #%d moved to Break-Even at %s", ticket, DoubleToString(breakEvenSL, _Digits)));
                  continue; 
               }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               // If price moved down far enough and SL is still above entry
               if((entryPrice - currentAsk) >= triggerDistance && (currentSL > entryPrice || currentSL == 0))
               {
                  double breakEvenSL = entryPrice - (20 * _Point);
                  trade.PositionModify(ticket, breakEvenSL, currentTP);
                  Print(StringFormat("[PROFIT ENGINE] Sell Position #%d moved to Break-Even at %s", ticket, DoubleToString(breakEvenSL, _Digits)));
                  continue;
               }
            }
         }
         
         // --- TRAILING STOP ENGINE ---
         if(InpUseTrailing)
         {
            double trailOffset = InpTrailDistanceATR * currentAtr;
            
            if(posType == POSITION_TYPE_BUY)
            {
               double targetTrailSL = NormalizeDouble(currentBid - trailOffset, _Digits);
               // Only trail upward; never move a trailing stop lower
               if(targetTrailSL > currentSL && targetTrailSL > entryPrice)
               {
                  trade.PositionModify(ticket, targetTrailSL, currentTP);
                  Print(StringFormat("[PROFIT ENGINE] Trailing Buy SL up for Position #%d to %s", ticket, DoubleToString(targetTrailSL, _Digits)));
               }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               double targetTrailSL = NormalizeDouble(currentAsk + trailOffset, _Digits);
               // Only trail downward; never move a trailing stop higher
               if((targetTrailSL < currentSL || currentSL == 0) && targetTrailSL < entryPrice)
               {
                  trade.PositionModify(ticket, targetTrailSL, currentTP);
                  Print(StringFormat("[PROFIT ENGINE] Trailing Sell SL down for Position #%d to %s", ticket, DoubleToString(targetTrailSL, _Digits)));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Structural Range Visual Box Drawing Engine                       |
//+------------------------------------------------------------------+
void UpdateStructuralBox(string nameKey, datetime t1, double p1, datetime t2, double p2, color boxCol)
{
   string objName = visualsPrefix + nameKey;
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, objName, OBJPROP_BACK, true); 
      ObjectSetInteger(0, objName, OBJPROP_FILL, true); 
   }
   ObjectSetInteger(0, objName, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, objName, OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, objName, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, objName, OBJPROP_PRICE, 1, p2);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, boxCol);
}

//+------------------------------------------------------------------+
//| Permanent Entry Marker Object Creator                            |
//+------------------------------------------------------------------+
void AddExecutionArrow(bool isBuy, datetime barTime, double price)
{
   string arrowName = arrowPrefix + IntegerToString((long)barTime);
   if(ObjectFind(0, arrowName) < 0)
   {
      ObjectCreate(0, arrowName, OBJ_ARROW, 0, barTime, price);
      if(isBuy)
      {
         ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 233); 
         ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrMediumAquamarine);
         ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, ANCHOR_TOP); 
      }
      else
      {
         ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 234); 
         ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrDeepPink);
         ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR, ANCHOR_BOTTOM); 
      }
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3); 
      ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| Dynamic Chart Object Drawing Mechanism                           |
//+------------------------------------------------------------------+
void UpdateChartLine(string nameKey, double price, color lineCol, ENUM_LINE_STYLE style, string labelDescription)
{
   string lineObjectName = levelsPrefix + nameKey + "_Line";
   string txtObjectName  = levelsPrefix + nameKey + "_Text";
   
   if(ObjectFind(0, lineObjectName) < 0)
   {
      ObjectCreate(0, lineObjectName, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, lineObjectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lineObjectName, OBJPROP_HIDDEN, true);
   }
   ObjectSetDouble(0, lineObjectName, OBJPROP_PRICE, price);
   ObjectSetInteger(0, lineObjectName, OBJPROP_COLOR, lineCol);
   ObjectSetInteger(0, lineObjectName, OBJPROP_STYLE, style);
   ObjectSetInteger(0, lineObjectName, OBJPROP_WIDTH, 1);
   
   if(ObjectFind(0, txtObjectName) < 0)
   {
      ObjectCreate(0, txtObjectName, OBJ_TEXT, 0, 0, 0);
      ObjectSetInteger(0, txtObjectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, txtObjectName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, txtObjectName, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, txtObjectName, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, txtObjectName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   }
   ObjectSetInteger(0, txtObjectName, OBJPROP_TIME, TimeCurrent() + PeriodSeconds(PERIOD_CURRENT) * 3);
   ObjectSetDouble(0, txtObjectName, OBJPROP_PRICE, price);
   ObjectSetString(0, txtObjectName, OBJPROP_TEXT, "  " + labelDescription + " [" + DoubleToString(price, _Digits) + "]");
   ObjectSetInteger(0, txtObjectName, OBJPROP_COLOR, lineCol);
}

//+------------------------------------------------------------------+
//| Native UI Rendering Engine                                       |
//+------------------------------------------------------------------+
void UpdateDashboard(string phase, string dir, string wB, string dB, string t4, string t1, string t5, double entry, double tp1, double tp2, double tp3, double sl)
{
   int xStart = 20, yStart = 40, ySpacing = 18;
   
   CreateLabel("lbl_title", "== MASTER PATTERN HUD ==", xStart, yStart, C'220,220,220');
   CreateLabel("lbl_p5",   "5M Phase:   " + phase, xStart, yStart + ySpacing, (phase == "Manipulation")?clrOrange:(phase=="Accumulation")?clrGray:clrLightGreen);
   CreateLabel("lbl_dir",  "Direction:  " + dir, xStart, yStart + (ySpacing*2), (dir=="BUY")?clrTeal:clrDeepPink);
   CreateLabel("lbl_w",    "1W Bias:    " + wB, xStart, yStart + (ySpacing*3), (wB=="BULLISH")?clrGreen:clrRed);
   CreateLabel("lbl_d",    "1D Bias:    " + dB, xStart, yStart + (ySpacing*4), (dB=="BULLISH")?clrGreen:clrRed);
   CreateLabel("lbl_4h",   "4H Trend:   " + t4, xStart, yStart + (ySpacing*5), (t4=="BULLISH")?clrGreen:clrRed);
   CreateLabel("lbl_1h",   "1H Trend:   " + t1, xStart, yStart + (ySpacing*6), (t1=="BULLISH")?clrGreen:clrRed);
   CreateLabel("lbl_5m",   "5M Trend:   " + t5, xStart, yStart + (ySpacing*7), (t5=="BULLISH")?clrGreen:clrRed);
   
   CreateLabel("lbl_ent",  "Entry Target: " + DoubleToString(entry, _Digits), xStart, yStart + (ySpacing*9), clrMediumAquamarine);
   CreateLabel("lbl_tp1",  "TP1 (0.272):  " + DoubleToString(tp1, _Digits), xStart, yStart + (ySpacing*10), clrLightSkyBlue);
   CreateLabel("lbl_tp2",  "TP2 (0.618):  " + DoubleToString(tp2, _Digits), xStart, yStart + (ySpacing*11), clrAqua);
   CreateLabel("lbl_tp3",  "TP3 (1.000):  " + DoubleToString(tp3, _Digits), xStart, yStart + (ySpacing*12), clrMediumPurple);
   CreateLabel("lbl_sl",   "Stop Loss:    " + DoubleToString(sl, _Digits), xStart, yStart + (ySpacing*13), clrCrimson);
}

//+------------------------------------------------------------------+
//| Base Wrapper for Canvas Graphical Labels                        |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color col)
{
   string objName = dashboardName + "_" + name;
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, objName, OBJPROP_FONT, "Lucida Console");
   }
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, col);
}