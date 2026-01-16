//+------------------------------------------------------------------+
//|                                                  KIT-ARA.mq5     |
//|                                  Your Virtual Trading Assistant  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "5.000" 
#property strict

#include <Trade\Trade.mqh>

//--- Assistant Personalization
input string   InpAssistantName = "MISSION CONTROL";
input string   InpUserTitle     = "Commander"; 

//--- Inputs
input int      InpFastEMA   = 9;      
input int      InpSlowEMA   = 21;     
input int      InpIntraEMA  = 55;     
input int      InpTrendEMA  = 200;    
input double   InpLotSize   = 0.00;   
input int      InpMaxTrades = 0;        
input int      InpStopBuffer = 250;     
input int      InpMomPeriod = 14;     

//--- Globals
CTrade trade;
int hFast, hSlow, hIntra, hTrend, hMom, hHTF, hD1;
string botStatus = "Systems Check: Green";
string tradeReason = "Orbiting";
bool signalArmed = false; 
int  armedType = -1; 
datetime lastSLBarTime = 0; // Tracks the bar time when the last SL was hit

int OnInit() {
   hFast  = iMA(_Symbol, PERIOD_M15, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, PERIOD_M15, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hIntra = iMA(_Symbol, PERIOD_M15, InpIntraEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, PERIOD_M15, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hHTF   = iMA(_Symbol, PERIOD_H1, 55, 0, MODE_EMA, PRICE_CLOSE);
   hD1    = iMA(_Symbol, PERIOD_D1, 21, 0, MODE_EMA, PRICE_CLOSE);
   hMom   = iMomentum(_Symbol, PERIOD_M15, InpMomPeriod, PRICE_CLOSE);
   
   if(hFast == INVALID_HANDLE || hTrend == INVALID_HANDLE || hMom == INVALID_HANDLE) return(INIT_FAILED);
   
   Print(InpAssistantName + ": Houston, we are online. " + InpUserTitle + ", all telemetry systems are nominal.");
   return(INIT_SUCCEEDED);
}

//--- Monitor Trade Activity to detect Stop Loss hits
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result) {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      ulong ticket = trans.deal;
      if(HistoryDealSelect(ticket)) {
         long reason = HistoryDealGetInteger(ticket, DEAL_REASON);
         // If deal was caused by Stop Loss
         if(reason == DEAL_REASON_SL) {
            lastSLBarTime = iTime(_Symbol, PERIOD_M15, 0); // Lock in the current candle time
            Print(InpAssistantName + ": Hull breach detected (SL Hit). Activating shields until candle close.");
         }
      }
   }
}

void OnTick() {
   double f[], s[], i[], t[], mom[], htf[], d1[], high[], low[], d1Close[], d1Open[];
   ArraySetAsSeries(f, true); ArraySetAsSeries(s, true);
   ArraySetAsSeries(i, true); ArraySetAsSeries(t, true);
   ArraySetAsSeries(mom, true); ArraySetAsSeries(htf, true); 
   ArraySetAsSeries(d1, true); ArraySetAsSeries(high, true); 
   ArraySetAsSeries(low, true); ArraySetAsSeries(d1Close, true); 
   ArraySetAsSeries(d1Open, true);

   if(CopyBuffer(hFast,0,0,3,f)<3 || CopyBuffer(hTrend,0,0,3,t)<3) return;
   if(CopyBuffer(hSlow,0,0,3,s)<3 || CopyBuffer(hIntra,0,0,3,i)<3 || CopyBuffer(hMom,0,0,3,mom)<3) return;
   if(CopyBuffer(hHTF,0,0,1,htf)<1 || CopyBuffer(hD1,0,0,1,d1)<1) return;
   if(CopyHigh(_Symbol, PERIOD_M15, 0, 5, high)<5 || CopyLow(_Symbol, PERIOD_M15, 0, 5, low)<5) return;
   if(CopyClose(_Symbol, PERIOD_D1, 0, 1, d1Close)<1 || CopyOpen(_Symbol, PERIOD_D1, 0, 1, d1Open)<1) return;

   // COOL-OFF LOGIC: Is current candle the same one where we hit SL?
   bool coolOffActive = (iTime(_Symbol, PERIOD_M15, 0) == lastSLBarTime);

   // NO-GO PROTOCOL: 9 EMA caught between 21 and 200
   bool noGoZone = (f[0] > s[0] && f[0] < t[0]) || (f[0] < s[0] && f[0] > t[0]);
   
   bool momBuyPass  = (mom[0] > 100.0 && mom[0] > mom[1]);
   bool momSellPass = (mom[0] < 100.0 && mom[0] < mom[1]);
   bool bullishTrend = (i[0] > t[0]);
   bool bearishTrend = (i[0] < t[0]);

   string htfStatus = (SymbolInfoDouble(_Symbol, SYMBOL_BID) > htf[0]) ? "ASCENDING" : "DESCENDING";
   string d1Bias = (d1Close[0] > d1Open[0]) ? "BULLISH BIAS" : "BEARISH BIAS";
   string ltfStatus = (i[0] > t[0]) ? "ASCENDING" : "DESCENDING";

   // Entries blocked if in No-Go Zone OR Cool-off is active
   bool originalBuy = (f[0] > i[0] && s[0] > i[0] && bullishTrend && momBuyPass && !noGoZone && !coolOffActive);
   bool originalSell = (f[0] < i[0] && s[0] < i[0] && bearishTrend && momSellPass && !noGoZone && !coolOffActive);

   if(originalBuy) { Execute(ORDER_TYPE_BUY, "Primary Ignition Initiated", high, low); signalArmed = false; }
   else if(originalSell) { Execute(ORDER_TYPE_SELL, "Primary Ignition Initiated", high, low); signalArmed = false; }

   if(GetActiveCount() == 0 && !originalBuy && !originalSell) {
      if(i[0] > t[0] && i[1] <= t[1]) { signalArmed = true; armedType = 0; }
      if(i[0] < t[0] && i[1] >= t[1]) { signalArmed = true; armedType = 1; }

      if(signalArmed) {
         if(coolOffActive) botStatus = "SHIELDS UP: Post-SL Cool-off";
         else if(noGoZone) botStatus = "NO-GO: 9 EMA Sandwich Detected";
         else botStatus = "Scanning for Re-entry Point";

         bool retestTriggered = false;
         if(armedType == 0 && (low[0] <= i[0] || (low[0] <= high[2] && high[2] < low[1]))) retestTriggered = true;
         if(armedType == 1 && (high[0] >= i[0] || (high[0] >= low[2] && low[2] > high[1]))) retestTriggered = true;

         if(retestTriggered && !noGoZone && !coolOffActive) {
            if(armedType == 0 && bullishTrend && momBuyPass) Execute(ORDER_TYPE_BUY, "Confirmed Re-entry", high, low);
            if(armedType == 1 && bearishTrend && momSellPass) Execute(ORDER_TYPE_SELL, "Confirmed Re-entry", high, low);
            if(!momBuyPass && !momSellPass) botStatus = "Awaiting Thrust Vector (Momentum)";
            else signalArmed = false;
         }
      }
   }

   ManageExits((f[0] < i[0] && s[0] < i[0]), (f[0] > i[0] && s[0] > i[0]), noGoZone);
   ManageBreakeven();
   UpdateBriefing(htfStatus, ltfStatus, d1Bias, mom[0], noGoZone, coolOffActive);
}

void Execute(ENUM_ORDER_TYPE type, string reason, double &high[], double &low[]) {
   int limit = (InpMaxTrades == 0) ? 3 : InpMaxTrades;
   if(GetActiveCount() >= limit) return;
   
   double lot = (InpLotSize <= 0) ? NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE)*0.00001, 2) : InpLotSize;
   if(lot < 0.01) lot = 0.01;
   
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl;

   if(type == ORDER_TYPE_BUY) {
      double lowestPoint = MathMin(low[1], MathMin(low[2], low[3]));
      sl = lowestPoint - (InpStopBuffer * _Point);
   } else {
      double highestPoint = MathMax(high[1], MathMax(high[2], high[3]));
      sl = highestPoint + (InpStopBuffer * _Point);
   }

   if(trade.PositionOpen(_Symbol, type, lot, price, sl, 0, "MISSION_CONTROL")) { 
      tradeReason = reason;
   }
}

void ManageExits(bool bullExit, bool bearExit, bool forceExit) {
   for(int k=PositionsTotal()-1; k>=0; k--) {
      ulong ticket = PositionGetTicket(k);
      if(PositionSelectByTicket(ticket) && PositionGetSymbol(k)==_Symbol) {
         if(forceExit) { trade.PositionClose(ticket); tradeReason = "Aborting: No-Go Zone Detected"; continue; }
         long type = PositionGetInteger(POSITION_TYPE);
         if((type==POSITION_TYPE_BUY && bullExit) || (type==POSITION_TYPE_SELL && bearExit)) { 
            trade.PositionClose(ticket); 
            tradeReason = "Mission Objective Met";
         }
      }
   }
}

void ManageBreakeven() {
   for(int k=PositionsTotal()-1; k>=0; k--) {
      ulong ticket = PositionGetTicket(k);
      if(PositionSelectByTicket(ticket) && PositionGetSymbol(k)==_Symbol) {
         double open = PositionGetDouble(POSITION_PRICE_OPEN), cur = PositionGetDouble(POSITION_PRICE_CURRENT), sl = PositionGetDouble(POSITION_SL);
         if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY && cur-open > 350*_Point && sl < open) trade.PositionModify(ticket, open + 20*_Point, 0);
         if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL && open-cur > 350*_Point && (sl > open || sl==0)) trade.PositionModify(ticket, open - 20*_Point, 0);
      }
   }
}

int GetActiveCount() {
   int count = 0;
   for(int k=0; k<PositionsTotal(); k++) if(PositionGetSymbol(k)==_Symbol) count++;
   return count;
}

string GetTimer(ENUM_TIMEFRAMES period) {
   datetime left = (datetime)SeriesInfoInteger(_Symbol, period, SERIES_LASTBAR_DATE) + PeriodSeconds(period) - TimeCurrent();
   return StringFormat("%02d:%02d", (int)(left/60), (int)(left%60));
}

void UpdateBriefing(string htf, string ltf, string d1b, double mom, bool nGo, bool cOff) {
   string psyche = (GetActiveCount() > 0) ? "Maintain cabin pressure, "+InpUserTitle+"." : "Scanning the void.";
   
   string out = "KIT-ARA ROCKET PROJ BOT\n" +
                "MISSION_STATEMENT: CHIPS AND FISH\n" +
                "========================\n" +
                "HTF TREND STATUS: " + htf + "\n" +
                "LTF TREND STATUS: " + ltf + "\n" +
                "========================\n" +
                "D1 BIAS: " + d1b + "\n" +
                "D1 CANDLE TIMER: T-minus " + GetTimer(PERIOD_D1) + "\n" +
                "M15 CANDLE TIMER: T-minus " + GetTimer(PERIOD_M15) + "\n" +
                "========================\n" +
                "MOMENTUM STATUS: " + (mom > 100 ? "POSITIVE THRUST" : "NEGATIVE THRUST") + "\n" +
                "========================\n" +
                "SYSTEM LOGS: " + botStatus + "\n" +
                "REASON: " + tradeReason + "\n" +
                "--------------------------------------------------\n" +
                "ALGO ADVISORY: " + (nGo || cOff ? "STAY ON PAD - NO GO" : "GO FOR LAUNCH") + "\n" +
                "NO-GO STATUS: " + (nGo ? "ACTIVE" : "CLEAR") + "\n" +
                "COOL-OFF STATUS: " + (cOff ? "SHIELDS UP" : "OFFLINE") + "\n" +
                "CONTROL NOTE: " + psyche + "\n" +
                "--------------------------------------------------\n" +
                "PREVIOUS INFO: [2026-01-10] HUD Persistence Enabled";
   Comment(out);
}