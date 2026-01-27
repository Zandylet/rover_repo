//+------------------------------------------------------------------+
//|                                                      KIT-ARA.mq5 |
//|   CHIPS AND FISH - FULL TRADING TERMINAL + VISUAL SIGNALS v3.00   |
//+------------------------------------------------------------------+
#property copyright "KIT-ARA"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade trade;
CPositionInfo posInfo;

//--- TELEGRAM INPUTS
input string   InpTelegramToken = "8450254645:AAF7Q96gfqjXZlK93Jf6alij92zEXE93Pos"; 
input string   InpTelegramID    = "1670920528";    
input bool     InpNotifications = true;             

//--- EXISTING INPUTS
input double RiskPercent       = 0.5;   
input double ManualLotSize     = 0.0;   
input double MaxSpread         = 3.0;   
input int    ATRPeriod         = 14;
input double ATR_SL_Mult       = 2.0;
input int    MaxTrades         = 3;
input double RetestATRRange    = 0.5;   
input double WeakTrendADX      = 25;   
input double HighVolATRFactor  = 2.0;   

//--- EXIT & SAFETY INPUTS
input int    ExitHourFriday    = 21;
input int    MinsBeforeNFP     = 60;    
input int    MinsAfterNFP      = 30;    

//--- INDICATORS
input int FastEMA = 9, SlowEMA = 21, IntraEMA = 55, TrendEMA = 200;
input int ADXPeriod = 14, MinADX = 22, MomPeriod = 14;

//--- GLOBALS
int hFast, hSlow, hIntra, hTrend, hADX, hMom, hATR, hHTF, hD1, hADX_HTF, hATR_M3;
string tradeReason = "SYSTEM IDLE";
string m3_status = "SCANNING...";
bool BotActive = true; 
bool ManualPause = false;
bool PrevBotState = true; 
double PauseThresholdADX = 20; 

//--- PULLBACK TRACKING GLOBALS
bool pullbackActive = false;
string lastPullbackType = "";

//--- NOTIFICATION & EQUITY GLOBALS
string lastSession = "";
bool londonSweeped = false;
double londonHigh = 0, londonLow = 0;
string lastMarketState = "";
datetime lastBreakoutTime = 0;
datetime lastM3BreakoutTime = 0;
datetime lastRetestNotify = 0;
double initialEquity = 0;
double equityTarget = 0;
double equityStopLoss = 0; 

//--- HUD SETTINGS
#define HUD_X 20
#define HUD_Y 30
#define LINE_SPACING 20
#define BTN_WIDTH 120
#define BTN_HEIGHT 25

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   hFast  = iMA(_Symbol, PERIOD_M15, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, PERIOD_M15, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hIntra = iMA(_Symbol, PERIOD_M15, IntraEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, PERIOD_M15, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hHTF   = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE); 
   hD1    = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE); 

   hADX     = iADX(_Symbol, PERIOD_M15, ADXPeriod);
   hADX_HTF = iADX(_Symbol, PERIOD_H1, ADXPeriod); 
   hMom     = iMomentum(_Symbol, PERIOD_M15, MomPeriod, PRICE_CLOSE);
   hATR     = iATR(_Symbol, PERIOD_M15, ATRPeriod);
   hATR_M3  = iATR(_Symbol, PERIOD_M3, ATRPeriod);

   trade.SetExpertMagicNumber(123456);
   initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   equityTarget = initialEquity * 2;
   equityStopLoss = initialEquity * 0.1; 
   
   Notify("KIT-ARA Bot Initialized v3.00.\nStart Equity: " + DoubleToString(initialEquity, 2) + "\nTarget: " + DoubleToString(equityTarget, 2));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) {
   ObjectsDeleteAll(0, "HUD_");
   ObjectDelete(0, "RETEST_PRICE_ZONE");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   if(IsNFPPauseActive()) { tradeReason = "NFP SHIELD ACTIVE"; BotActive=false; DrawTerminalHUD(0,0,0,0,"NONE"); return; }
   if(IsFridayExit()) { BotActive=false; tradeReason = "FRIDAY EXIT ACTIVE"; DrawTerminalHUD(0,0,0,0,"NONE"); return; }

   double f[], s[], i[], t[], adx[], mom[], atr[], htf[], d1[], adxHTF[], atrM3[];
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(i,true);
   ArraySetAsSeries(t,true); ArraySetAsSeries(adx,true); ArraySetAsSeries(mom,true);
   ArraySetAsSeries(atr,true); ArraySetAsSeries(htf,true); ArraySetAsSeries(d1,true); 
   ArraySetAsSeries(adxHTF,true); ArraySetAsSeries(atrM3, true);

   MqlRates rates[], ratesM3[];
   ArraySetAsSeries(rates, true); ArraySetAsSeries(ratesM3, true);

   if(CopyBuffer(hFast,0,0,3,f)<3 || CopyBuffer(hSlow,0,0,3,s)<3 || CopyBuffer(hIntra,0,0,3,i)<3 ||
      CopyBuffer(hTrend,0,0,3,t)<3 || CopyBuffer(hADX,0,0,1,adx)<1 || CopyBuffer(hMom,0,0,2,mom)<2 ||
      CopyBuffer(hATR,0,0,2,atr)<2 || CopyBuffer(hHTF,0,0,1,htf)<1 || CopyBuffer(hD1,0,0,1,d1)<1 || 
      CopyBuffer(hADX_HTF,0,0,1,adxHTF)<1 || CopyRates(_Symbol, PERIOD_M15, 0, 4, rates) < 4 ||
      CopyBuffer(hATR_M3,0,0,1,atrM3)<1 || CopyRates(_Symbol, PERIOD_M3, 0, 2, ratesM3) < 2) return;

   double atrVal = atr[0];
   double atrPrev = atr[1]; 
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   //--- PULLBACK & AUTO-TRADE LOGIC
   bool isBullTrend = (i[0] > t[0] && bid > d1[0]);
   bool isBearTrend = (i[0] < t[0] && bid < d1[0]);

   if(isBullTrend) {
      if(!pullbackActive && bid < f[0]) {
         pullbackActive = true;
         lastPullbackType = "BULLISH";
         tradeReason = "PULLBACK STARTED (BUY)";
         Notify("🔄 PULLBACK STARTED: Price dipped below 9 EMA (" + _Symbol + ")");
      }
      else if(pullbackActive && lastPullbackType == "BULLISH" && bid > f[0]) {
         pullbackActive = false;
         tradeReason = "PULLBACK ENTRY (BUY)";
         if(GetActiveCount() < MaxTrades && !ManualPause) {
            if(Execute(ORDER_TYPE_BUY, atrVal, 1.0))
               Notify("✅ PULLBACK COMPLETED: Auto-Buy Executed (" + _Symbol + ")");
         }
      }
   }
   else if(isBearTrend) {
      if(!pullbackActive && ask > f[0]) {
         pullbackActive = true;
         lastPullbackType = "BEARISH";
         tradeReason = "PULLBACK STARTED (SELL)";
         Notify("🔄 PULLBACK STARTED: Price rose above 9 EMA (" + _Symbol + ")");
      }
      else if(pullbackActive && lastPullbackType == "BEARISH" && ask < f[0]) {
         pullbackActive = false;
         tradeReason = "PULLBACK ENTRY (SELL)";
         if(GetActiveCount() < MaxTrades && !ManualPause) {
            if(Execute(ORDER_TYPE_SELL, atrVal, 1.0))
               Notify("✅ PULLBACK COMPLETED: Auto-Sell Executed (" + _Symbol + ")");
         }
      }
   }

   //--- CALCULATE FORECAST
   string forecastDir = "NEUTRAL";
   double forecastPct = CalculateForecast(f[0], s[0], i[0], t[0], htf[0], d1[0], mom[0], adx[0], forecastDir);

   CheckEquityProtection();
   CheckSessions();
   CheckNYCross(f[0], s[0], f[1], s[1]);
   CheckLondonSweep(rates[0].high, rates[0].low);
   CheckMarketState(adx[0]);
   CheckM15Breakout(rates, atrVal, forecastPct, forecastDir);
   CheckM3Breakout(ratesM3, atrM3[0], forecastPct, forecastDir);

   double curSpread = (ask - bid) / _Point;

   // 1. EMA OVERLAP FILTER
   bool overlap = false;
   for(int idx=0; idx<3; idx++) {
      if(i[idx] >= rates[idx].low && i[idx] <= rates[idx].high) { overlap = true; break; }
   }
   bool priceThroughEMA = overlap;

   if(atrVal > atrPrev * HighVolATRFactor) { 
      Notify("⚠️ HIGH VOLATILITY DETECTED on " + _Symbol);
      BotActive=false; 
      tradeReason="VOLATILE MARKET - BOT PAUSED"; 
   }

   if(curSpread > (atrVal / _Point) * MaxSpread) { 
      tradeReason="SPREAD TOO WIDE"; 
      BotActive=false; 
      DrawTerminalHUD(adx[0],mom[0],atrVal,forecastPct,forecastDir); 
      return; 
   }

   // 3. BOT ACTIVE STATE
   bool currentBotState = !ManualPause;
   if(adx[0] < PauseThresholdADX || adxHTF[0] < MinADX) currentBotState = false;
   if(priceThroughEMA) currentBotState = false; 

   if(currentBotState != PrevBotState) {
      string stateReason = (ManualPause) ? "Manual User Action" : (priceThroughEMA ? "EMA Price Overlap" : "Low ADX Consolidation");
      Notify("🤖 Bot Status Change: " + (currentBotState ? "ACTIVE ✅" : "PAUSED ⏸️") + " (" + _Symbol + ")\nReason: " + stateReason);
      PrevBotState = currentBotState;
   }

   if(ManualPause) { BotActive = false; tradeReason = "USER MANUALLY PAUSED"; } 
   else {
      BotActive = currentBotState;
      if(!BotActive) {
         if(priceThroughEMA) tradeReason = "EMA FILTER: PRICE OVERLAP (C0-C2)";
         else tradeReason = "TREND TOO WEAK - BOT PAUSED";
      }
   }
   
   bool bullishD1 = bid > d1[0];
   bool bull = i[0] > t[0] && adx[0] >= MinADX && bullishD1;
   bool bear = i[0] < t[0] && adx[0] >= MinADX && !bullishD1;
   
   UpdateRetestBox(bull, bear, i[0], atrVal); 
   CheckRetestEvent(bull, bear, i[0], atrVal, forecastPct, forecastDir);

   if(!BotActive) { DrawTerminalHUD(adx[0],mom[0],atrVal,forecastPct,forecastDir); return; }

   bool htfBuy = bid > htf[0];
   bool htfSell = bid < htf[0];
   bool momBuy = mom[0] > 100 && mom[0] > mom[1];
   bool momSell = mom[0] < 100 && mom[0] < mom[1];

   bool buySig   = f[0] > i[0] && s[0] > i[0] && bull && momBuy && htfBuy;
   bool sellSig = f[0] < i[0] && s[0] < i[0] && bear && momSell && htfSell;
   bool buyRetest   = bull && htfBuy && ask > i[0] && ask < (i[0] + (atrVal*RetestATRRange)) && momBuy;
   bool sellRetest = bear && htfSell && bid < i[0] && bid > (i[0] - (atrVal*RetestATRRange)) && momSell;

   double lotMultiplier = 1.0;
   if(adx[0] < WeakTrendADX || adxHTF[0] < WeakTrendADX) lotMultiplier = 0.5;

   if(GetActiveCount() < MaxTrades) {
      if(buySig || buyRetest) { 
         tradeReason = buyRetest ? "RETEST BUY" : "BREAKOUT BUY"; 
         if(Execute(ORDER_TYPE_BUY, atrVal, lotMultiplier)) 
            Notify("🚀 BUY TRADE TAKEN: " + _Symbol + "\nType: " + tradeReason + "\nForecast: " + DoubleToString(forecastPct,1) + "% BULLISH");
      }
      else if(sellSig || sellRetest) { 
         tradeReason = sellRetest ? "RETEST SELL" : "BREAKOUT SELL"; 
         if(Execute(ORDER_TYPE_SELL, atrVal, lotMultiplier))
            Notify("📉 SELL TRADE TAKEN: " + _Symbol + "\nType: " + tradeReason + "\nForecast: " + DoubleToString(forecastPct,1) + "% BEARISH");
      }
   }

   ManageSecuringProfits(atrVal);
   DrawTerminalHUD(adx[0],mom[0],atrVal,forecastPct,forecastDir);
}

//+------------------------------------------------------------------+
//| M3 BREAKOUT LOGIC                                                |
//+------------------------------------------------------------------+
void CheckM3Breakout(MqlRates &rates[], double atr, double pct, string dir) {
   if(rates[0].time == lastM3BreakoutTime) return;
   double body = MathAbs(rates[1].close - rates[1].open);
   if(body > atr) {
      m3_status = "VALID BREAKOUT";
      Notify("⚡ M3 SCALP BREAKOUT: High Momentum detected on " + _Symbol + "\nForecast: " + DoubleToString(pct, 1) + "% " + dir);
      lastM3BreakoutTime = rates[0].time;
   } else { m3_status = "SCANNING..."; }
}

//+------------------------------------------------------------------+
//| FORECAST ENGINE                                                  |
//+------------------------------------------------------------------+
double CalculateForecast(double f, double s, double i, double t, double htf, double d1, double mom, double adx, string &dir) {
   double score = 0;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(f > i && s > i) score += 20;
   if(price > t) score += 15;
   if(price > htf) score += 15;
   if(price > d1) score += 20;
   if(mom > 100) score += 15;
   if(adx > 25) score += 15;
   if(score > 55) { dir = "BULLISH"; return score; }
   if(score < 45) { dir = "BEARISH"; return (100 - score); }
   dir = "NEUTRAL"; return 50.0;
}

//+------------------------------------------------------------------+
//| EVENT HANDLERS                                                   |
//+------------------------------------------------------------------+
void CheckRetestEvent(bool bull, bool bear, double emaVal, double atr, double pct, string dir) {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool inZone = false;
   if(bull && ask > emaVal && ask < (emaVal + (atr * RetestATRRange))) inZone = true;
   if(bear && bid < emaVal && bid > (emaVal - (atr * RetestATRRange))) inZone = true;
   if(inZone && TimeCurrent() > lastRetestNotify + 3600) { 
      Notify("🔄 RETEST DETECTED: Price in EMA Zone (" + _Symbol + ")\nForecast: " + DoubleToString(pct, 1) + "% " + dir);
      lastRetestNotify = TimeCurrent();
   }
}

void CheckM15Breakout(MqlRates &rates[], double atr, double pct, string dir) {
   if(rates[0].time == lastBreakoutTime) return;
   double body = MathAbs(rates[1].close - rates[1].open);
   if(body > atr) {
      if(rates[1].close > rates[2].high || rates[1].close < rates[2].low) {
         Notify("🔥 M15 RANGE BREAKOUT on " + _Symbol + "\nForecast: " + DoubleToString(pct, 1) + "% " + dir);
         lastBreakoutTime = rates[0].time;
      }
   }
}

//+------------------------------------------------------------------+
//| EQUITY & PROTECTION LOGIC                                        |
//+------------------------------------------------------------------+
void CheckEquityProtection() {
   double curEq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(curEq >= equityTarget) {
      equityStopLoss = equityTarget * 0.80; 
      equityTarget = curEq * 2; 
      Notify("🎊 EQUITY DOUBLED!\nNew Goal: " + DoubleToString(equityTarget, 2) + "\nSafety Floor Set at: " + DoubleToString(equityStopLoss, 2));
   }
   if(curEq <= equityStopLoss && equityStopLoss > 0) {
      CloseAllPositions();
      ManualPause = true;
      tradeReason = "EQUITY STOP LOSS HIT";
      Notify("🚨 EQUITY STOP LOSS HIT!\nAll trades closed to protect capital.\nBot Paused at: " + DoubleToString(curEq, 2));
   }
}

void CheckSessions() {
   MqlDateTime dt; TimeGMT(dt);
   string currentSession = "";
   if(dt.hour == 0 && dt.min == 0) currentSession = "Sydney";
   else if(dt.hour == 23 && dt.min == 0) currentSession = "Tokyo";
   else if(dt.hour == 8 && dt.min == 0)  currentSession = "London";
   else if(dt.hour == 13 && dt.min == 0) currentSession = "New York";
   if(currentSession != "" && currentSession != lastSession) {
      Notify("Session: " + currentSession + " Started");
      lastSession = currentSession;
   }
}

void CheckNYCross(double f0, double s0, double f1, double s1) {
   MqlDateTime dt; TimeGMT(dt);
   if(dt.hour >= 13 && dt.hour <= 21) {
      if(f1 <= s1 && f0 > s0) Notify("⚡ NY M15 EMA Cross: BULLISH");
      else if(f1 >= s1 && f0 < s0) Notify("⚡ NY M15 EMA Cross: BEARISH");
   }
}

void CheckLondonSweep(double high, double low) {
   MqlDateTime dt; TimeGMT(dt);
   if(dt.hour >= 13 && !londonSweeped && londonHigh > 0) {
      if(high > londonHigh) { Notify("🎯 NY Sweep: London High Broken"); londonSweeped = true; }
      else if(low < londonLow) { Notify("🎯 NY Sweep: London Low Broken"); londonSweeped = true; }
   }
}

void CheckMarketState(double adx) {
   string state = (adx >= 25) ? "TRENDING" : (adx <= 20 ? "CONSOLIDATING" : "");
   if(state != "" && state != lastMarketState) {
      Notify("📊 Market Condition: " + state);
      lastMarketState = state;
   }
}

void UpdateRetestBox(bool bull, bool bear, double emaVal, double atr) {
   string name = "RETEST_PRICE_ZONE";
   if(!bull && !bear) { ObjectDelete(0, name); return; }
   double price1 = emaVal;
   double price2 = bull ? (emaVal + (atr * RetestATRRange)) : (emaVal - (atr * RetestATRRange));
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, TimeCurrent(), price1, TimeCurrent()+3600, price2);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   } else {
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price1);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price2);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, bull ? clrLimeGreen : clrTomato);
}

void Notify(string msg) {
   if(!InpNotifications) return;
   Print(msg);
   SendNotification(msg);
   SendTelegram(msg);      
}

void SendTelegram(string message) {
   if(InpTelegramToken == "YOUR_BOT_TOKEN" || InpTelegramID == "YOUR_CHAT_ID") return;
   string url = "https://api.telegram.org/bot" + InpTelegramToken + "/sendMessage";
   string params = "chat_id=" + InpTelegramID + "&text=" + message;
   char data[], result[];
   string headers;
   StringToCharArray(params, data);
   WebRequest("POST", url, headers, 10, data, result, headers);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK) {
      if(sparam == "HUD_BTN_CLOSE") { CloseAllPositions(); Notify("🛑 ALL POSITIONS CLOSED MANUALLY"); }
      else if(sparam == "HUD_BTN_90") { TakePercentageProfit(0.90); Notify("💰 90% PROFIT TAKEN"); }
      else if(sparam == "HUD_BTN_PAUSE") {
         ManualPause = !ManualPause;
         Notify(ManualPause ? "⏸️ BOT MANUALLY PAUSED" : "▶️ BOT MANUALLY RESUMED");
         ObjectSetString(0, "HUD_BTN_PAUSE", OBJPROP_TEXT, ManualPause ? "RESUME BOT" : "PAUSE BOT");
         ObjectSetInteger(0, "HUD_BTN_PAUSE", OBJPROP_BGCOLOR, ManualPause ? clrLime : clrCrimson);
      }
   }
}

//+------------------------------------------------------------------+
//| UPDATED HUD RENDERER                                             |
//+------------------------------------------------------------------+
void DrawTerminalHUD(double adx_val, double mom_val, double atr_val, double forecast_pct, string forecast_dir) {
   MqlDateTime dt; TimeCurrent(dt);
   int h1_rem = 60 - dt.min;
   int m15_rem = 15 - (dt.min % 15);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (ask - bid) / _Point;
   
   double d1_v[], htf_v[], ltf_v[];
   ArraySetAsSeries(d1_v, true); ArraySetAsSeries(htf_v, true); ArraySetAsSeries(ltf_v, true);
   if(CopyBuffer(hD1, 0, 0, 1, d1_v) < 1) return;
   if(CopyBuffer(hHTF, 0, 0, 1, htf_v) < 1) return;
   if(CopyBuffer(hTrend, 0, 0, 1, ltf_v) < 1) return;

   string dailyBias = (bid > d1_v[0]) ? "BULLISH" : "BEARISH";
   string htfStatus = (bid > htf_v[0]) ? "BULL" : "BEAR";
   string ltfStatus = (bid > ltf_v[0]) ? "BULL" : "BEAR";
   
   color htfCol = (htfStatus == "BULL") ? clrLime : clrRed;
   color ltfCol = (ltfStatus == "BULL") ? clrLime : clrRed;
   color spreadCol = (spread > (atr_val / _Point) * MaxSpread) ? clrRed : clrWhite;
   color forecastCol = (forecast_dir == "BULLISH") ? clrLime : (forecast_dir == "BEARISH" ? clrRed : clrWhite);
   color m3Col = (m3_status == "VALID BREAKOUT") ? clrGold : clrWhite;

   UpdateLabel("HUD_NAME", "SYSTEM_NAME: KIT-ARA | " + _Symbol, HUD_X, HUD_Y, clrWhite);
   UpdateLabel("HUD_HTF", "HTF TREND STATUS: " + htfStatus, HUD_X, HUD_Y + LINE_SPACING, htfCol);
   UpdateLabel("HUD_LTF", "LTF TREND STATUS: " + ltfStatus, HUD_X, HUD_Y + (LINE_SPACING*2), ltfCol);
   UpdateLabel("HUD_BIAS", "DAILY BIAS: " + dailyBias, HUD_X, HUD_Y + (LINE_SPACING*3), clrGold);
   UpdateLabel("HUD_H1", "H1 CANDLE TIMER: " + IntegerToString(h1_rem) + " MINS", HUD_X, HUD_Y + (LINE_SPACING*4), clrAqua);
   UpdateLabel("HUD_M15", "M15 CANDLE TIMER: " + IntegerToString(m15_rem) + " MINS", HUD_X, HUD_Y + (LINE_SPACING*5), clrAqua);
   UpdateLabel("HUD_SPREAD", "CURRENT SPREAD: " + DoubleToString(spread, 1), HUD_X, HUD_Y + (LINE_SPACING*6), spreadCol);
   UpdateLabel("HUD_REASON", "REASON: " + tradeReason, HUD_X, HUD_Y + (LINE_SPACING*7), clrYellow);
   UpdateLabel("HUD_TARGET", "NEXT EQUITY GOAL: " + DoubleToString(equityTarget, 2), HUD_X, HUD_Y + (LINE_SPACING*8), clrLime); 
   UpdateLabel("HUD_FORECAST", "MARKET FORECAST: " + DoubleToString(forecast_pct,1) + "% " + forecast_dir, HUD_X, HUD_Y + (LINE_SPACING*9), forecastCol);
   UpdateLabel("HUD_M3", "M3 BREAKOUT STATUS: " + m3_status, HUD_X, HUD_Y + (LINE_SPACING*10), m3Col);
   UpdateLabel("HUD_PSYCH", "TRUST THE SYSTEM.", HUD_X, HUD_Y + (LINE_SPACING*11), clrLightGray);

   CreateButton("HUD_BTN_CLOSE", "CLOSE ALL", HUD_X, HUD_Y + (LINE_SPACING*13), clrRed);
   CreateButton("HUD_BTN_90", "TAKE 90% PROFIT", HUD_X + BTN_WIDTH + 5, HUD_Y + (LINE_SPACING*13), clrOrange);
   CreateButton("HUD_BTN_PAUSE", ManualPause ? "RESUME BOT" : "PAUSE BOT", HUD_X, HUD_Y + (LINE_SPACING*13) + BTN_HEIGHT + 5, ManualPause ? clrLime : clrCrimson);
}

void UpdateLabel(string name, string text, int x, int y, color col) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Verdana");
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
}

void CreateButton(string name, string text, int x, int y, color bgCol) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, BTN_WIDTH);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, BTN_HEIGHT);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, name, OBJPROP_FONT, "Verdana");
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgCol);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
}

bool IsNFPPauseActive() { return false; }
bool IsFridayExit() { MqlDateTime dt; TimeCurrent(dt); return (dt.day_of_week == 5 && dt.hour >= ExitHourFriday); }
int GetActiveCount() {
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) if(posInfo.SelectByIndex(i) && posInfo.Magic() == 123456) count++;
   return count;
}
bool Execute(ENUM_ORDER_TYPE type, double atr, double mult) {
   double lot = (ManualLotSize > 0) ? ManualLotSize : 0.01;
   if(type == ORDER_TYPE_BUY) return trade.Buy(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), 0, 0);
   if(type == ORDER_TYPE_SELL) return trade.Sell(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), 0, 0);
   return false;
}
void CloseAllPositions() { for(int i=PositionsTotal()-1; i>=0; i--) if(posInfo.SelectByIndex(i) && posInfo.Magic() == 123456) trade.PositionClose(posInfo.Ticket()); }
void TakePercentageProfit(double percentage) {
   for(int i=PositionsTotal()-1; i>=0; i--) if(posInfo.SelectByIndex(i) && posInfo.Magic() == 123456) trade.PositionClosePartial(posInfo.Ticket(), NormalizeDouble(posInfo.Volume()*percentage, 2));
}
void ManageSecuringProfits(double atr) {}
