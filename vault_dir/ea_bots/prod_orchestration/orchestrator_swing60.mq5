//+------------------------------------------------------------------+
//|                                     Orchestrator_Swing60.mq5     |
//|                                  Copyright 2026, Gemini AI       |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

//--- Unique Magic for Swing60
#define MAGIC_ORCH_SWING 1103

//--- Garuda Palette
#define G_CYAN    C'0, 255, 255' 
#define G_PINK    C'255, 0, 127' 
#define G_PURP    C'187, 154, 247'
#define G_WHITE   C'248, 248, 242'

//--- Inputs
input double   InpLotSize        = 0.10;      // Standard Swing Lot
input int      InpMaxConcurrent  = 2;         // Fewer, higher-quality trades
input double   InpExplosiveFactor = 1.5;      // High barrier for H1 entries

//--- Global Handles
int hFast, hSlow, hTrend, hATR;
CTrade trade;
string hud_names[16]; 

//+------------------------------------------------------------------+
//| HUD Interface                                                    |
//+------------------------------------------------------------------+
void RenderHUD(int index, string key, string value, color clr) {
    string alignedText = StringFormat("%-18s: %-12s", key, value);
    ObjectSetString(0, hud_names[index], OBJPROP_TEXT, alignedText);
    ObjectSetInteger(0, hud_names[index], OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Orchestration: Wide Swing Guard                                  |
//+------------------------------------------------------------------+
void OrchestrateProtection(double atr) {
    double reachBE = 2.5 * atr; // BE after a significant H1 trend move
    double trail   = 4.0 * atr; // Very wide trail to survive pullbacks

    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) != MAGIC_ORCH_SWING) continue;
            
            ulong  t   = PositionGetTicket(i);
            double ent = PositionGetDouble(POSITION_PRICE_OPEN);
            double cur = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl  = PositionGetDouble(POSITION_SL);
            long   typ = PositionGetInteger(POSITION_TYPE);

            // 1. Swing Break-Even
            if(sl != ent) {
                bool hitTarget = (typ == POSITION_TYPE_BUY) ? (cur > ent + reachBE) : (cur < ent - reachBE);
                if(hitTarget) trade.PositionModify(t, ent, 0); 
            }

            // 2. Slow-Burn Trailing Stop
            if(typ == POSITION_TYPE_BUY && cur > ent + (trail * 1.2)) {
                double nSL = NormalizeDouble(cur - trail, _Digits);
                if(nSL > sl + (10 * _Point)) trade.PositionModify(t, nSL, 0);
            }
            if(typ == POSITION_TYPE_SELL && cur < ent - (trail * 1.2)) {
                double nSL = NormalizeDouble(cur + trail, _Digits);
                if(sl == 0 || nSL < sl - (10 * _Point)) trade.PositionModify(t, nSL, 0);
            }
        }
    }
}

int OnInit() {
    trade.SetExpertMagicNumber(MAGIC_ORCH_SWING);
    for(int i=0; i<16; i++) {
        hud_names[i] = "ORCH_SWING_" + (string)i;
        ObjectCreate(0, hud_names[i], OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, hud_names[i], OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, hud_names[i], OBJPROP_XDISTANCE, 40);
        ObjectSetInteger(0, hud_names[i], OBJPROP_YDISTANCE, 50 + (i * 18));
        ObjectSetInteger(0, hud_names[i], OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, hud_names[i], OBJPROP_FONT, "Consolas");
    }
    // Hardcoded for H1
    hFast  = iMA(_Symbol, PERIOD_H1, 9, 0, MODE_EMA, PRICE_CLOSE);
    hSlow  = iMA(_Symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
    hTrend = iMA(_Symbol, PERIOD_H1, 200, 0, MODE_EMA, PRICE_CLOSE);
    hATR   = iATR(_Symbol, PERIOD_H1, 14);
    return(INIT_SUCCEEDED);
}

void OnTick() {
    double f[], s[], atr[];
    ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(atr,true);
    MqlRates r[]; ArraySetAsSeries(r,true);
    if(CopyBuffer(hFast,0,0,1,f)<1 || CopyBuffer(hSlow,0,0,1,s)<1 || 
       CopyBuffer(hATR,0,0,1,atr)<1 || CopyRates(_Symbol, PERIOD_H1, 0, 5, r)<5) return;

    OrchestrateProtection(atr[0]);
    
    bool isBull = f[0] > s[0];
    bool isExplosive = (MathAbs(r[0].close - r[0].open) >= (atr[0] * InpExplosiveFactor));
    
    // Swing Entry Logic
    if(PositionsTotal() < InpMaxConcurrent && isExplosive) {
        if(isBull) trade.Buy(InpLotSize, _Symbol, r[0].close, r[0].close - (atr[0]*6.0), 0);
        else trade.Sell(InpLotSize, _Symbol, r[0].close, r[0].close + (atr[0]*6.0), 0);
    }

    // HUD Update
    RenderHUD(0, "Orchestrator",   "SWING TRADING", G_PURP);
    RenderHUD(1, "Target TF",      "H1 (Hourly)", G_CYAN);
    RenderHUD(2, "Bias",           (isBull?"BULLISH TREND":"BEARISH TREND"), G_WHITE);
    RenderHUD(3, "Swing ATR",      DoubleToString(atr[0], _Digits), G_CYAN);
    RenderHUD(4, "Position Limit", (string)InpMaxConcurrent, G_WHITE);
}

void OnDeinit(const int r) { for(int i=0; i<16; i++) ObjectDelete(0, hud_names[i]); }