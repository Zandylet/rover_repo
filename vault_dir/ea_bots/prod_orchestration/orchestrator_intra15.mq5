//+------------------------------------------------------------------+
//|                                     Orchestrator_Intra15.mq5     |
//|                                  Copyright 2026, Gemini AI       |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

//--- Unique Magic for Intra15
#define MAGIC_ORCH_INTRA 1102

//--- Garuda Palette
#define G_CYAN    C'0, 255, 255' 
#define G_PINK    C'255, 0, 127' 
#define G_PURP    C'187, 154, 247'
#define G_WHITE   C'248, 248, 242'

//--- Inputs
input double   InpLotSize        = 0.05;      // Higher default for Intra
input int      InpMaxConcurrent  = 3;         
input double   InpExplosiveFactor = 1.3;      // Filter for M15 structure

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
//| Orchestration: Balanced Intra Guard                              |
//+------------------------------------------------------------------+
void OrchestrateProtection(double atr) {
    double reachBE = 1.5 * atr; // Move to BE after substantial move
    double trail   = 2.5 * atr; // Wider trail for M15 volatility

    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) != MAGIC_ORCH_INTRA) continue;
            
            ulong  t   = PositionGetTicket(i);
            double ent = PositionGetDouble(POSITION_PRICE_OPEN);
            double cur = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl  = PositionGetDouble(POSITION_SL);
            double vol = PositionGetDouble(POSITION_VOLUME);
            long   typ = PositionGetInteger(POSITION_TYPE);

            // 1. Partial Profit (50%) & Move to BE
            if(vol > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
                bool hitTarget = (typ == POSITION_TYPE_BUY) ? (cur > ent + reachBE) : (cur < ent - reachBE);
                if(hitTarget) {
                    trade.PositionClosePartial(t, NormalizeDouble(vol/2.0, 2));
                    trade.PositionModify(t, ent, 0); 
                }
            }

            // 2. Structural Trailing Stop
            if(typ == POSITION_TYPE_BUY && cur > ent + (trail * 1.5)) {
                double nSL = NormalizeDouble(cur - trail, _Digits);
                if(nSL > sl + (5 * _Point)) trade.PositionModify(t, nSL, 0);
            }
            if(typ == POSITION_TYPE_SELL && cur < ent - (trail * 1.5)) {
                double nSL = NormalizeDouble(cur + trail, _Digits);
                if(sl == 0 || nSL < sl - (5 * _Point)) trade.PositionModify(t, nSL, 0);
            }
        }
    }
}

int OnInit() {
    trade.SetExpertMagicNumber(MAGIC_ORCH_INTRA);
    for(int i=0; i<16; i++) {
        hud_names[i] = "ORCH_INTRA_" + (string)i;
        ObjectCreate(0, hud_names[i], OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, hud_names[i], OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, hud_names[i], OBJPROP_XDISTANCE, 40);
        ObjectSetInteger(0, hud_names[i], OBJPROP_YDISTANCE, 50 + (i * 18));
        ObjectSetInteger(0, hud_names[i], OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, hud_names[i], OBJPROP_FONT, "Consolas");
    }
    // Hardcoded handles for M15
    hFast  = iMA(_Symbol, PERIOD_M15, 9, 0, MODE_EMA, PRICE_CLOSE);
    hSlow  = iMA(_Symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
    hTrend = iMA(_Symbol, PERIOD_M15, 200, 0, MODE_EMA, PRICE_CLOSE);
    hATR   = iATR(_Symbol, PERIOD_M15, 14);
    return(INIT_SUCCEEDED);
}

void OnTick() {
    double f[], s[], atr[];
    ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(atr,true);
    MqlRates r[]; ArraySetAsSeries(r,true);
    if(CopyBuffer(hFast,0,0,1,f)<1 || CopyBuffer(hSlow,0,0,1,s)<1 || 
       CopyBuffer(hATR,0,0,1,atr)<1 || CopyRates(_Symbol,PERIOD_M15,0,5,r)<5) return;

    OrchestrateProtection(atr[0]);
    
    bool isBull = f[0] > s[0];
    bool isExplosive = (MathAbs(r[0].close - r[0].open) >= (atr[0] * InpExplosiveFactor));
    
    // Intra Entry Logic
    if(PositionsTotal() < InpMaxConcurrent && isExplosive) {
        if(isBull) trade.Buy(InpLotSize, _Symbol, r[0].close, r[0].close - (atr[0]*4.0), 0);
        else trade.Sell(InpLotSize, _Symbol, r[0].close, r[0].close + (atr[0]*4.0), 0);
    }

    // HUD Update
    RenderHUD(0, "Orchestrator",   "INTRADAY", G_PURP);
    RenderHUD(1, "Target TF",      "M15", G_CYAN);
    RenderHUD(2, "Best Pair Match", "XAUUSD / Majors", G_WHITE);
    RenderHUD(3, "Vol. Sensitivity", DoubleToString(InpExplosiveFactor,1), G_WHITE);
    RenderHUD(4, "Checklist",      (isExplosive?"READY":"WAITING"), (isExplosive?G_CYAN:G_PINK));
}

void OnDeinit(const int r) { for(int i=0; i<16; i++) ObjectDelete(0, hud_names[i]); }