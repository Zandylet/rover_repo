//+------------------------------------------------------------------+
//|                                     EMA_Donchian_Ultra_Pro.mq5   |
//|                                  Copyright 2026, Gemini AI Labs |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Gemini"
#property version   "5.00"
#property strict

#include <Trade\Trade.mqh>

// --- INPUTS ---
input group "--- Strategy Settings ---"
input int      FastEMALen    = 20;     
input int      SlowEMALen    = 50;     
input int      RSILen        = 14;     
input int      WPRLen        = 14;     
input int      DonchianLen   = 20;     

input group "--- Risk Management ---"
input double   LotSize       = 0.01;   
input int      MaxTrades     = 3;      
input int      MagicNum      = 123456; 

input group "--- Telegram Notifications ---"
input bool     UseTelegram   = false;  
input string   TG_Token      = "YOUR_TOKEN"; 
input string   TG_ChatID     = "YOUR_ID";   

// --- Global Variables ---
int hFast5, hSlow5, hRSI5, hWPR5, hFast1, hSlow1;
string botLog = "System Ready";
CTrade trade;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   hFast5 = iMA(_Symbol, PERIOD_M5, FastEMALen, 0, MODE_EMA, PRICE_CLOSE);
   hSlow5 = iMA(_Symbol, PERIOD_M5, SlowEMALen, 0, MODE_EMA, PRICE_CLOSE);
   hRSI5  = iRSI(_Symbol, PERIOD_M5, RSILen, PRICE_CLOSE);
   hWPR5  = iWPR(_Symbol, PERIOD_M5, WPRLen);
   hFast1 = iMA(_Symbol, PERIOD_H1, FastEMALen, 0, MODE_EMA, PRICE_CLOSE);
   hSlow1 = iMA(_Symbol, PERIOD_H1, SlowEMALen, 0, MODE_EMA, PRICE_CLOSE);
   
   trade.SetExpertMagicNumber(MagicNum);
   
   // Create UI Dashboard
   CreateLabel("HUD_BG", 10, 30, 240, 190, clrBlack);
   CreateButton("HUD_BTN_CLOSE", 25, 185, 210, 25, "EMERGENCY CLOSE ALL", clrWhite, clrMaroon);
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { 
   ObjectsDeleteAll(0, "HUD_"); 
   Comment("");
}

//+------------------------------------------------------------------+
//| Main Processing                                                  |
//+------------------------------------------------------------------+
void OnTick() {
   ManageTrailingStop();
   
   static datetime last_time = 0;
   datetime current_time = iTime(_Symbol, PERIOD_M5, 0);
   
   // Check for Entries on M5 candle close/open
   if(last_time != current_time) {
      CheckForEntries();
      last_time = current_time;
   }
   
   // Update HUD every tick (for the timers)
   UpdateHUD();
}

//+------------------------------------------------------------------+
//| Strategy Execution Logic                                         |
//+------------------------------------------------------------------+
void CheckForEntries() {
   double f5[], s5[], r5[], w5[], f1[], s1[];
   ArraySetAsSeries(f5, true); ArraySetAsSeries(s5, true);
   ArraySetAsSeries(r5, true); ArraySetAsSeries(w5, true);
   ArraySetAsSeries(f1, true); ArraySetAsSeries(s1, true);

   if(CopyBuffer(hFast5,0,0,2,f5)<2 || CopyBuffer(hSlow5,0,0,2,s5)<2) return;
   if(CopyBuffer(hRSI5,0,0,1,r5)<1 || CopyBuffer(hWPR5,0,0,1,w5)<1) return;
   if(CopyBuffer(hFast1,0,0,1,f1)<1 || CopyBuffer(hSlow1,0,0,1,s1)<1) return;

   bool h1Up = (f1[0] > s1[0]);
   bool m5Up = (f5[0] > s5[0]);
   
   if(CountPositions() >= MaxTrades) { botLog = "Max trades active"; return; }
   if(h1Up != m5Up) { botLog = "TF Mismatch"; return; }

   // Buy Logic
   if(h1Up && (w5[0] >= -100 && w5[0] <= -50) && r5[0] > 50) {
      double sl = iLow(_Symbol, PERIOD_M5, iLowest(_Symbol, PERIOD_M5, MODE_LOW, DonchianLen, 1));
      if(trade.Buy(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), sl, 0)) {
         SendTelegram("🟢 BUY ORDER: " + _Symbol); botLog = "Long Opened";
      }
   }
   
   // Sell Logic
   if(!h1Up && (w5[0] <= 0 && w5[0] >= -50) && r5[0] < 50) {
      double sl = iHigh(_Symbol, PERIOD_M5, iHighest(_Symbol, PERIOD_M5, MODE_HIGH, DonchianLen, 1));
      if(trade.Sell(LotSize, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), sl, 0)) {
         SendTelegram("🔴 SELL ORDER: " + _Symbol); botLog = "Short Opened";
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop (Donchian)                                         |
//+------------------------------------------------------------------+
void ManageTrailingStop() {
   for(int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == MagicNum) {
         double currentSL = PositionGetDouble(POSITION_SL);
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            double trail = iLow(_Symbol, PERIOD_M5, iLowest(_Symbol, PERIOD_M5, MODE_LOW, DonchianLen, 1));
            if(trail > currentSL) {
               trade.PositionModify(ticket, trail, 0);
               SendTelegram("🛡️ Trail SL Up: " + DoubleToString(trail, _Digits));
            }
         } else {
            double trail = iHigh(_Symbol, PERIOD_M5, iHighest(_Symbol, PERIOD_M5, MODE_HIGH, DonchianLen, 1));
            if(trail < currentSL || currentSL == 0) {
               trade.PositionModify(ticket, trail, 0);
               SendTelegram("🛡️ Trail SL Down: " + DoubleToString(trail, _Digits));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dashboard (HUD) & Timers                                         |
//+------------------------------------------------------------------+
void UpdateHUD() {
   double f1[], s1[], f5[], s5[];
   CopyBuffer(hFast1,0,0,1,f1); CopyBuffer(hSlow1,0,0,1,s1);
   CopyBuffer(hFast5,0,0,1,f5); CopyBuffer(hSlow5,0,0,1,s5);

   bool h1U = (f1[0] > s1[0]); bool m5U = (f5[0] > s5[0]);

   UpdateLabel("HUD_H1", "1H Trend: " + (h1U?"BULLISH":"BEARISH") + " ["+GetTimer(PERIOD_H1)+"]", 20, 50, (h1U?clrLime:clrRed));
   UpdateLabel("HUD_M5", "5M Trend: " + (m5U?"BULLISH":"BEARISH") + " ["+GetTimer(PERIOD_M5)+"]", 20, 75, (m5U?clrLime:clrRed));
   UpdateLabel("HUD_AL", "Align Status: " + ((h1U==m5U)?"ALIGNED":"WAITING"), 20, 100, ((h1U==m5U)?clrAqua:clrYellow));
   UpdateLabel("HUD_TR", "Trades: " + (string)CountPositions() + "/" + (string)MaxTrades, 20, 125, clrWhite);
   UpdateLabel("HUD_LG", "Bot Log: " + botLog, 20, 155, clrLightGray, 8);
}

string GetTimer(ENUM_TIMEFRAMES p) {
   datetime next = iTime(_Symbol, p, 0) + PeriodSeconds(p);
   long d = (long)next - (long)TimeCurrent();
   if(d < 0) d = 0;
   return StringFormat("%02d:%02d", d/60, d%60);
}

// --- UI HELPER FUNCTIONS ---
void CreateLabel(string name, int x, int y, int w, int h, color bg) {
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void UpdateLabel(string name, string text, int x, int y, color col, int size=10) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void CreateButton(string name, int x, int y, int w, int h, string text, color txtCol, color bgCol) {
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtCol);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgCol);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "HUD_BTN_CLOSE") {
      for(int i=PositionsTotal()-1; i>=0; i--) {
         ulong t = PositionGetTicket(i);
         if(PositionSelectByTicket(t) && PositionGetInteger(POSITION_MAGIC) == MagicNum) {
            trade.PositionClose(t);
            SendTelegram("🛑 EMERGENCY: All positions closed for " + _Symbol);
         }
      }
      ObjectSetInteger(0, "HUD_BTN_CLOSE", OBJPROP_STATE, false);
      botLog = "Manual Flush Done";
   }
}

int CountPositions() {
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--) {
      if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == MagicNum) count++;
   }
   return count;
}

void SendTelegram(string message) {
   if(!UseTelegram) return;
   string url = "https://api.telegram.org/bot" + TG_Token + "/sendMessage?chat_id=" + TG_ChatID + "&text=" + message;
   char data[], result[]; string headers;
   WebRequest("GET", url, headers, 1000, data, result, headers);
}