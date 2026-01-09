//+------------------------------------------------------------------+
//|                                   Garuda_XAUUSD_Final_HUD.mq5    |
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
input double          InpExplosiveFactor = 1.2;      

//--- Global Variables
int hFast, hSlow, hTrend, hATR;
CTrade trade;
string hud_names[16]; // Increased for "Best TF" line
string watermark_id = "G_WATERMARK";

//+------------------------------------------------------------------+
//| Profit Protection Logic (XAUUSD Optimized)                       |
//+------------------------------------------------------------------+
void ProtectProfits(double atr) {
    double partialMult = (InpTradeMode == MODE_SCALPING) ? 1.5 : (InpTradeMode == MODE_INTRA) ? 2.5 : 4.0;
    double trailMult   = (InpTradeMode == MODE_SCALPING) ? 2.2 : (InpTradeMode == MODE_INTRA) ? 3.5 : 6.0;

    for(int i=PositionsTotal()-1; i>=0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i))) {
            ulong  ticket  = PositionGetTicket(i);
            if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

            double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
            double current = PositionGetDouble(POSITION_PRICE_CURRENT);
            double sl      = PositionGetDouble(POSITION_SL);
            double vol     = PositionGetDouble(POSITION_VOLUME);
            long   type    = PositionGetInteger(POSITION_TYPE);

            // 1. Partial & BE
            double target = atr * partialMult;
            bool hitTarget = (type == POSITION_TYPE_BUY) ? (current > entry + target) : (current < entry - target);
            if(hitTarget && vol > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
                trade.PositionClosePartial(ticket, NormalizeDouble(vol/2.0, 2));
                trade.PositionModify(ticket, entry, 0); 
            }

            // 2. Trailing Stop
            double trailDist = atr * trailMult;
            if(type == POSITION_TYPE_BUY && current > entry + trailDist) {
                double newSL = NormalizeDouble(current - trailDist, _Digits);
                if(newSL > sl + (10 * _Point)) trade.PositionModify(ticket, newSL, 0);
            }
            if(type == POSITION_TYPE_SELL && current < entry - trailDist) {
                double newSL = NormalizeDouble(current + trailDist, _Digits);
                if(sl == 0 || newSL < sl - (10 * _Point)) trade.PositionModify(ticket, newSL, 0);
            }
        }
    }
}

void RenderHUD(int index, string key, string value, color clr) {
    string alignedText = StringFormat("%-18s: %-12s", key, value);
    ObjectSetString(0, hud_names[index], OBJPROP_TEXT, alignedText);
    ObjectSetInteger(0, hud_names[index], OBJPROP_COLOR, clr);
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
    for(int i=0; i<16; i++) {
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

    ProtectProfits(atr[0]);
    bool isBullish = f[0] > s[0];
    bool explosive = (MathAbs(r[0].close - r[0].open) >= (atr[0] * InpExplosiveFactor));
    bool isFlat = (MathAbs(t[0] - t[4]) < (0.0005));
    double targetPrice = isBullish ? iHigh(_Symbol, PERIOD_D1, 1) : iLow(_Symbol, PERIOD_D1, 1);
    
    // HUD Strings
    string mStr = (InpTradeMode==MODE_SCALPING)?"SCALPING":(InpTradeMode==MODE_INTRA)?"INTRADAY":"SWING";
    string bTF  = (InpTradeMode==MODE_SCALPING)?"M1 / M5":(InpTradeMode==MODE_INTRA)?"M15 / M30":"H1 / H4";

    RenderHUD(0,  "Trading Mode",    mStr, G_PURP);
    RenderHUD(1,  "Best Timeframe",  bTF, G_CYAN); // NEW LINE
    RenderHUD(2,  "Bot Status",      (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"ALGO ON":"ALGO OFF"), G_CYAN);
    RenderHUD(3,  "Equity Status",   (AccountInfoDouble(ACCOUNT_MARGIN_FREE)<(AccountInfoDouble(ACCOUNT_EQUITY)*0.2)?"FUNDING REQ":"STABLE"), G_WHITE);
    RenderHUD(4,  "Market Activity", (isFlat ? "QUIET" : "ACTIVE"), (isFlat?G_PINK:G_CYAN));
    RenderHUD(5,  "Trade Quality",   (explosive ? "GOOD VOL" : "LOW VOL"), G_CYAN);
    RenderHUD(6,  "Bot Waiting For", (isFlat ? "EMA ANGLE" : (!explosive ? "MOMENTUM" : "READY")), G_PURP);
    RenderHUD(7,  "Checklist",       (explosive && !isFlat ? "READY" : "STANDBY"), (explosive && !isFlat?G_CYAN:G_PINK));
    RenderHUD(8,  "FVG Status",      (r[0].low > r[2].high ? "BULLISH" : r[0].high < r[2].low ? "BEARISH" : "NONE"), G_PURP);
    RenderHUD(9,  "EMA 9/21 Rel.",   (isBullish ? "9 > 21" : "9 < 21"), G_CYAN);
    RenderHUD(10, "HTF Liquidity",   (isBullish?"BULL":"BEAR")+" @"+DoubleToString(targetPrice, 2), G_WHITE);
    RenderHUD(11, "Trade Ratio",     (string)PositionsTotal()+" / "+(string)InpMaxConcurrent, G_CYAN);
    RenderHUD(12, "Lot Size Set",    DoubleToString(InpLotSize, 2), G_WHITE);
    RenderHUD(13, "1H Trend",        ScanTrend(PERIOD_H1), G_WHITE);
    RenderHUD(14, "M15 Trend",       ScanTrend(PERIOD_M15), G_WHITE);
    RenderHUD(15, "M1 Trend",         ScanTrend(PERIOD_M1), G_WHITE);
}

void OnDeinit(const int r) { for(int i=0; i<16; i++) ObjectDelete(0, hud_names[i]); }