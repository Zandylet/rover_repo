//+------------------------------------------------------------------+
//|                                     Orchestrator_Scalping.mq5    |
//|                                  Copyright 2026, Gemini AI       |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

//--- Unique Magic for Orchestrator
#define MAGIC_ORCH_SCALP 1101

//--- Symmetrical Palette
#define G_CYAN    C'0, 255, 255' 
#define G_PINK    C'255, 0, 127' 
#define G_PURP    C'187, 154, 247'
#define G_WHITE   C'248, 248, 242'

//--- Inputs
input double   InpLotSize        = 0.01;      
input int      InpMaxConcurrent  = 5;         
input double   InpExplosiveFactor = 1.1;      // Sensitivity to M1 spikes

//--- Global Handles
int hFast, hSlow, hTrend, hATR;
CTrade trade;
string hud_names[16]; 

//+------------------------------------------------------------------+
//| HUD: Symmetrical Orchestrator Interface                          |
//+------------------------------------------------------------------+
void RenderHUD(int index, string key, string value, color clr) {
    string alignedText = StringFormat("%-18s: %-12s", key, value);
    ObjectSetString(0, hud_names[index], OBJPROP_TEXT, alignedText);
    ObjectSetInteger(0, hud_names[index], OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Orchestration: Aggressive Profit Guard                           |
//+------------------------------------------------------------------+
void OrchestrateProtection(double atr) {
    double reachBE = 0.8 * atr; // Move to BE after 80% of ATR move
    double trail   = 1.5 * atr; // Tight trailing for M1 noise

    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) != MAGIC_ORCH_SCALP) continue;
            
            ulong  t   = PositionGetTicket(i);
            double ent = PositionGetDouble(POSITION_PRICE_OPEN);
            double cur = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl  = PositionGetDouble(POSITION_SL);
            long   typ = PositionGetInteger(POSITION_TYPE);

            // 1. Instant Break-Even Orchestration
            if(sl != ent) {
                if((typ == POSITION_TYPE_BUY && cur > ent + reachBE) || 
                   (typ == POSITION_TYPE_SELL && cur < ent - reachBE)) {
                    trade.PositionModify(t, ent, 0); 
                }
            }

            // 2. High-Frequency Trailing
            if(typ == POSITION_TYPE_BUY && cur > ent + (trail * 1.2)) {
                double nSL = NormalizeDouble(cur - trail, _Digits);
                if(nSL > sl + (2 * _Point)) trade.PositionModify(t, nSL, 0);
            }
            if(typ == POSITION_TYPE_SELL && cur < ent - (trail * 1.2)) {
                double nSL = NormalizeDouble(cur + trail, _Digits);
                if(sl == 0 || nSL < sl - (2 * _Point)) trade.PositionModify(t, nSL, 0);
            }
        }
    }
}

int OnInit() {
    trade.SetExpertMagicNumber(MAGIC_ORCH_SCALP);
    for(int i=0; i<16; i++) {
        hud_names[i] = "ORCH_HUD_" + (string)i;
        ObjectCreate(0, hud_names[i], OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, hud_names[i], OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, hud_names[i], OBJPROP_XDISTANCE, 40);
        ObjectSetInteger(0, hud_names[i], OBJPROP_YDISTANCE, 50 + (i * 18));
        ObjectSetInteger(0, hud_names[i], OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, hud_names[i], OBJPROP_FONT, "Consolas");
    }
    hFast  = iMA(_Symbol, PERIOD_M1, 9, 0, MODE_EMA, PRICE_CLOSE);
    hSlow  = iMA(_Symbol, PERIOD_M1, 21, 0, MODE_EMA, PRICE_CLOSE);
    hTrend = iMA(_Symbol, PERIOD_M1, 200, 0, MODE_EMA, PRICE_CLOSE);
    hATR   = iATR(_Symbol, PERIOD_M1, 14);
    return(INIT_SUCCEEDED);
}

void OnTick() {
    double f[], s[], t[], atr[];
    ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(t,true); ArraySetAsSeries(atr,true);
    MqlRates r[]; ArraySetAsSeries(r,true);
    if(CopyBuffer(hFast,0,0,1,f)<1 || CopyBuffer(hSlow,0,0,1,s)<1 || 
       CopyBuffer(hATR,0,0,1,atr)<1 || CopyRates(_Symbol,PERIOD_M1,0,5,r)<5) return;

    OrchestrateProtection(atr[0]);
    
    bool isBull = f[0] > s[0];
    bool isExplosive = (MathAbs(r[0].close - r[0].open) >= (atr[0] * InpExplosiveFactor));
    
    // Auto-Entry
    if(PositionsTotal() < InpMaxConcurrent && isExplosive) {
        if(isBull) trade.Buy(InpLotSize, _Symbol, r[0].close, r[0].close - (atr[0]*2.5), 0);
        else trade.Sell(InpLotSize, _Symbol, r[0].close, r[0].close + (atr[0]*2.5), 0);
    }

    // HUD Display
    RenderHUD(0, "Orchestrator",   "SCALPING", G_PURP);
    RenderHUD(1, "Target TF",      "M1 (Primary)", G_CYAN);
    RenderHUD(2, "Market Flow",    (isBull?"BULLISH":"BEARISH"), G_WHITE);
    RenderHUD(3, "Vol. Status",    (isExplosive?"SPIKE DETECTED":"NORMAL"), (isExplosive?G_CYAN:G_WHITE));
    RenderHUD(4, "Active Orders",  (string)PositionsTotal(), G_CYAN);
}

void OnDeinit(const int r) { for(int i=0; i<16; i++) ObjectDelete(0, hud_names[i]); }