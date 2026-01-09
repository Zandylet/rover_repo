//+------------------------------------------------------------------+
//|                                   Garuda_Final_Adaptive_V1.mq5   |
//|                                  Copyright 2026, Gemini AI       |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

enum ENUM_TRADE_MODE { MODE_SCALPING, MODE_INTRA, MODE_SWING };

//--- Colors
#define G_CYAN    C'0, 255, 255' 
#define G_PINK    C'255, 0, 127' 
#define G_PURP    C'187, 154, 247'
#define G_WHITE   C'248, 248, 242'
#define G_GRAY    C'60, 60, 60' 

//--- Inputs
input ENUM_TRADE_MODE InpTradeMode      = MODE_SCALPING; 
input double          InpLotSize        = 0.01;      
input int             InpMaxConcurrent  = 5;         
input double          InpExplosiveFactor = 0.85;     

//--- Global
int hFast, hSlow, hTrend, hATR;
CTrade trade;
string hud_names[15];
string watermark_id = "G_WATERMARK";

//+------------------------------------------------------------------+
//| Profit Protection Logic (Adaptive)                               |
//+------------------------------------------------------------------+
void ProtectProfits(double atr) {
    // Multipliers adapt based on Mode
    double partialMult = (InpTradeMode == MODE_SCALPING) ? 1.0 : (InpTradeMode == MODE_INTRA) ? 1.5 : 2.5;
    double trailMult   = (InpTradeMode == MODE_SCALPING) ? 1.5 : (InpTradeMode == MODE_INTRA) ? 2.0 : 3.5;

    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            ulong  ticket  = PositionGetTicket(i);
            double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
            double current = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl      = PositionGetDouble(POSITION_SL);
            double vol     = PositionGetDouble(POSITION_VOLUME);
            long   type    = PositionGetInteger(POSITION_TYPE);

            // 1. Partial Scale-Out (50%) & Move to Break-Even
            double target = atr * partialMult;
            if(vol > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
                if((type == POSITION_TYPE_BUY && current > entry + target) || 
                   (type == POSITION_TYPE_SELL && current < entry - target)) {
                    trade.PositionClosePartial(ticket, NormalizeDouble(vol/2.0, 2));
                    trade.PositionModify(ticket, entry, 0); 
                }
            }

            // 2. Adaptive Trailing Stop
            double trailDist = atr * trailMult;
            if(type == POSITION_TYPE_BUY && current > entry + trailDist) {
                double newSL = NormalizeDouble(current - trailDist, _Digits);
                if(newSL > sl + (5 * _Point)) trade.PositionModify(ticket, newSL, 0);
            }
            if(type == POSITION_TYPE_SELL && current < entry - trailDist) {
                double newSL = NormalizeDouble(current + trailDist, _Digits);
                if(sl == 0 || newSL < sl - (5 * _Point)) trade.PositionModify(ticket, newSL, 0);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Symmetrical HUD Helper                                           |
//+------------------------------------------------------------------+
void RenderHUD(int index, string key, string value, color clr) {
    string alignedText = StringFormat("%-18s: %-12s", key, value);
    ObjectSetString(0, hud_names[index], OBJPROP_TEXT, alignedText);
    ObjectSetInteger(0, hud_names[index], OBJPROP_COLOR, clr);
}

void CreateWatermark() {
    string mStr = (InpTradeMode==MODE_SCALPING)?"SCALP":(InpTradeMode==MODE_INTRA)?"INTRA":"SWING";
    ObjectCreate(0, watermark_id, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, watermark_id, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, watermark_id, OBJPROP_XDISTANCE, 50);
    ObjectSetInteger(0, watermark_id, OBJPROP_YDISTANCE, 50);
    ObjectSetInteger(0, watermark_id, OBJPROP_FONTSIZE, 55);
    ObjectSetString(0, watermark_id, OBJPROP_FONT, "Impact");
    ObjectSetInteger(0, watermark_id, OBJPROP_COLOR, G_GRAY);
    ObjectSetInteger(0, watermark_id, OBJPROP_BACK, true); 
    ObjectSetString(0, watermark_id, OBJPROP_TEXT, _Symbol + " [" + mStr + "]");
}

string ScanTrend(ENUM_TIMEFRAMES tf) {
    double f[], s[];
    int hF = iMA(_Symbol, tf, 9, 0, MODE_EMA, PRICE_CLOSE);
    int hS = iMA(_Symbol, tf, 21, 0, MODE_EMA, PRICE_CLOSE);
    ArraySetAsSeries(f, true); ArraySetAsSeries(s, true);
    if(CopyBuffer(hF,0,0,1,f)<1 || CopyBuffer(hS,0,0,1,s)<1) { IndicatorRelease(hF); IndicatorRelease(hS); return "LOAD"; }
    IndicatorRelease(hF); IndicatorRelease(hS);
    return (f[0] > s[0]) ? "BULLISH" : "BEARISH";
}

int OnInit() {
    CreateWatermark();
    for(int i=0; i<15; i++) {
        hud_names[i] = "G_HUD_" + (string)i;
        ObjectCreate(0, hud_names[i], OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, hud_names[i], OBJPROP_CORNER, CORNER_RIGHT_UPPER);
        ObjectSetInteger(0, hud_names[i], OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
        ObjectSetInteger(0, hud_names[i], OBJPROP_XDISTANCE, 40);
        ObjectSetInteger(0, hud_names[i], OBJPROP_YDISTANCE, 50 + (i * 18));
        ObjectSetInteger(0, hud_names[i], OBJPROP_FONTSIZE, 9);
        ObjectSetString(0, hud_names[i], OBJPROP_FONT, "Consolas");
    }
    ENUM_TIMEFRAMES aTF = (InpTradeMode==MODE_SCALPING)?PERIOD_M1:(InpTradeMode==MODE_INTRA)?PERIOD_M15:PERIOD_H1;
    hFast=iMA(_Symbol,aTF,9,0,MODE_EMA,PRICE_CLOSE);
    hSlow=iMA(_Symbol,aTF,21,0,MODE_EMA,PRICE_CLOSE);
    hTrend=iMA(_Symbol,aTF,200,0,MODE_EMA,PRICE_CLOSE);
    hATR=iATR(_Symbol,aTF,14);
    return(INIT_SUCCEEDED);
}

void OnTick() {
    double f[], s[], t[], atr[];
    ArraySetAsSeries(f,true); ArraySetAsSeries(s,true); ArraySetAsSeries(t,true); ArraySetAsSeries(atr,true);
    MqlRates r[]; ArraySetAsSeries(r,true);
    
    if(CopyBuffer(hFast,0,0,2,f)<2 || CopyBuffer(hSlow,0,0,2,s)<2 || CopyBuffer(hTrend,0,0,5,t)<5 ||
       CopyBuffer(hATR,0,0,1,atr)<1 || CopyRates(_Symbol,_Period,0,5,r)<5) return;

    // Logic 
    int active = PositionsTotal();
    bool isBullish = f[0] > s[0];
    bool explosive = (MathAbs(r[0].close - r[0].open) >= (atr[0] * InpExplosiveFactor));
    double slope = MathAbs(t[0] - t[4]);
    bool isFlat = slope < (0.00005 * (_Symbol == "XAUUSD" ? 10.0 : 1.0));
    string fvg = (r[0].low > r[2].high) ? "BULLISH" : (r[0].high < r[2].low ? "BEARISH" : "NONE");
    double targetPrice = isBullish ? iHigh(_Symbol, PERIOD_D1, 1) : iLow(_Symbol, PERIOD_D1, 1);

    // Protection Call
    ProtectProfits(atr[0]);

    // Entries
    if(active < InpMaxConcurrent && !isFlat && explosive) {
        double slPts = atr[0] * 3.0;
        if(isBullish) trade.Buy(InpLotSize, _Symbol, r[0].close, r[0].close - slPts, 0);
        if(!isBullish) trade.Sell(InpLotSize, _Symbol, r[0].close, r[0].close + slPts, 0);
    }

    // Sound alert
    static bool lastReady = false;
    bool currentReady = (explosive && !isFlat);
    if(currentReady && !lastReady) PlaySound("expert.wav");
    lastReady = currentReady;

    // HUD
    string mStr = (InpTradeMode==MODE_SCALPING)?"SCALPING":(InpTradeMode==MODE_INTRA)?"INTRADAY":"SWING";
    RenderHUD(0, "Trading Mode", mStr, G_PURP);
    RenderHUD(1, "Bot Status", (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"ALGO ON":"ALGO OFF"), G_CYAN);
    RenderHUD(2, "Equity Status", (AccountInfoDouble(ACCOUNT_MARGIN_FREE)<(AccountInfoDouble(ACCOUNT_EQUITY)*0.2)?"FUNDING REQ":"STABLE"), G_WHITE);
    RenderHUD(3, "Market Activity", (isFlat ? "QUIET" : "ACTIVE"), (isFlat?G_PINK:G_CYAN));
    RenderHUD(4, "Trade Quality", (explosive ? "GOOD VOL" : "LOW VOL"), G_CYAN);
    RenderHUD(5, "Bot Waiting For", (isFlat ? "EMA ANGLE" : (!explosive ? "MOMENTUM" : "READY")), G_PURP);
    RenderHUD(6, "Checklist", (currentReady ? "READY" : "STANDBY"), (currentReady?G_CYAN:G_PINK));
    RenderHUD(7, "FVG Status", fvg, G_PURP);
    RenderHUD(8, "EMA 9/21 Rel.", (isBullish ? "9 > 21" : "9 < 21"), G_CYAN);
    RenderHUD(9, "HTF Liquidity", (isBullish?"BULL":"BEAR")+" @"+DoubleToString(targetPrice,_Digits), G_WHITE);
    RenderHUD(10, "Trade Ratio", IntegerToString(active)+" / "+IntegerToString(InpMaxConcurrent), G_CYAN);
    RenderHUD(11, "Lot Size Set", DoubleToString(InpLotSize, 2), G_WHITE);
    RenderHUD(12, "1H Trend", ScanTrend(PERIOD_H1), G_WHITE);
    RenderHUD(13, "M15 Trend", ScanTrend(PERIOD_M15), G_WHITE);
    RenderHUD(14, "M1 Trend", ScanTrend(PERIOD_M1), G_WHITE);
}

void OnDeinit(const int r) { 
    for(int i=0; i<15; i++) ObjectDelete(0, hud_names[i]); 
    ObjectDelete(0, watermark_id);
}