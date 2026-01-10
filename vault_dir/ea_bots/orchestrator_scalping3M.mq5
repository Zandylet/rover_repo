//+------------------------------------------------------------------+
//|                                     Orchestrator_Scalping3M.mq5  |
//|                                  Copyright 2026, Gemini AI       |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

//--- Unique Identity for the 3M Orchestrator
#define MAGIC_ORCH_3M 1104

//--- Garuda Palette
#define G_CYAN    C'0, 255, 255' 
#define G_PINK    C'255, 0, 127' 
#define G_PURP    C'187, 154, 247'
#define G_WHITE   C'248, 248, 242'

//--- Inputs
input double   InpLotSize        = 0.02;      // Slightly higher lot due to better signal quality
input int      InpMaxConcurrent  = 4;         
input double   InpExplosiveFactor = 1.2;      // Recalibrated for M3 body size

//--- Global Variables
int hFast, hSlow, hTrend, hATR;
CTrade trade;
string hud_names[16]; 

//+------------------------------------------------------------------+
//| Symmetrical HUD Helper                                           |
//+------------------------------------------------------------------+
void RenderHUD(int index, string key, string value, color clr) {
    string alignedText = StringFormat("%-18s: %-12s", key, value);
    ObjectSetString(0, hud_names[index], OBJPROP_TEXT, alignedText);
    ObjectSetInteger(0, hud_names[index], OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Orchestration: The M3 "Sweet Spot" Protection                    |
//+------------------------------------------------------------------+
void OrchestrateProtection(double atr) {
    double reachBE = 1.1 * atr; // BE after 110% ATR move
    double trail   = 2.0 * atr; // Balanced trail for 3M swings

    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            if(PositionGetInteger(POSITION_MAGIC) != MAGIC_ORCH_3M) continue;
            
            ulong  t   = PositionGetTicket(i);
            double ent = PositionGetDouble(POSITION_PRICE_OPEN);
            double cur = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl  = PositionGetDouble(POSITION_SL);
            long   typ = PositionGetInteger(POSITION_TYPE);

            // 1. Structural Break-Even
            if(sl != ent) {
                if((typ == POSITION_TYPE_BUY && cur > ent + reachBE) || 
                   (typ == POSITION_TYPE_SELL && cur < ent - reachBE)) {
                    trade.PositionModify(t, ent, 0); 
                }
            }

            // 2. Trend-Following Trail
            if(typ == POSITION_TYPE_BUY && cur > ent + (trail * 1.3)) {
                double nSL = NormalizeDouble(cur - trail, _Digits);
                if(nSL > sl + (3 * _Point)) trade.PositionModify(t, nSL, 0);
            }
            if(typ == POSITION_TYPE_SELL && cur < ent - (trail * 1.3)) {
                double nSL = NormalizeDouble(cur + trail, _Digits);
                if(sl == 0 || nSL < sl - (3 * _Point)) trade.PositionModify(t, nSL, 0);
            }
        }
    }
}

int OnInit() {
    trade.SetExpertMagicNumber(MAGIC_ORCH_3M);
    for(int i=0; i<16; i++) {
        hud_names[i] = "ORCH3M_HUD_" + (string)i;
        ObjectCreate(0, hud_names[i], OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, hud_names[i], OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, hud_names[i], OBJPROP_XDISTANCE, 40);
        ObjectSetInteger(0, hud_names[i], OBJPROP_YDISTANCE, 50 + (i * 18));
        ObjectSetInteger(0, hud_names[i], OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, hud_names[i], OBJPROP_FONT, "Consolas");
    }
    // Hardcoded for M3 Efficiency
    hFast  = iMA(_Symbol, PERIOD_M3, 9, 0, MODE_EMA, PRICE_CLOSE);
    hSlow  = iMA(_Symbol, PERIOD_M3, 21, 0, MODE_EMA, PRICE_CLOSE);
    hTrend = iMA(_Symbol, PERIOD_M3, 200, 0, MODE_EMA, PRICE_CLOSE);
    hATR   = iATR(_Symbol, PERIOD_M3, 14);
    return(INIT_SUCCEEDED);
}

void OnTick() {
    double f[], s[], atr[];
    ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(atr,true);
    MqlRates r[]; ArraySetAsSeries(r,true);
    if(CopyBuffer(hFast,0,0,1,f)<1 || CopyBuffer(hSlow,0,0,1,s)<1 || 
       CopyBuffer(hATR,0,0,1,atr)<1 || CopyRates(_Symbol, PERIOD_M3, 0, 5, r)<5) return;

    OrchestrateProtection(atr[0]);
    
    bool isBull = f[0] > s[0];
    bool isExplosive = (MathAbs(r[0].close - r[0].open) >= (atr[0] * InpExplosiveFactor));
    
    // Auto-Entry based on 3-Minute Structure
    if(PositionsTotal() < InpMaxConcurrent && isExplosive) {
        if(isBull) trade.Buy(InpLotSize, _Symbol, r[0].close, r[0].close - (atr[0]*3.5), 0);
        else trade.Sell(InpLotSize, _Symbol, r[0].close, r[0].close + (atr[0]*3.5), 0);
    }

    // HUD Data
    RenderHUD(0, "Orchestrator",   "SCALPING 3M", G_PURP);
    RenderHUD(1, "Logic Period",   "PERIOD_M3", G_CYAN);
    RenderHUD(2, "M3 Volatility",  DoubleToString(atr[0], _Digits), G_WHITE);
    RenderHUD(3, "Entry Signal",   (isExplosive?"EXPLOSIVE":"CALM"), (isExplosive?G_CYAN:G_WHITE));
    RenderHUD(4, "Total Risk",     DoubleToString(PositionsTotal()*InpLotSize, 2)+" Lots", G_PINK);
}

void OnDeinit(const int r) { for(int i=0; i<16; i++) ObjectDelete(0, hud_names[i]); }