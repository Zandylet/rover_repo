//+------------------------------------------------------------------+
//|                                                      CHIPS.mq5   |
//|                                   Your Virtual Trading Assistant |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.67"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs
input int      InpFastEMA   = 9;      
input int      InpSlowEMA   = 21;     
input int      InpIntraEMA  = 55;     
input int      InpTrendEMA  = 200;    
input double   InpLotSize   = 0.00;   
input int      InpMaxTrades = 0;       
input int      InpStopLoss  = 650;     
input int      InpTrendGap  = 50;     
input int      InpADXPeriod = 14;     
input int      InpMinADX    = 22;     
input int      InpMomPeriod = 14;     // Momentum Period

//--- Globals
CTrade trade;
int hFast, hSlow, hIntra, hTrend, hADX, hMom;
string botStatus = "Initializing...";
string tradeReason = "None";
int tradesTaken = 0;
bool rangeFilterActive = false; 

//--- Retest Logic Globals
bool signalArmed = false; 
int  armedType = -1; // 0 for Buy, 1 for Sell

int OnInit() {
   hFast  = iMA(_Symbol, PERIOD_M15, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlow  = iMA(_Symbol, PERIOD_M15, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hIntra = iMA(_Symbol, PERIOD_M15, InpIntraEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrend = iMA(_Symbol, PERIOD_M15, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
   hADX   = iADX(_Symbol, PERIOD_M15, InpADXPeriod);
   hMom   = iMomentum(_Symbol, PERIOD_M15, InpMomPeriod, PRICE_CLOSE);
   
   if(hFast == INVALID_HANDLE || hTrend == INVALID_HANDLE || hMom == INVALID_HANDLE) return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

void OnTick() {
   double f[], s[], i[], t[], adx[], mom[], high[], low[];
   ArraySetAsSeries(f, true); ArraySetAsSeries(s, true);
   ArraySetAsSeries(i, true); ArraySetAsSeries(t, true);
   ArraySetAsSeries(adx, true); ArraySetAsSeries(mom, true);
   ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);

   //--- Data Validation
   if(CopyBuffer(hFast,0,0,3,f)<3 || CopyBuffer(hTrend,0,0,3,t)<3 || CopyBuffer(hADX,0,0,1,adx)<1) return;
   if(CopyBuffer(hSlow,0,0,3,s)<3 || CopyBuffer(hIntra,0,0,3,i)<3 || CopyBuffer(hMom,0,0,3,mom)<3) return;
   if(CopyHigh(_Symbol, PERIOD_M15, 0, 5, high)<5 || CopyLow(_Symbol, PERIOD_M15, 0, 5, low)<5) return;

   int activeTrades = GetActiveCount();
   double currentGap = MathAbs(i[0] - t[0]) / _Point;
   bool trendStrengthPass = adx[0] >= InpMinADX;
   bool gapPass = currentGap >= InpTrendGap;
   
   //--- Momentum Logic: Above 100 for Buy, Below 100 for Sell
   bool momBuyPass  = (mom[0] > 100.0 && mom[0] > mom[1]);
   bool momSellPass = (mom[0] < 100.0 && mom[0] < mom[1]);
   
   //--- Range Exclusion Logic
   bool bullTrap = (f[0] > t[0] && s[0] > t[0]) && (f[0] < i[0] && s[0] < i[0]);
   bool bearTrap = (f[0] < t[0] && s[0] < t[0]) && (f[0] > i[0] && s[0] > i[0]);
   rangeFilterActive = (bullTrap || bearTrap);

   //--- MANDATORY EXIT: 9 is between 21 and 55
   bool betweenZone = (f[0] > s[0] && f[0] < i[0]) || (f[0] < s[0] && f[0] > i[0]);

   bool bullishTrend = (i[0] > t[0]) && gapPass && trendStrengthPass && !rangeFilterActive;
   bool bearishTrend = (i[0] < t[0]) && gapPass && trendStrengthPass && !rangeFilterActive;

   //--- [PRIORITY 1] ORIGINAL ENTRY LOGIC (With Momentum Filter)
   bool originalBuy = (f[0] > i[0] && s[0] > i[0] && bullishTrend && momBuyPass);
   bool originalSell = (f[0] < i[0] && s[0] < i[0] && bearishTrend && momSellPass);

   if(originalBuy) {
      Execute(ORDER_TYPE_BUY, "Original Logic + Momentum");
      signalArmed = false; 
   }
   else if(originalSell) {
      Execute(ORDER_TYPE_SELL, "Original Logic + Momentum");
      signalArmed = false;
   }

   //--- [PRIORITY 2] RETEST ENTRY LOGIC
   if(activeTrades == 0 && !originalBuy && !originalSell) {
      if(i[0] > t[0] && i[1] <= t[1]) { signalArmed = true; armedType = 0; }
      if(i[0] < t[0] && i[1] >= t[1]) { signalArmed = true; armedType = 1; }

      if(signalArmed) {
         botStatus = rangeFilterActive ? "FILTERED: Inside 55/200 Range" : "WAITING: M15 Retest...";
         bool retestTriggered = false;
         if(armedType == 0 && (low[0] <= i[0] || (low[0] <= high[2] && high[2] < low[1]))) retestTriggered = true;
         if(armedType == 1 && (high[0] >= i[0] || (high[0] >= low[2] && low[2] > high[1]))) retestTriggered = true;

         if(retestTriggered && !rangeFilterActive) {
            if(armedType == 0 && bullishTrend && momBuyPass) Execute(ORDER_TYPE_BUY, "Retest + Momentum");
            if(armedType == 1 && bearishTrend && momSellPass) Execute(ORDER_TYPE_SELL, "Retest + Momentum");
            if(!momBuyPass && !momSellPass) botStatus = "Retest OK - Waiting for Momentum...";
            else signalArmed = false;
         }
      }
   }

   ManageExits((f[0] < i[0] && s[0] < i[0]), (f[0] > i[0] && s[0] > i[0]), betweenZone);
   ManageBreakeven();
   UpdateHUD(currentGap, adx[0], trendStrengthPass, mom[0]);
}

void Execute(ENUM_ORDER_TYPE type, string reason) {
   int limit = (InpMaxTrades == 0) ? 3 : InpMaxTrades;
   if(GetActiveCount() >= limit) return;
   double lot = (InpLotSize <= 0) ? NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE)*0.00001, 2) : InpLotSize;
   if(lot < 0.01) lot = 0.01;
   double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = (type == ORDER_TYPE_BUY) ? price - InpStopLoss*_Point : price + InpStopLoss*_Point;
   if(trade.PositionOpen(_Symbol, type, lot, price, sl, 0, "CHIPS v1.67")) {
      tradesTaken++; tradeReason = reason;
   }
}

void ManageExits(bool bullExit, bool bearExit, bool forceExit) {
   for(int k=PositionsTotal()-1; k>=0; k--) {
      ulong ticket = PositionGetTicket(k);
      if(PositionSelectByTicket(ticket) && PositionGetSymbol(k)==_Symbol) {
         if(forceExit) {
            trade.PositionClose(ticket);
            tradeReason = "Exit: EMA 9 Between 21/55";
            continue;
         }
         long type = PositionGetInteger(POSITION_TYPE);
         if((type==POSITION_TYPE_BUY && bullExit) || (type==POSITION_TYPE_SELL && bearExit)) {
            trade.PositionClose(ticket);
            tradeReason = "Exit: MA Crossover";
         }
      }
   }
}

void ManageBreakeven() {
   for(int k=PositionsTotal()-1; k>=0; k--) {
      ulong ticket = PositionGetTicket(k);
      if(PositionSelectByTicket(ticket) && PositionGetSymbol(k)==_Symbol) {
         double open = PositionGetDouble(POSITION_PRICE_OPEN), cur = PositionGetDouble(POSITION_PRICE_CURRENT), sl = PositionGetDouble(POSITION_SL);
         if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY && cur-open > 250*_Point && sl < open) trade.PositionModify(ticket, open + 20*_Point, 0);
         if(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL && open-cur > 250*_Point && (sl > open || sl==0)) trade.PositionModify(ticket, open - 20*_Point, 0);
      }
   }
}

int GetActiveCount() {
   int count = 0;
   for(int k=0; k<PositionsTotal(); k++) if(PositionGetSymbol(k)==_Symbol) count++;
   return count;
}

void UpdateHUD(double gap, double adxVal, bool adxPass, double momVal) {
   string marketState = (adxVal < 20) ? "CONSOLIDATION" : (adxVal > 25 ? "TRENDING" : "TRANSITIONING");
   string momStatus = (momVal > 100) ? "BULLISH (" + DoubleToString(momVal, 2) + ")" : "BEARISH (" + DoubleToString(momVal, 2) + ")";
   
   string out = "BOT NAME: CHIPS v1.67 (M15)\n" +
                "MARKET STATE: " + marketState + "\n" +
                "MOMENTUM: " + momStatus + "\n" +
                "ADX: " + DoubleToString(adxVal, 1) + " | GAP: " + DoubleToString(gap, 1) + "\n" +
                "RANGE FILTER: " + (rangeFilterActive ? "LOCKED" : "Clear") + "\n" + 
                "REASON: " + tradeReason + "\n" +
                "STATUS: " + botStatus + "\n" +
                "--------------------------------------------------\n" +
                "PREVIOUS INFO: [2026-01-10] HUD Persistence Enabled";
   Comment(out);
}