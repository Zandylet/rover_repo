//+------------------------------------------------------------------+
//| Mirage Liquidity Sweep Pro [WillyAlgoTrader]                     |
//| MT5 / MQL5 conversion of Pine v1.3.1                             |
//|                                                                  |
//| Indicator version: signal + simulated trade management           |
//| No broker orders are placed.                                    |
//+------------------------------------------------------------------+
#property copyright "WillyAlgoTrader"
#property version   "1.30"
#property strict
#property indicator_chart_window
#property indicator_plots 0

//--- Main
input group "Main Settings"
input int      InpSwingLength       = 21;
input int      InpMaxSweepDistance  = 80;
input int      InpMinSweepScore     = 50;

//--- Confirmation
input group "Confirmation"
input bool     InpRequireCHoCH      = true;
input int      InpStructureLength   = 8;
input int      InpConfirmWindow     = 13;

//--- Filters
input group "Filters"
input bool     InpUseVolume         = true;
input int      InpVolumeMALength    = 21;
input double   InpVolumeSpike       = 1.5;
input bool     InpUseHTFBias        = true;
input ENUM_TIMEFRAMES InpHTF        = PERIOD_H4;
input int      InpHTFEMALength      = 50;

//--- Risk
input group "Risk Management"
enum ENUM_RISK_PRESET
{
   RISK_CONSERVATIVE,
   RISK_BALANCED,
   RISK_AGGRESSIVE,
   RISK_SCALPING,
   RISK_CUSTOM
};
input ENUM_RISK_PRESET InpRiskPreset = RISK_BALANCED;
input int      InpATRLength           = 14;
input double   InpSLBufferATR         = 0.25;
input double   InpTP1R                = 1.0;
input double   InpTP2R                = 2.0;
input double   InpTP3R                = 3.0;
input bool     InpBreakEvenAfterTP1   = true;
input bool     InpShowSLTP            = true;

//--- Liquidity
input group "Liquidity"
input bool     InpShowLiquidity       = true;
input int      InpMaxLiquiditySide    = 6;
input int      InpLiquidityExtendBars = 10;
input bool     InpShowLiquidityLabels = true;
input bool     InpShowEqualHL         = true;
input double   InpEqualToleranceATR   = 0.15;
input bool     InpShowLiquidityTarget = true;

//--- Visual
input group "Visual"
input bool     InpShowSweepMarks      = true;
input bool     InpShowSweepLines      = true;
input int      InpSweepLineExtend     = 8;
input bool     InpShowPenetration     = true;
input int      InpMaxSweepDrawings    = 15;
input bool     InpShowSignals         = true;
input bool     InpShowScoreLabels     = false;
input bool     InpShowSweptLevel      = true;
input bool     InpShowWatermark       = true;

//--- Dashboard
input group "Dashboard"
input bool     InpShowDashboard       = true;

//--- Alerts
input group "Alerts"
input bool     InpEnableAlerts        = true;
input bool     InpWebhookJSON         = false;
input bool     InpAlertSL             = true;
input bool     InpAlertTP             = false;

//--- colors
input group "Colors"
input color    InpBullColor           = clrLimeGreen;
input color    InpBearColor           = clrTomato;

//--- object prefixes
string PREFIX = "MIRAGE_";

//--- swing memory
struct SwingPoint
{
   double price;
   int    shift;
   bool   used;
};
SwingPoint Highs[];
SwingPoint Lows[];

//--- simulated trade state
int      ActiveDir       = 0;
double   ActiveEntry     = 0.0;
double   ActiveSL        = 0.0;
double   ActiveTP1       = 0.0;
double   ActiveTP2       = 0.0;
double   ActiveTP3       = 0.0;
int      EntryShift      = -1;
bool     TP1Reached      = false;
bool     TP2Reached      = false;
bool     TP3Reached      = false;
bool     BEActive        = false;

int      StatWins        = 0;
int      StatLosses      = 0;
string   FormString      = "";

int      PendingDir      = 0;
int      PendingShift    = -1;
double   PendingLevel    = 0.0;
double   PendingWick     = 0.0;
double   PendingScore    = 0.0;

int      LastSignalDir   = 0;
double   LastSignalScore = 0.0;

//--- handles
int      ATRHandle       = INVALID_HANDLE;
int      HTFEMAHandle    = INVALID_HANDLE;

//--- bar tracking
datetime LastBarTime = 0;

//+------------------------------------------------------------------+
double GetRiskBuffer()
{
   switch(InpRiskPreset)
   {
      case RISK_CONSERVATIVE: return 0.50;
      case RISK_AGGRESSIVE:   return 0.15;
      case RISK_SCALPING:     return 0.10;
      case RISK_CUSTOM:       return InpSLBufferATR;
      default:                return 0.25;
   }
}
//+------------------------------------------------------------------+
double GetTP1()
{
   switch(InpRiskPreset)
   {
      case RISK_CONSERVATIVE: return 1.0;
      case RISK_AGGRESSIVE:   return 1.5;
      case RISK_SCALPING:     return 0.8;
      case RISK_CUSTOM:       return InpTP1R;
      default:                return 1.0;
   }
}
//+------------------------------------------------------------------+
double GetTP2()
{
   switch(InpRiskPreset)
   {
      case RISK_CONSERVATIVE: return 2.0;
      case RISK_AGGRESSIVE:   return 2.5;
      case RISK_SCALPING:     return 1.5;
      case RISK_CUSTOM:       return InpTP2R;
      default:                return 2.0;
   }
}
//+------------------------------------------------------------------+
double GetTP3()
{
   switch(InpRiskPreset)
   {
      case RISK_CONSERVATIVE: return 4.0;
      case RISK_AGGRESSIVE:   return 4.0;
      case RISK_SCALPING:     return 2.0;
      case RISK_CUSTOM:       return InpTP3R;
      default:                return 3.0;
   }
}
//+------------------------------------------------------------------+
double ATR(const int shift)
{
   if(ATRHandle == INVALID_HANDLE) return 0.0;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(ATRHandle,0,shift,1,b) != 1) return 0.0;
   return b[0];
}
//+------------------------------------------------------------------+
double HTFEMA(const int shift)
{
   if(HTFEMAHandle == INVALID_HANDLE) return 0.0;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(HTFEMAHandle,0,shift,1,b) != 1) return 0.0;
   return b[0];
}
//+------------------------------------------------------------------+
double HTFClosedClose()
{
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,InpHTF,1,1,r) != 1) return 0.0;
   return r[0].close;
}
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t=iTime(_Symbol,_Period,0);
   if(t==0) return false;
   if(t!=LastBarTime)
   {
      LastBarTime=t;
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+
bool IsPivotHigh(const MqlRates &r[],const int shift,const int len,const int total)
{
   if(shift-len<0 || shift+len>=total) return false;
   double p=r[shift].high;
   for(int i=1;i<=len;i++)
      if(r[shift-i].high>=p || r[shift+i].high>p) return false;
   return true;
}
//+------------------------------------------------------------------+
bool IsPivotLow(const MqlRates &r[],const int shift,const int len,const int total)
{
   if(shift-len<0 || shift+len>=total) return false;
   double p=r[shift].low;
   for(int i=1;i<=len;i++)
      if(r[shift-i].low<=p || r[shift+i].low<p) return false;
   return true;
}
//+------------------------------------------------------------------+
void AddHigh(const double price,const int shift)
{
   SwingPoint x;
   x.price=price; x.shift=shift; x.used=false;
   int n=ArraySize(Highs);
   ArrayResize(Highs,n+1);
   Highs[n]=x;
   if(ArraySize(Highs)>25)
   {
      for(int i=1;i<ArraySize(Highs);i++) Highs[i-1]=Highs[i];
      ArrayResize(Highs,25);
   }
}
//+------------------------------------------------------------------+
void AddLow(const double price,const int shift)
{
   SwingPoint x;
   x.price=price; x.shift=shift; x.used=false;
   int n=ArraySize(Lows);
   ArrayResize(Lows,n+1);
   Lows[n]=x;
   if(ArraySize(Lows)>25)
   {
      for(int i=1;i<ArraySize(Lows);i++) Lows[i-1]=Lows[i];
      ArrayResize(Lows,25);
   }
}
//+------------------------------------------------------------------+
double VolumeComponent(const MqlRates &r[],const int shift,const int total)
{
   if(!InpUseVolume) return 0.5;
   if(r[shift].tick_volume<=0) return 0.5;

   int len=MathMin(InpVolumeMALength,total-shift-1);
   if(len<2) return 0.5;

   double sum=0.0;
   for(int i=shift+1;i<=shift+len;i++) sum+=(double)r[i].tick_volume;
   double ma=sum/len;
   if(ma<=0) return 0.5;

   double ratio=(double)r[shift].tick_volume/ma;
   double denom=MathMax(InpVolumeSpike-1.0,0.1);
   return MathMin(MathMax((ratio-1.0)/denom,0.0),1.0);
}
//+------------------------------------------------------------------+
double SweepScore(const int dir,const double lvl,const MqlRates &b,const double atr,const double volComp,const double htfComp)
{
   if(atr<=0 || lvl<=0) return 0.0;
   double range=b.high-b.low;
   if(range<=0) return 0.0;

   double wick=(dir==1 ? MathMin(b.open,b.close)-b.low
                         : b.high-MathMax(b.open,b.close));
   double reclaim=(dir==1 ? b.close-lvl : lvl-b.close);
   double closePos=(b.close-b.low)/range;
   double cpComp=(dir==1 ? closePos : 1.0-closePos);
   double wickComp=MathMin(MathMax(wick/atr,0.0),1.0);
   double rclComp=MathMin(MathMax(reclaim/atr,0.0),1.0);

   return (wickComp*0.30+rclComp*0.25+cpComp*0.20+
           volComp*0.15+htfComp*0.10)*100.0;
}
//+------------------------------------------------------------------+
bool GetMinorHigh(const MqlRates &r[],const int total,const int len,double &value)
{
   for(int s=len+1;s<total-len;s++)
      if(IsPivotHigh(r,s,len,total))
      {
         value=r[s].high;
         return true;
      }
   return false;
}
//+------------------------------------------------------------------+
bool GetMinorLow(const MqlRates &r[],const int total,const int len,double &value)
{
   for(int s=len+1;s<total-len;s++)
      if(IsPivotLow(r,s,len,total))
      {
         value=r[s].low;
         return true;
      }
   return false;
}
//+------------------------------------------------------------------+
void DeleteObjectSafe(const string name)
{
   if(ObjectFind(0,name)>=0) ObjectDelete(0,name);
}
//+------------------------------------------------------------------+
void HLine(const string name,const double price,const color clr,
           const ENUM_LINE_STYLE style=STYLE_DOT,const int width=1)
{
   DeleteObjectSafe(name);
   ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
}
//+------------------------------------------------------------------+
void TrendLine(const string name,const datetime t1,const double p1,
               const datetime t2,const double p2,const color clr,
               const ENUM_LINE_STYLE style=STYLE_DASH,const int width=1)
{
   DeleteObjectSafe(name);
   ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
}
//+------------------------------------------------------------------+
void TextObject(const string name,const datetime t,const double price,
                const string text,const color clr,const int size=9)
{
   DeleteObjectSafe(name);
   ObjectCreate(0,name,OBJ_TEXT,0,t,price);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT);
}
//+------------------------------------------------------------------+
void MarkSweep(const string side,const MqlRates &b,const double level,const double score,
               const color clr,const int shift)
{
   if(InpShowSweepMarks)
   {
      string n=PREFIX+"SWEEP_"+side+"_"+IntegerToString((int)b.time);
      TextObject(n,b.time,side=="BUY"?b.low:b.high,"×",clr,12);
   }

   if(InpShowScoreLabels)
   {
      string n=PREFIX+"SCORE_"+IntegerToString((int)b.time);
      double p=(side=="BUY"?b.low:b.high)+(side=="BUY"?-1:1)*ATR(1)*0.6;
      TextObject(n,b.time,p,DoubleToString(score,0),clr,8);
   }

   if(InpShowSweepLines)
   {
      datetime t1=iTime(_Symbol,_Period,shift);
      datetime t2=iTime(_Symbol,_Period,0);
      TrendLine(PREFIX+"SWEPT_"+IntegerToString((int)b.time),t1,level,t2,level,
                clr,STYLE_DASH,1);
   }
}
//+------------------------------------------------------------------+
void DrawTradeLevels()
{
   DeleteObjectSafe(PREFIX+"ENTRY");
   DeleteObjectSafe(PREFIX+"SL");
   DeleteObjectSafe(PREFIX+"TP1");
   DeleteObjectSafe(PREFIX+"TP2");
   DeleteObjectSafe(PREFIX+"TP3");

   if(ActiveDir==0 || !InpShowSLTP) return;

   HLine(PREFIX+"ENTRY",ActiveEntry,clrSlateGray,STYLE_DOT,1);
   HLine(PREFIX+"SL",ActiveSL,BEActive?clrOrangeRed:clrRed,STYLE_SOLID,2);
   HLine(PREFIX+"TP1",ActiveTP1,TP1Reached?clrTeal:clrGreen,TP1Reached?STYLE_SOLID:STYLE_DASH,1);
   HLine(PREFIX+"TP2",ActiveTP2,TP2Reached?clrTeal:clrGreen,TP2Reached?STYLE_SOLID:STYLE_DASH,1);
   HLine(PREFIX+"TP3",ActiveTP3,TP3Reached?clrTeal:clrGreen,TP3Reached?STYLE_SOLID:STYLE_DASH,1);
}
//+------------------------------------------------------------------+
void OpenSimulatedTrade(const int dir,const double entry,const double wick,
                        const double atr,const double score)
{
   if(ActiveDir!=0 || atr<=0) return;

   double buf=GetRiskBuffer();
   double dist=0.0;

   ActiveEntry=entry;

   if(dir==1)
   {
      ActiveSL=wick-atr*buf;
      dist=MathAbs(ActiveEntry-ActiveSL);
      if(dist<atr*0.5){ ActiveSL=ActiveEntry-atr*0.5; dist=atr*0.5; }
      ActiveTP1=ActiveEntry+dist*GetTP1();
      ActiveTP2=ActiveEntry+dist*GetTP2();
      ActiveTP3=ActiveEntry+dist*GetTP3();
   }
   else
   {
      ActiveSL=wick+atr*buf;
      dist=MathAbs(ActiveSL-ActiveEntry);
      if(dist<atr*0.5){ ActiveSL=ActiveEntry+atr*0.5; dist=atr*0.5; }
      ActiveTP1=ActiveEntry-dist*GetTP1();
      ActiveTP2=ActiveEntry-dist*GetTP2();
      ActiveTP3=ActiveEntry-dist*GetTP3();
   }

   ActiveDir=dir;
   EntryShift=1;
   TP1Reached=false; TP2Reached=false; TP3Reached=false; BEActive=false;
   LastSignalDir=dir;
   LastSignalScore=score;

   DrawTradeLevels();

   string direction=(dir==1?"LONG":"SHORT");
   string msg=direction+" (Sweep) | "+_Symbol+
      " | TF: "+EnumToString(_Period)+
      " | Score: "+DoubleToString(score,0)+
      " | Price: "+DoubleToString(ActiveEntry,_Digits)+
      " | SL: "+DoubleToString(ActiveSL,_Digits)+
      " | TP1: "+DoubleToString(ActiveTP1,_Digits)+
      " | TP2: "+DoubleToString(ActiveTP2,_Digits)+
      " | TP3: "+DoubleToString(ActiveTP3,_Digits)+
      " | R:R: "+DoubleToString(GetTP1(),1);

   if(InpEnableAlerts)
   {
      if(InpWebhookJSON)
      {
         string action=(dir==1?"buy":"sell");
         string json=StringFormat(
            "{\"action\":\"%s\",\"ticker\":\"%s\",\"price\":%s,\"score\":%s,\"sl\":%s,\"tp1\":%s,\"tp2\":%s,\"tp3\":%s,\"rr\":%s}",
            action,_Symbol,
            DoubleToString(ActiveEntry,_Digits),DoubleToString(score,0),
            DoubleToString(ActiveSL,_Digits),DoubleToString(ActiveTP1,_Digits),
            DoubleToString(ActiveTP2,_Digits),DoubleToString(ActiveTP3,_Digits),
            DoubleToString(GetTP1(),1));
         Alert(json);
         Print(json);
      }
      else
      {
         Alert(msg);
         Print(msg);
      }
   }
}
//+------------------------------------------------------------------+
void CloseSimulatedTrade(const string reason)
{
   bool win=TP1Reached;
   if(win) StatWins++; else StatLosses++;

   FormString+=(win?"▰":"▱");
   if(StringLen(FormString)>10)
      FormString=StringSubstr(FormString,StringLen(FormString)-10);

   if(InpEnableAlerts)
      Alert(reason+" | ",_Symbol," | Entry: ",DoubleToString(ActiveEntry,_Digits));

   ActiveDir=0;
   ActiveEntry=0; ActiveSL=0; ActiveTP1=0; ActiveTP2=0; ActiveTP3=0;
   EntryShift=-1;
   TP1Reached=false; TP2Reached=false; TP3Reached=false; BEActive=false;

   DeleteObjectSafe(PREFIX+"ENTRY");
   DeleteObjectSafe(PREFIX+"SL");
   DeleteObjectSafe(PREFIX+"TP1");
   DeleteObjectSafe(PREFIX+"TP2");
   DeleteObjectSafe(PREFIX+"TP3");
}
//+------------------------------------------------------------------+
void ManageTrade(const MqlRates &b)
{
   if(ActiveDir==0) return;

   bool slHit=false,tp1Hit=false,tp2Hit=false,tp3Hit=false;

   if(ActiveDir==1)
   {
      slHit=(b.low<=ActiveSL);
      tp1Hit=(b.high>=ActiveTP1);
      tp2Hit=(b.high>=ActiveTP2);
      tp3Hit=(b.high>=ActiveTP3);
   }
   else
   {
      slHit=(b.high>=ActiveSL);
      tp1Hit=(b.low<=ActiveTP1);
      tp2Hit=(b.low<=ActiveTP2);
      tp3Hit=(b.low<=ActiveTP3);
   }

   // Pine gives SL precedence if both SL and TP are touched in one bar.
   if(slHit)
   {
      bool be=BEActive;
      string reason=(be?"BE STOP-OUT":"SL HIT");
      CloseSimulatedTrade(reason);
      return;
   }

   if(tp1Hit && !TP1Reached)
   {
      TP1Reached=true;
      if(InpBreakEvenAfterTP1)
      {
         ActiveSL=ActiveEntry;
         BEActive=true;
         if(InpEnableAlerts && InpAlertTP)
            Alert("BREAK-EVEN | ",_Symbol," | SL moved to ",
                  DoubleToString(ActiveEntry,_Digits));
      }
      else if(InpEnableAlerts && InpAlertTP)
         Alert("TP1 HIT | ",_Symbol," | Price: ",DoubleToString(ActiveTP1,_Digits));
   }

   if(tp2Hit && !TP2Reached)
   {
      TP2Reached=true;
      if(InpEnableAlerts && InpAlertTP)
         Alert("TP2 HIT | ",_Symbol," | Price: ",DoubleToString(ActiveTP2,_Digits));
   }

   if(tp3Hit && !TP3Reached)
   {
      TP3Reached=true;
      if(InpEnableAlerts && InpAlertTP)
         Alert("TP3 HIT | ",_Symbol," | Price: ",DoubleToString(ActiveTP3,_Digits));
      CloseSimulatedTrade("TP3 HIT");
      return;
   }

   DrawTradeLevels();
}
//+------------------------------------------------------------------+
void DrawDashboard()
{
   if(!InpShowDashboard)
   {
      DeleteObjectSafe(PREFIX+"DASH");
      return;
   }

   string trend=LastSignalDir==1?"Bullish":LastSignalDir==-1?"Bearish":"Neutral";
   string signal=ActiveDir==1?"LONG":ActiveDir==-1?"SHORT":"Wait";
   string bias="—";

   double htfClose=HTFClosedClose();
   double ema=HTFEMA(1);
   if(InpUseHTFBias && htfClose>0 && ema>0)
      bias=htfClose>ema?"Bullish":"Bearish";
   else if(!InpUseHTFBias)
      bias="Off";

   int trades=StatWins+StatLosses;
   double wr=trades>0?(double)StatWins/trades*100.0:0.0;

   string text=
      "◆ MIRAGE · "+trend+"\n"+
      "────────────────────\n"+
      "Market\n"+
      "Trend       "+trend+"\n"+
      "HTF Bias    "+bias+"\n"+
      "Signal      "+signal+"\n"+
      "Last Sweep  "+(LastSignalDir==0?"—":(LastSignalDir==1?"Bullish ":"Bearish ")+DoubleToString(LastSignalScore,0))+"\n"+
      "Timeframe   "+EnumToString(_Period)+"\n"+
      "────────────────────\n"+
      "Trade\n";

   if(ActiveDir!=0)
   {
      text+="SL          "+DoubleToString(ActiveSL,_Digits)+(BEActive?" (BE)":"")+"\n"+
            "TP1         "+(TP1Reached?"✓ ":"")+DoubleToString(ActiveTP1,_Digits)+"\n"+
            "TP2         "+(TP2Reached?"✓ ":"")+DoubleToString(ActiveTP2,_Digits)+"\n"+
            "TP3         "+(TP3Reached?"✓ ":"")+DoubleToString(ActiveTP3,_Digits)+"\n"+
            "R:R (TP1)   "+DoubleToString(GetTP1(),1)+"R\n"+
            "SL Dist %   "+DoubleToString(MathAbs(ActiveEntry-ActiveSL)/ActiveEntry*100.0,2)+"%\n";
   }
   else
      text+="Flat · waiting for sweep\n";

   text+="────────────────────\n"+
         "Stats\n"+
         "Trades      "+IntegerToString(trades)+"\n"+
         "W / L       "+IntegerToString(StatWins)+" / "+IntegerToString(StatLosses)+"\n"+
         "Win rate    "+DoubleToString(wr,1)+"%\n"+
         "Form        "+(FormString==""?"—":FormString)+"\n"+
         "────────────────────\n"+
         "Mirage LSP · v1.3.1";

   DeleteObjectSafe(PREFIX+"DASH");
   ObjectCreate(0,PREFIX+"DASH",OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,PREFIX+"DASH",OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,PREFIX+"DASH",OBJPROP_XDISTANCE,15);
   ObjectSetInteger(0,PREFIX+"DASH",OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,PREFIX+"DASH",OBJPROP_COLOR,clrGainsboro);
   ObjectSetInteger(0,PREFIX+"DASH",OBJPROP_FONTSIZE,9);
   ObjectSetString(0,PREFIX+"DASH",OBJPROP_FONT,"Consolas");
   ObjectSetString(0,PREFIX+"DASH",OBJPROP_TEXT,text);
}
//+------------------------------------------------------------------+
void DrawWatermark()
{
   if(!InpShowWatermark)
   {
      DeleteObjectSafe(PREFIX+"WM");
      return;
   }

   DeleteObjectSafe(PREFIX+"WM");
   ObjectCreate(0,PREFIX+"WM",OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,PREFIX+"WM",OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,PREFIX+"WM",OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,PREFIX+"WM",OBJPROP_YDISTANCE,10);
   ObjectSetInteger(0,PREFIX+"WM",OBJPROP_COLOR,clrDimGray);
   ObjectSetInteger(0,PREFIX+"WM",OBJPROP_FONTSIZE,9);
   ObjectSetString(0,PREFIX+"WM",OBJPROP_TEXT,"WillyAlgoTrader");
}
//+------------------------------------------------------------------+
void ProcessClosedBar()
{
   int need=MathMax(500,InpSwingLength*3+InpMaxSweepDistance+InpVolumeMALength+20);

   MqlRates r[];
   ArraySetAsSeries(r,true);
   int total=CopyRates(_Symbol,_Period,0,need,r);
   if(total<InpSwingLength*2+20) return;

   // Work on the just-closed bar.
   const int sh=1;
   const MqlRates &b=r[sh];

   // Add confirmed major pivots.
   int pivotShift=InpSwingLength+1;
   if(pivotShift+InpSwingLength<total)
   {
      if(IsPivotHigh(r,pivotShift,InpSwingLength,total))
      {
         double p=r[pivotShift].high;
         bool duplicate=false;
         if(ArraySize(Highs)>0 && MathAbs(Highs[ArraySize(Highs)-1].price-p)<=_Point)
            duplicate=true;
         if(!duplicate) AddHigh(p,pivotShift);
      }

      if(IsPivotLow(r,pivotShift,InpSwingLength,total))
      {
         double p=r[pivotShift].low;
         bool duplicate=false;
         if(ArraySize(Lows)>0 && MathAbs(Lows[ArraySize(Lows)-1].price-p)<=_Point)
            duplicate=true;
         if(!duplicate) AddLow(p,pivotShift);
      }
   }

   // Equal highs/lows.
   double atr=ATR(1);
   if(InpShowEqualHL && atr>0)
   {
      if(ArraySize(Highs)>=2)
      {
         SwingPoint a=Highs[ArraySize(Highs)-2];
         SwingPoint z=Highs[ArraySize(Highs)-1];
         if(MathAbs(a.price-z.price)<=atr*InpEqualToleranceATR)
         {
            datetime t1=iTime(_Symbol,_Period,a.shift);
            datetime t2=iTime(_Symbol,_Period,z.shift);
            TrendLine(PREFIX+"EQH_"+IntegerToString((int)t2),t1,MathMax(a.price,z.price),
                      t2,MathMax(a.price,z.price),clrSlateGray,STYLE_SOLID,1);
            if(InpShowLiquidityLabels)
               TextObject(PREFIX+"EQHL_"+IntegerToString((int)t2),t2,MathMax(a.price,z.price),"EQH",clrSilver,8);
         }
      }

      if(ArraySize(Lows)>=2)
      {
         SwingPoint a=Lows[ArraySize(Lows)-2];
         SwingPoint z=Lows[ArraySize(Lows)-1];
         if(MathAbs(a.price-z.price)<=atr*InpEqualToleranceATR)
         {
            datetime t1=iTime(_Symbol,_Period,a.shift);
            datetime t2=iTime(_Symbol,_Period,z.shift);
            TrendLine(PREFIX+"EQL_"+IntegerToString((int)t2),t1,MathMin(a.price,z.price),
                      t2,MathMin(a.price,z.price),clrSlateGray,STYLE_SOLID,1);
            if(InpShowLiquidityLabels)
               TextObject(PREFIX+"EQLL_"+IntegerToString((int)t2),t2,MathMin(a.price,z.price),"EQL",clrSilver,8);
         }
      }
   }

   // HTF bias.
   double htfClose=HTFClosedClose();
   double htfEma=HTFEMA(1);
   bool htfBull=htfClose>0 && htfEma>0 && htfClose>htfEma;
   bool htfBear=htfClose>0 && htfEma>0 && htfClose<htfEma;
   double htfBullComp=!InpUseHTFBias?0.5:(htfBull?1.0:0.0);
   double htfBearComp=!InpUseHTFBias?0.5:(htfBear?1.0:0.0);

   double volComp=VolumeComponent(r,sh,total);

   bool bullSweep=false,bearSweep=false;
   double bullLvl=0,bearLvl=0;
   int bullLvlShift=-1,bearLvlShift=-1;

   // Major low sweeps.
   for(int j=ArraySize(Lows)-1;j>=0;j--)
   {
      if(Lows[j].used) continue;
      int age=Lows[j].shift-sh;
      if(age<0) continue;
      if(age>InpMaxSweepDistance)
      {
         Lows[j].used=true;
         continue;
      }

      double lvl=Lows[j].price;
      if(b.close<lvl)
         Lows[j].used=true;
      else if(b.low<lvl && b.close>lvl)
      {
         Lows[j].used=true;
         if(!bullSweep)
         {
            bullSweep=true;
            bullLvl=lvl;
            bullLvlShift=Lows[j].shift;
         }
      }
   }

   // Major high sweeps.
   for(int j=ArraySize(Highs)-1;j>=0;j--)
   {
      if(Highs[j].used) continue;
      int age=Highs[j].shift-sh;
      if(age<0) continue;
      if(age>InpMaxSweepDistance)
      {
         Highs[j].used=true;
         continue;
      }

      double lvl=Highs[j].price;
      if(b.close>lvl)
         Highs[j].used=true;
      else if(b.high>lvl && b.close<lvl)
      {
         Highs[j].used=true;
         if(!bearSweep)
         {
            bearSweep=true;
            bearLvl=lvl;
            bearLvlShift=Highs[j].shift;
         }
      }
   }

   double bullScore=bullSweep?SweepScore(1,bullLvl,b,atr,volComp,htfBullComp):0;
   double bearScore=bearSweep?SweepScore(-1,bearLvl,b,atr,volComp,htfBearComp):0;

   bool bullQ=bullSweep && bullScore>=InpMinSweepScore;
   bool bearQ=bearSweep && bearScore>=InpMinSweepScore;

   if(bullQ)
   {
      MarkSweep("BUY",b,bullLvl,bullScore,InpBullColor,bullLvlShift);
      PendingDir=1; PendingShift=sh; PendingLevel=bullLvl; PendingWick=b.low; PendingScore=bullScore;
      if(!InpRequireCHoCH) PendingShift=sh-InpConfirmWindow-1;
   }

   if(bearQ)
   {
      MarkSweep("SELL",b,bearLvl,bearScore,InpBearColor,bearLvlShift);
      PendingDir=-1; PendingShift=sh; PendingLevel=bearLvl; PendingWick=b.high; PendingScore=bearScore;
      if(!InpRequireCHoCH) PendingShift=sh-InpConfirmWindow-1;
   }

   // Minor structure confirmation.
   double minorHigh=0,minorLow=0;
   bool gotMH=GetMinorHigh(r,total,InpStructureLength,minorHigh);
   bool gotML=GetMinorLow(r,total,InpStructureLength,minorLow);

   bool fireBull=false,fireBear=false;
   double sigScore=0,sigWick=0,sigLvl=0;

   if(InpRequireCHoCH)
   {
      if(PendingDir!=0)
      {
         int age=PendingShift-sh;
         if(age>InpConfirmWindow)
            PendingDir=0;
      }

      if(PendingDir==1 && gotMH && b.close>minorHigh)
      {
         fireBull=true; sigScore=PendingScore; sigWick=PendingWick; sigLvl=PendingLevel;
         PendingDir=0;
      }
      else if(PendingDir==-1 && gotML && b.close<minorLow)
      {
         fireBear=true; sigScore=PendingScore; sigWick=PendingWick; sigLvl=PendingLevel;
         PendingDir=0;
      }
   }
   else
   {
      fireBull=bullQ; fireBear=bearQ;
      if(fireBull){sigScore=bullScore;sigWick=b.low;sigLvl=bullLvl;}
      if(fireBear){sigScore=bearScore;sigWick=b.high;sigLvl=bearLvl;}
   }

   // One simulated position at a time.
   if(ActiveDir==0 && atr>0 && !(fireBull && fireBear))
   {
      if(fireBull)
      {
         OpenSimulatedTrade(1,b.close,sigWick,atr,sigScore);
         if(InpShowSweptLevel) HLine(PREFIX+"LEVEL",sigLvl,clrSlateGray,STYLE_DOT,1);
      }
      else if(fireBear)
      {
         OpenSimulatedTrade(-1,b.close,sigWick,atr,sigScore);
         if(InpShowSweptLevel) HLine(PREFIX+"LEVEL",sigLvl,clrSlateGray,STYLE_DOT,1);
      }
   }

   ManageTrade(b);
   DrawDashboard();
   DrawWatermark();
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME,"Mirage Liquidity Sweep Pro [MT5]");

   ArrayResize(Highs,0);
   ArrayResize(Lows,0);

   ATRHandle=iATR(_Symbol,_Period,InpATRLength);
   if(ATRHandle==INVALID_HANDLE)
      return INIT_FAILED;

   HTFEMAHandle=iMA(_Symbol,InpHTF,InpHTFEMALength,0,MODE_EMA,PRICE_CLOSE);
   if(HTFEMAHandle==INVALID_HANDLE)
      return INIT_FAILED;

   DrawDashboard();
   DrawWatermark();
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(ATRHandle!=INVALID_HANDLE) IndicatorRelease(ATRHandle);
   if(HTFEMAHandle!=INVALID_HANDLE) IndicatorRelease(HTFEMAHandle);

   int total=ObjectsTotal(0,-1,-1);
   for(int i=total-1;i>=0;i--)
   {
      string n=ObjectName(0,i,-1,-1);
      if(StringFind(n,PREFIX)==0)
         ObjectDelete(0,n);
   }
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total<InpSwingLength*2+50)
      return rates_total;

   // Process only after a new chart bar, so signals are based on closed candles.
   if(IsNewBar())
      ProcessClosedBar();

   // Keep simulated trade levels/dashboard responsive on live ticks.
   if(ActiveDir!=0 && rates_total>1)
   {
      MqlRates rr[];
      ArraySetAsSeries(rr,true);
      if(CopyRates(_Symbol,_Period,1,1,rr)==1)
         ManageTrade(rr[0]);
   }

   DrawDashboard();
   DrawWatermark();

   return rates_total;
}
//+------------------------------------------------------------------+
