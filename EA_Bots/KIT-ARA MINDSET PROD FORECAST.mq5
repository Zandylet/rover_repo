//+------------------------------------------------------------------+
//|                                                  KIT-ARA_v3.01.mq5 |
//|   CHIPS AND FISH - FULL TRADING TERMINAL + VISUAL SIGNALS v3.01  |
//|         DYNAMIC LOTS + PROBABILITY FILTER + ORIGINAL HUD         |
//+------------------------------------------------------------------+
#property copyright "KIT-ARA"
#property version   "3.01"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade trade;
CPositionInfo posInfo;

//--- TELEGRAM INPUTS
input string   InpTelegramToken = "8450254645:AAF7Q96gfqjXZlK93Jf6alij92zEXE93Pos"; 
input string   InpTelegramID    = "1670920528";    
input bool     InpNotifications = true;             

//--- RISK & FILTER INPUTS
input double RiskPercent        = 0.5;   
input double ManualLotSize      = 0.0;   
input int    MinProbability     = 60;    
input double MaxSpread          = 3.0;   
input int    MaxTrades          = 3;

//--- INDICATOR INPUTS
input int ATRPeriod = 14;
input double ATR_SL_Mult = 2.0;
input int FastEMA = 9, SlowEMA = 21, IntraEMA = 55, TrendEMA = 200;
input int ADXPeriod = 14, MinADX = 22, MomPeriod = 14;

//--- GLOBALS
int hFast, hSlow, hIntra, hTrend, hADX, hMom, hATR, hHTF, hD1;
string tradeReason = "SYSTEM IDLE";
int currentProbPercent = 0; 
bool BotActive = true; 
bool ManualPause = false;

//--- EQUITY & TIME GLOBALS
string lastSession = "";
double initialEquity = 0;
double equityTarget = 0;
double equityStopLoss = 0; 

//--- HUD SETTINGS (Original Layout)
#define HUD_X 20
#define HUD_Y 30
#define LINE_SPACING 20

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
   hADX   = iADX(_Symbol, PERIOD_M15, ADXPeriod);
   hMom   = iMomentum(_Symbol, PERIOD_M15, MomPeriod, PRICE_CLOSE);
   hATR   = iATR(_Symbol, PERIOD_M15, ATRPeriod);

   if(hFast==INVALID_HANDLE || hADX==INVALID_HANDLE) return INIT_FAILED;

   trade.SetExpertMagicNumber(123456);
   initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   equityTarget = initialEquity * 2;
   equityStopLoss = initialEquity * 0.8; 
   
   Notify("KIT-ARA v3.01: Original HUD Restored. Probability Filter Active.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { ObjectsDeleteAll(0, "HUD_"); }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   double f[], s[], i[], t[], adx[], mom[], atr[], htf[], d1[];
   ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(i,true);
   ArraySetAsSeries(t,true); ArraySetAsSeries(adx,true); ArraySetAsSeries(mom,true);
   ArraySetAsSeries(atr,true); ArraySetAsSeries(htf,true); ArraySetAsSeries(d1,true);

   if(CopyBuffer(hFast,0,0,2,f)<2 || CopyBuffer(hSlow,0,0,2,s)<2 || CopyBuffer(hIntra,0,0,2,i)<2 ||
      CopyBuffer(hTrend,0,0,2,t)<2 || CopyBuffer(hADX,0,0,1,adx)<1 || CopyBuffer(hMom,0,0,2,mom)<2 ||
      CopyBuffer(hATR,0,0,1,atr)<1 || CopyBuffer(hHTF,0,0,1,htf)<1 || CopyBuffer(hD1,0,0,1,d1)<1) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (ask - bid) / _Point;

   CheckEquityProtection();
   
   // Update probability for internal logic
   CalculateInternalProbability(adx[0], mom[0], bid, d1[0], htf[0], i[0]);

   if(!ManualPause && adx[0] >= 20) {
      bool bullishD1 = bid > d1[0];
      bool bull = i[0] > t[0] && adx[0] >= MinADX && bullishD1;
      bool bear = i[0] < t[0] && adx[0] >= MinADX && !bullishD1;

      bool buySig  = f[0] > i[0] && s[0] > i[0] && bull && mom[0] > 100;
      bool sellSig = f[0] < i[0] && s[0] < i[0] && bear && mom[0] < 100;

      if(GetActiveCount() < MaxTrades && spread <= MaxSpread) {
         if((buySig || sellSig) && currentProbPercent >= MinProbability) {
            tradeReason = buySig ? "BREAKOUT BUY" : "BREAKOUT SELL";
            double lot = CalculateLotSize(currentProbPercent >= 90 ? RiskPercent * 2 : RiskPercent);
            
            if(ExecuteTrade(buySig ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lot))
               Notify("🔥 TRADE: " + tradeReason + " (" + IntegerToString(currentProbPercent) + "% Prob)\nLot: " + DoubleToString(lot,2));
         } else if((buySig || sellSig) && currentProbPercent < MinProbability) {
            tradeReason = "LOW PROB (" + IntegerToString(currentProbPercent) + "%)";
         }
      } else if (spread > MaxSpread) tradeReason = "SPREAD TOO HIGH";
   } else tradeReason = ManualPause ? "USER PAUSED" : "CONSOLIDATING";

   DrawTerminalHUD(adx[0], spread, atr[0], d1[0], htf[0]);
}

//+------------------------------------------------------------------+
//| PROBABILITY CALCULATION (INTERNAL)                               |
//+------------------------------------------------------------------+
void CalculateInternalProbability(double adx, double mom, double bid, double d1, double htf, double ltf) {
    int score = 0;
    bool bullAlign = (bid > d1 && bid > htf && bid > ltf);
    bool bearAlign = (bid < d1 && bid < htf && bid < ltf);
    if(bullAlign || bearAlign) {
        score += 40;
        if(adx > 25) score += 20;
        if(adx > 40) score += 20;
        if((bullAlign && mom > 100) || (bearAlign && mom < 100)) score += 20;
    }
    currentProbPercent = score;
}

//+------------------------------------------------------------------+
//| RISK MANAGEMENT                                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double risk) {
   if(ManualLotSize > 0) return ManualLotSize;
   double margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lot = NormalizeDouble((margin * (risk/100)) / 1000, 2); 
   return (lot < minLot) ? minLot : MathFloor(lot/lotStep)*lotStep;
}

//+------------------------------------------------------------------+
//| ORIGINAL HUD RENDERER                                            |
//+------------------------------------------------------------------+
void DrawTerminalHUD(double adx_val, double spread, double atr_val, double d1, double htf) {
   MqlDateTime dt; TimeCurrent(dt);
   int h1_rem = 60 - dt.min;
   int m15_rem = 15 - (dt.min % 15);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   color htfCol = (bid > htf) ? clrLime : clrRed;
   color spreadCol = (spread > MaxSpread) ? clrRed : clrWhite;

   // ALL ORIGINAL INFORMATION KEPT
   UpdateLabel("HUD_NAME", "SYSTEM_NAME: KIT-ARA | " + _Symbol, HUD_X, HUD_Y, clrWhite);
   UpdateLabel("HUD_HTF", "HTF TREND STATUS: " + ((bid > htf) ? "BULL" : "BEAR"), HUD_X, HUD_Y + LINE_SPACING, htfCol);
   UpdateLabel("HUD_LTF", "LTF TREND STATUS: " + ((currentProbPercent >= 60) ? "STRONG" : "WEAK"), HUD_X, HUD_Y + (LINE_SPACING*2), clrWhite);
   UpdateLabel("HUD_BIAS", "DAILY BIAS: " + ((bid > d1) ? "BULLISH" : "BEARISH"), HUD_X, HUD_Y + (LINE_SPACING*3), clrGold);
   UpdateLabel("HUD_H1", "H1 CANDLE TIMER: " + IntegerToString(h1_rem) + " MINS", HUD_X, HUD_Y + (LINE_SPACING*4), clrAqua);
   UpdateLabel("HUD_M15", "M15 CANDLE TIMER: " + IntegerToString(m15_rem) + " MINS", HUD_X, HUD_Y + (LINE_SPACING*5), clrAqua);
   UpdateLabel("HUD_SPREAD", "CURRENT SPREAD: " + DoubleToString(spread, 1), HUD_X, HUD_Y + (LINE_SPACING*6), spreadCol);
   UpdateLabel("HUD_REASON", "REASON: " + tradeReason, HUD_X, HUD_Y + (LINE_SPACING*7), clrYellow);
   UpdateLabel("HUD_TARGET", "NEXT EQUITY GOAL: " + DoubleToString(equityTarget, 2), HUD_X, HUD_Y + (LINE_SPACING*8), clrLime);
   UpdateLabel("HUD_PSYCH", "TRUST THE SYSTEM. (Prob: " + IntegerToString(currentProbPercent) + "%)", HUD_X, HUD_Y + (LINE_SPACING*9), clrLightGray);

   // Original Buttons
   CreateButton("HUD_BTN_CLOSE", "CLOSE ALL", HUD_X, HUD_Y + (LINE_SPACING*11), clrRed);
   CreateButton("HUD_BTN_PAUSE", ManualPause ? "RESUME BOT" : "PAUSE BOT", HUD_X + 125, HUD_Y + (LINE_SPACING*11), ManualPause ? clrLime : clrCrimson);
}

//+------------------------------------------------------------------+
//| CORE HELPERS                                                     |
//+------------------------------------------------------------------+
void UpdateLabel(string name, string text, int x, int y, color col) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, name, OBJPROP_FONT, "Verdana");
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
}

void CreateButton(string name, string text, int x, int y, color bg) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, 120);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 25);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlack);
}

bool ExecuteTrade(ENUM_ORDER_TYPE type, double lot) {
   if(type == ORDER_TYPE_BUY) return trade.Buy(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), 0, 0);
   if(type == ORDER_TYPE_SELL) return trade.Sell(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), 0, 0);
   return false;
}

int GetActiveCount() {
   int c=0; for(int i=PositionsTotal()-1; i>=0; i--) if(posInfo.SelectByIndex(i) && posInfo.Magic()==123456) c++;
   return c;
}

void CheckEquityProtection() {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq >= equityTarget) { equityStopLoss = eq*0.95; equityTarget = eq*2; Notify("Goal Reached!"); }
   if(eq <= equityStopLoss && equityStopLoss > 0) {
      for(int i=PositionsTotal()-1; i>=0; i--) if(posInfo.SelectByIndex(i)) trade.PositionClose(posInfo.Ticket());
      ManualPause = true;
   }
}

void Notify(string msg) { if(InpNotifications) { SendNotification(msg); SendTelegram(msg); } }
void SendTelegram(string m) {
   string url = "https://api.telegram.org/bot"+InpTelegramToken+"/sendMessage";
   string p = "chat_id="+InpTelegramID+"&text="+m;
   char d[], r[]; string h; StringToCharArray(p, d); WebRequest("POST", url, h, 10, d, r, h);
}

void OnChartEvent(const int id, const long &l, const double &d, const string &s) {
   if(id == CHARTEVENT_OBJECT_CLICK) {
      if(s == "HUD_BTN_CLOSE") { for(int i=PositionsTotal()-1; i>=0; i--) if(posInfo.SelectByIndex(i)) trade.PositionClose(posInfo.Ticket()); }
      if(s == "HUD_BTN_PAUSE") ManualPause = !ManualPause;
   }
}