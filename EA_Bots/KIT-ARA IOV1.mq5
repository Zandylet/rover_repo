//+------------------------------------------------------------------+
//|                                                   KIT-ARA.mq5    |
//|   CHIPS AND FISH - FULL TRADING TERMINAL + VISUAL SIGNALS v2.94  |
//+------------------------------------------------------------------+
#property copyright "KIT-ARA"
#property version   "2.94"
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
input int    MaxTrades         = 10;
input double RetestATRRange    = 0.5;
input double WeakTrendADX      = 25;
input double HighVolATRFactor  = 2.0;

//--- INDICATORS
input int FastEMA = 9, SlowEMA = 21, IntraEMA = 55, TrendEMA = 200;
input int ADXPeriod = 14, MinADX = 22, MomPeriod = 14;

//--- GLOBALS
int hFast, hSlow, hIntra, hTrend, hADX, hMom, hATR, hHTF, hD1;
bool BotActive = true;
string tradeReason = "SYSTEM IDLE";

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit() {

   hFast  = iMA(_Symbol, PERIOD_M15, FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, PERIOD_M15, SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hIntra = iMA(_Symbol, PERIOD_M15, IntraEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, PERIOD_M15, TrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hHTF   = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
   hD1    = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);

   hADX = iADX(_Symbol, PERIOD_M15, ADXPeriod);
   hMom = iMomentum(_Symbol, PERIOD_M15, MomPeriod, PRICE_CLOSE);
   hATR = iATR(_Symbol, PERIOD_M15, ATRPeriod);

   trade.SetExpertMagicNumber(123456);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+
void OnTick() {

   double f[], s[], i[], t[], adx[], mom[], atr[];
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(i,true);
   ArraySetAsSeries(t,true); ArraySetAsSeries(adx,true); ArraySetAsSeries(mom,true);
   ArraySetAsSeries(atr,true);

   if(CopyBuffer(hFast,0,0,3,f)<3 ||
      CopyBuffer(hSlow,0,0,3,s)<3 ||
      CopyBuffer(hIntra,0,0,3,i)<3 ||
      CopyBuffer(hTrend,0,0,3,t)<3 ||
      CopyBuffer(hADX,0,0,3,adx)<3 ||
      CopyBuffer(hMom,0,0,2,mom)<2 ||
      CopyBuffer(hATR,0,0,2,atr)<2) return;

   double atrVal = atr[0];

   // === ANTI-WHIPSAW ADX FILTER ===
   bool adxRising = (adx[0] > adx[1] && adx[1] > adx[2]);

   if(!adxRising) {
      BotActive   = false;
      tradeReason = "ADX FLAT / FALLING (ANTI-WHIPSAW)";
      return;
   }

   // --- TREND CONDITIONS
   bool bullishD1 = SymbolInfoDouble(_Symbol, SYMBOL_BID) > iMA(_Symbol, PERIOD_D1, 200, 0, MODE_EMA, PRICE_CLOSE);
   bool bull = i[0] > t[0] && adx[0] >= MinADX && bullishD1;
   bool bear = i[0] < t[0] && adx[0] >= MinADX && !bullishD1;

   bool momBuy  = mom[0] > 100 && mom[0] > mom[1];
   bool momSell = mom[0] < 100 && mom[0] < mom[1];

   bool buySig  = f[0] > i[0] && s[0] > i[0] && bull && momBuy;
   bool sellSig = f[0] < i[0] && s[0] < i[0] && bear && momSell;

   if(!BotActive) return;

   if(GetActiveCount() < MaxTrades) {

      if(buySig) {
         tradeReason = "BUY (ADX EXPANDING)";
         Execute(ORDER_TYPE_BUY);
      }

      if(sellSig) {
         tradeReason = "SELL (ADX EXPANDING)";
         Execute(ORDER_TYPE_SELL);
      }
   }
}

//+------------------------------------------------------------------+
//| EXECUTION                                                        |
//+------------------------------------------------------------------+
bool Execute(ENUM_ORDER_TYPE type) {

   double lot = (ManualLotSize > 0) ? ManualLotSize : 0.01;

   if(type == ORDER_TYPE_BUY)
      return trade.Buy(lot, _Symbol);

   if(type == ORDER_TYPE_SELL)
      return trade.Sell(lot, _Symbol);

   return false;
}

//+------------------------------------------------------------------+
//| POSITION COUNT                                                   |
//+------------------------------------------------------------------+
int GetActiveCount() {
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == 123456)
         count++;
   }
   return count;
}
