//+------------------------------------------------------------------+
//|                                                      KIT-ARA.mq5 |
//|   CHIPS AND FISH - FULL TRADING TERMINAL + VISUAL SIGNALS v2.87  |
//+------------------------------------------------------------------+
#property copyright "KIT-ARA"
#property version   "2.87"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade trade;
CPositionInfo posInfo;

//--- INPUTS
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
int hFast, hSlow, hIntra, hTrend, hADX, hMom, hATR, hHTF, hD1;
int hADX_HTF;
string tradeReason = "SYSTEM IDLE";
bool BotActive = true; 
double PauseThresholdADX = 20; 

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

   trade.SetExpertMagicNumber(123456);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick() {
   if(IsNFPPauseActive()) { tradeReason = "NFP SHIELD ACTIVE"; BotActive=false; DrawTerminalHUD(0,0,0); return; }
   if(IsFridayExit()) { BotActive=false; DrawTerminalHUD(0,0,0); return; }

   double f[], s[], i[], t[], adx[], mom[], atr[], htf[], d1[], adxHTF[];
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(i,true);
   ArraySetAsSeries(t,true); ArraySetAsSeries(adx,true); ArraySetAsSeries(mom,true);
   ArraySetAsSeries(atr,true); ArraySetAsSeries(htf,true); ArraySetAsSeries(d1,true); ArraySetAsSeries(adxHTF,true);

   // Copy data from handles to arrays
   if(CopyBuffer(hFast,0,0,3,f)<3 || CopyBuffer(hSlow,0,0,3,s)<3 || CopyBuffer(hIntra,0,0,3,i)<3 ||
      CopyBuffer(hTrend,0,0,3,t)<3 || CopyBuffer(hADX,0,0,1,adx)<1 || CopyBuffer(hMom,0,0,2,mom)<2 ||
      CopyBuffer(hATR,0,0,2,atr)<2 || CopyBuffer(hHTF,0,0,1,htf)<1 || CopyBuffer(hD1,0,0,1,d1)<1 || CopyBuffer(hADX_HTF,0,0,1,adxHTF)<1) return;

   double atrVal = atr[0];
   double atrPrev = atr[1]; // Used to check volatility
   double curSpread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;

   if(curSpread > (atrVal / _Point) * MaxSpread) { 
      tradeReason="SPREAD TOO WIDE"; 
      BotActive=false; 
      DrawTerminalHUD(adx[0],mom[0],atrVal); 
      return; 
   }

   BotActive = true;
   if(adx[0] < PauseThresholdADX) { BotActive=false; tradeReason="M15 TREND TOO WEAK - BOT PAUSED"; }
   
   // FIXED: Use the copied buffer for ATR comparison
   if(atrVal > atrPrev * HighVolATRFactor) { BotActive=false; tradeReason="VOLATILE MARKET - BOT PAUSED"; }
   
   if(adxHTF[0] < MinADX) { BotActive=false; tradeReason="H1 TREND WEAK - BOT PAUSED"; }
   if(!BotActive) { DrawTerminalHUD(adx[0],mom[0],atrVal); return; }

   bool bullishD1 = SymbolInfoDouble(_Symbol,SYMBOL_BID) > d1[0];
   bool bearishD1 = SymbolInfoDouble(_Symbol,SYMBOL_BID) < d1[0];

   bool bull = i[0] > t[0] && adx[0] >= MinADX && bullishD1;
   bool bear = i[0] < t[0] && adx[0] >= MinADX && bearishD1;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   bool htfBuy = bid > htf[0];
   bool htfSell = bid < htf[0];
   bool momBuy = mom[0] > 100 && mom[0] > mom[1];
   bool momSell = mom[0] < 100 && mom[0] < mom[1];

   bool buySig  = f[0] > i[0] && s[0] > i[0] && bull && momBuy && htfBuy;
   bool sellSig = f[0] < i[0] && s[0] < i[0] && bear && momSell && htfSell;

   bool buyRetest  = bull && htfBuy && ask > i[0] && ask < (i[0] + (atrVal*RetestATRRange)) && momBuy;
   bool sellRetest = bear && htfSell && bid < i[0] && bid > (i[0] - (atrVal*RetestATRRange)) && momSell;

   double lotMultiplier = 1.0;
   if(adx[0] < WeakTrendADX || adxHTF[0] < WeakTrendADX) lotMultiplier = 0.5;

   if(GetActiveCount() < MaxTrades) {
      if(buySig || buyRetest) { tradeReason = buyRetest ? "RETEST BUY" : "BREAKOUT BUY"; Execute(ORDER_TYPE_BUY, atrVal, lotMultiplier); }
      else if(sellSig || sellRetest) { tradeReason = sellRetest ? "RETEST SELL" : "BREAKOUT SELL"; Execute(ORDER_TYPE_SELL, atrVal, lotMultiplier); }
   }

   ManageSecuringProfits(atrVal);

   string htfTrendStr = bid > htf[0] ? "BULL" : "BEAR";
   string ltfTrendStr = bid > t[0] ? "BULL" : "BEAR";

   DrawSignalsOnChart(buySig, sellSig, buyRetest, sellRetest);
   DrawTrendLabels(htfTrendStr, ltfTrendStr);

   // Time and Price for Gradient Zones
   datetime t0 = iTime(_Symbol, PERIOD_M15, 0);
   datetime t1 = iTime(_Symbol, PERIOD_M15, 1);
   double lowM15 = iLow(_Symbol, PERIOD_M15, 1);
   double highM15 = iHigh(_Symbol, PERIOD_M15, 0);

   color htfColor = (bid > htf[0]) ? clrLime : clrRed;
   color ltfColor = (bid > t[0]) ? clrLime : clrRed;

   DrawTrendGradient("HTF_Zone", htfColor, t1, t0, lowM15, highM15);
   DrawTrendGradient("LTF_Zone", ltfColor, t1, t0, lowM15, highM15);

   DrawTerminalHUD(adx[0],mom[0],atrVal);
}

//+------------------------------------------------------------------+
//| Gradient trend zones function                                     |
//+------------------------------------------------------------------+
void DrawTrendGradient(string name, color zoneColor, datetime startTime, datetime endTime, double lowPrice, double highPrice)
{
    ObjectDelete(0, name);
    if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, startTime, highPrice, endTime, lowPrice)) {
       ObjectSetInteger(0, name, OBJPROP_COLOR, zoneColor);
       ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
       ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
       ObjectSetInteger(0, name, OBJPROP_BACK, true);
       ObjectSetInteger(0, name, OBJPROP_FILL, true);
    }
}

//+------------------------------------------------------------------+
//| PLACEHOLDERS FOR MISSING FUNCTIONS                               |
//+------------------------------------------------------------------+
bool IsNFPPauseActive() { return false; }
bool IsFridayExit() { 
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return (dt.day_of_week == 5 && dt.hour >= ExitHourFriday);
}
int GetActiveCount() {
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == 123456) count++;
   }
   return count;
}
void Execute(ENUM_ORDER_TYPE type, double atr, double mult) {
   double lot = (ManualLotSize > 0) ? ManualLotSize : 0.01; // Simplistic lot logic
   if(type == ORDER_TYPE_BUY) trade.Buy(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), 0, 0);
   if(type == ORDER_TYPE_SELL) trade.Sell(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), 0, 0);
}
void ManageSecuringProfits(double atr) {}
void DrawSignalsOnChart(bool b, bool s, bool br, bool sr) {}
void DrawTrendLabels(string htf, string ltf) {}
void DrawTerminalHUD(double a, double m, double atr) {
   Comment("Reason: ", tradeReason, "\nADX: ", a, "\nMom: ", m);
}