//+------------------------------------------------------------------+
//| Mirage Liquidity Sweep Pro EA                                    |
//| MT5 Expert Advisor based on the Mirage LSP indicator logic       |
//|                                                                  |
//| Features                                                         |
//| - Liquidity sweep + optional CHoCH confirmation                 |
//| - Bullish / Bearish / Both direction filter                     |
//| - Conservative / Balanced / Aggressive / Scalping / Custom      |
//| - Default lot size: 0.01                                        |
//| - Default maximum concurrent trades: 1                          |
//| - TP1 / TP2 / TP3 targets                                       |
//| - Moves SL to entry when TP1 is reached                         |
//| - Real broker orders via CTrade                                  |
//| - Dashboard and chart levels                                     |
//+------------------------------------------------------------------+
#property copyright "WillyAlgoTrader / MT5 conversion"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>

CTrade trade;

//------------------------------------------------------------------
// Direction
//------------------------------------------------------------------
enum ENUM_MIRAGE_DIRECTION
{
   MIRAGE_BOTH = 0,
   MIRAGE_BULLISH_ONLY = 1,
   MIRAGE_BEARISH_ONLY = 2
};

//------------------------------------------------------------------
// Risk mode
//------------------------------------------------------------------
enum ENUM_MIRAGE_MODE
{
   MIRAGE_CONSERVATIVE = 0,
   MIRAGE_BALANCED = 1,
   MIRAGE_AGGRESSIVE = 2,
   MIRAGE_SCALPING = 3,
   MIRAGE_CUSTOM = 4
};

//------------------------------------------------------------------
// Main
//------------------------------------------------------------------
input group "=== Mirage Signal ==="
input int                     InpSwingLength       = 21;
input int                     InpMaxSweepDistance  = 80;
input int                     InpMinSweepScore     = 50;
input bool                    InpRequireCHoCH      = true;
input int                     InpStructureLength   = 8;
input int                     InpConfirmWindow     = 13;
input ENUM_MIRAGE_DIRECTION   InpTradeDirection    = MIRAGE_BOTH;

//------------------------------------------------------------------
// Filters
//------------------------------------------------------------------
input group "=== Filters ==="
input bool             InpUseVolume       = true;
input int              InpVolumeMALength  = 21;
input double           InpVolumeSpike     = 1.5;
input bool             InpUseHTFBias      = true;
input ENUM_TIMEFRAMES  InpHTF             = PERIOD_H4;
input int              InpHTFEMALength    = 50;

//------------------------------------------------------------------
// Trading
//------------------------------------------------------------------
input group "=== Trading ==="
input bool             InpEnableTrading   = true;
input double           InpLotSize        = 0.01;
input int              InpMaxConcurrent  = 1;
input ulong            InpMagicNumber    = 20260929;
input int              InpDeviationPoints = 20;

//------------------------------------------------------------------
// Mode / targets
//------------------------------------------------------------------
input group "=== Mode ==="
input ENUM_MIRAGE_MODE InpMode            = MIRAGE_CONSERVATIVE;
input int              InpATRLength       = 14;
input double           InpCustomSLBufferATR = 0.25;
input double           InpCustomTP1R       = 1.0;
input double           InpCustomTP2R       = 2.0;
input double           InpCustomTP3R       = 3.0;
input bool             InpBreakEvenAfterTP1 = true;

//------------------------------------------------------------------
// Chart
//------------------------------------------------------------------
input group "=== Chart ==="
input bool             InpShowDashboard   = true;
input bool             InpShowSweepMarks  = true;
input bool             InpShowSweepLines  = true;
input bool             InpShowSLTP        = true;
input bool             InpShowWatermark   = true;
input color            InpBullColor      = clrLimeGreen;
input color            InpBearColor      = clrTomato;

//------------------------------------------------------------------
// Alerts
//------------------------------------------------------------------
input group "=== Alerts ==="
input bool             InpEnableAlerts    = true;
input bool             InpAlertTP1       = true;
input bool             InpAlertTP2       = false;
input bool             InpAlertTP3       = true;

//------------------------------------------------------------------
// State
//------------------------------------------------------------------
struct SwingPoint
{
   double price;
   int    shift;
   bool   used;
};

SwingPoint Highs[];
SwingPoint Lows[];

int      PendingDir       = 0;
int      PendingShift     = -1;
double   PendingLevel     = 0.0;
double   PendingWick      = 0.0;
double   PendingScore     = 0.0;

int      LastSignalDir    = 0;
double   LastSignalScore  = 0.0;
string   LastSignalText   = "Waiting";

double   SignalEntry      = 0.0;
double   SignalSL         = 0.0;
double   SignalTP1        = 0.0;
double   SignalTP2        = 0.0;
double   SignalTP3        = 0.0;

bool     TP1Reached       = false;
bool     TP2Reached       = false;
bool     TP3Reached       = false;
bool     BEActive         = false;

int      StatWins         = 0;
int      StatLosses       = 0;
string   FormString       = "";

datetime LastBarTime      = 0;

int ATRHandle             = INVALID_HANDLE;
int HTFEMAHandle          = INVALID_HANDLE;

string PREFIX = "MIRAGE_EA_";

//------------------------------------------------------------------
// Mode parameters
//------------------------------------------------------------------
double GetRiskBuffer()
{
   switch(InpMode)
   {
      case MIRAGE_CONSERVATIVE: return 0.50;
      case MIRAGE_AGGRESSIVE:   return 0.15;
      case MIRAGE_SCALPING:     return 0.10;
      case MIRAGE_CUSTOM:       return InpCustomSLBufferATR;
      default:                  return 0.25;
   }
}

double GetTP1R()
{
   switch(InpMode)
   {
      case MIRAGE_CONSERVATIVE: return 1.0;
      case MIRAGE_AGGRESSIVE:   return 1.5;
      case MIRAGE_SCALPING:     return 0.8;
      case MIRAGE_CUSTOM:       return InpCustomTP1R;
      default:                  return 1.0;
   }
}

double GetTP2R()
{
   switch(InpMode)
   {
      case MIRAGE_CONSERVATIVE: return 2.0;
      case MIRAGE_AGGRESSIVE:   return 2.5;
      case MIRAGE_SCALPING:     return 1.5;
      case MIRAGE_CUSTOM:       return InpCustomTP2R;
      default:                  return 2.0;
   }
}

double GetTP3R()
{
   switch(InpMode)
   {
      case MIRAGE_CONSERVATIVE: return 4.0;
      case MIRAGE_AGGRESSIVE:   return 4.0;
      case MIRAGE_SCALPING:     return 2.0;
      case MIRAGE_CUSTOM:       return InpCustomTP3R;
      default:                  return 3.0;
   }
}

string ModeName()
{
   switch(InpMode)
   {
      case MIRAGE_CONSERVATIVE: return "Conservative";
      case MIRAGE_BALANCED:     return "Balanced";
      case MIRAGE_AGGRESSIVE:   return "Aggressive";
      case MIRAGE_SCALPING:     return "Scalping";
      default:                  return "Custom";
   }
}

string DirectionName()
{
   switch(InpTradeDirection)
   {
      case MIRAGE_BULLISH_ONLY: return "Bullish only";
      case MIRAGE_BEARISH_ONLY: return "Bearish only";
      default:                  return "Both";
   }
}

//------------------------------------------------------------------
// Helpers
//------------------------------------------------------------------
double ATR(const int shift)
{
   if(ATRHandle == INVALID_HANDLE)
      return 0.0;

   double b[];
   ArraySetAsSeries(b,true);

   if(CopyBuffer(ATRHandle,0,shift,1,b) != 1)
      return 0.0;

   return b[0];
}

double HTFEMA(const int shift)
{
   if(HTFEMAHandle == INVALID_HANDLE)
      return 0.0;

   double b[];
   ArraySetAsSeries(b,true);

   if(CopyBuffer(HTFEMAHandle,0,shift,1,b) != 1)
      return 0.0;

   return b[0];
}

double HTFClosedClose()
{
   MqlRates r[];
   ArraySetAsSeries(r,true);

   if(CopyRates(_Symbol,InpHTF,1,1,r) != 1)
      return 0.0;

   return r[0].close;
}

bool IsNewBar()
{
   datetime t=iTime(_Symbol,_Period,0);

   if(t==0)
      return false;

   if(t!=LastBarTime)
   {
      LastBarTime=t;
      return true;
   }

   return false;
}

bool IsPivotHigh(const MqlRates &r[],const int shift,const int len,const int total)
{
   if(shift-len<0 || shift+len>=total)
      return false;

   double p=r[shift].high;

   for(int i=1;i<=len;i++)
      if(r[shift-i].high>=p || r[shift+i].high>p)
         return false;

   return true;
}

bool IsPivotLow(const MqlRates &r[],const int shift,const int len,const int total)
{
   if(shift-len<0 || shift+len>=total)
      return false;

   double p=r[shift].low;

   for(int i=1;i<=len;i++)
      if(r[shift-i].low<=p || r[shift+i].low<p)
         return false;

   return true;
}

void AddHigh(const double price,const int shift)
{
   SwingPoint x;
   x.price=price;
   x.shift=shift;
   x.used=false;

   int n=ArraySize(Highs);
   ArrayResize(Highs,n+1);
   Highs[n]=x;

   if(ArraySize(Highs)>25)
   {
      for(int i=1;i<ArraySize(Highs);i++)
         Highs[i-1]=Highs[i];

      ArrayResize(Highs,25);
   }
}

void AddLow(const double price,const int shift)
{
   SwingPoint x;
   x.price=price;
   x.shift=shift;
   x.used=false;

   int n=ArraySize(Lows);
   ArrayResize(Lows,n+1);
   Lows[n]=x;

   if(ArraySize(Lows)>25)
   {
      for(int i=1;i<ArraySize(Lows);i++)
         Lows[i-1]=Lows[i];

      ArrayResize(Lows,25);
   }
}

double VolumeComponent(const MqlRates &r[],const int shift,const int total)
{
   if(!InpUseVolume)
      return 0.5;

   if(r[shift].tick_volume<=0)
      return 0.5;

   int len=MathMin(InpVolumeMALength,total-shift-1);

   if(len<2)
      return 0.5;

   double sum=0.0;

   for(int i=shift+1;i<=shift+len;i++)
      sum+=(double)r[i].tick_volume;

   double ma=sum/len;

   if(ma<=0)
      return 0.5;

   double ratio=(double)r[shift].tick_volume/ma;
   double denom=MathMax(InpVolumeSpike-1.0,0.1);

   return MathMin(MathMax((ratio-1.0)/denom,0.0),1.0);
}

double SweepScore(const int dir,
                  const double lvl,
                  const MqlRates &b,
                  const double atr,
                  const double volComp,
                  const double htfComp)
{
   if(atr<=0 || lvl<=0)
      return 0.0;

   double range=b.high-b.low;

   if(range<=0)
      return 0.0;

   double wick=(dir==1 ?
                MathMin(b.open,b.close)-b.low :
                b.high-MathMax(b.open,b.close));

   double reclaim=(dir==1 ?
                   b.close-lvl :
                   lvl-b.close);

   double closePos=(b.close-b.low)/range;
   double cpComp=(dir==1 ? closePos : 1.0-closePos);

   double wickComp=MathMin(MathMax(wick/atr,0.0),1.0);
   double rclComp=MathMin(MathMax(reclaim/atr,0.0),1.0);

   return (wickComp*0.30+
           rclComp*0.25+
           cpComp*0.20+
           volComp*0.15+
           htfComp*0.10)*100.0;
}

bool GetMinorHigh(const MqlRates &r[],
                  const int total,
                  const int len,
                  double &value)
{
   for(int s=len+1;s<total-len;s++)
   {
      if(IsPivotHigh(r,s,len,total))
      {
         value=r[s].high;
         return true;
      }
   }

   return false;
}

bool GetMinorLow(const MqlRates &r[],
                 const int total,
                 const int len,
                 double &value)
{
   for(int s=len+1;s<total-len;s++)
   {
      if(IsPivotLow(r,s,len,total))
      {
         value=r[s].low;
         return true;
      }
   }

   return false;
}

//------------------------------------------------------------------
// Chart objects
//------------------------------------------------------------------
void DeleteObjectSafe(const string name)
{
   if(ObjectFind(0,name)>=0)
      ObjectDelete(0,name);
}

void HLine(const string name,
           const double price,
           const color clr,
           const ENUM_LINE_STYLE style=STYLE_DOT,
           const int width=1)
{
   DeleteObjectSafe(name);

   if(!ObjectCreate(0,name,OBJ_HLINE,0,0,price))
      return;

   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
}

void TrendLine(const string name,
               const datetime t1,
               const double p1,
               const datetime t2,
               const double p2,
               const color clr)
{
   DeleteObjectSafe(name);

   if(!ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2))
      return;

   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
}

void TextObject(const string name,
                const datetime t,
                const double price,
                const string text,
                const color clr,
                const int size=9)
{
   DeleteObjectSafe(name);

   if(!ObjectCreate(0,name,OBJ_TEXT,0,t,price))
      return;

   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT);
}

void MarkSweep(const string side,
               const MqlRates &b,
               const double level,
               const double score,
               const color clr,
               const int levelShift)
{
   if(InpShowSweepMarks)
   {
      string n=PREFIX+"SWEEP_"+side+"_"+IntegerToString((int)b.time);

      double p=(side=="BUY" ? b.low : b.high);

      TextObject(n,b.time,p,"X",clr,12);
   }

   if(InpShowSweepLines)
   {
      datetime t1=iTime(_Symbol,_Period,levelShift);
      datetime t2=iTime(_Symbol,_Period,0);

      TrendLine(PREFIX+"SWEPT_"+IntegerToString((int)b.time),
                t1,level,t2,level,clr);
   }
}

void DrawTradeLevels()
{
   DeleteObjectSafe(PREFIX+"ENTRY");
   DeleteObjectSafe(PREFIX+"SL");
   DeleteObjectSafe(PREFIX+"TP1");
   DeleteObjectSafe(PREFIX+"TP2");
   DeleteObjectSafe(PREFIX+"TP3");

   if(!InpShowSLTP || !PositionExists())
      return;

   HLine(PREFIX+"ENTRY",
         SignalEntry,
         clrSlateGray,
         STYLE_DOT,
         1);

   HLine(PREFIX+"SL",
         CurrentPositionSL(),
         BEActive ? clrOrange : clrRed,
         STYLE_SOLID,
         2);

   HLine(PREFIX+"TP1",
         SignalTP1,
         TP1Reached ? clrTeal : clrGreen,
         TP1Reached ? STYLE_SOLID : STYLE_DASH,
         1);

   HLine(PREFIX+"TP2",
         SignalTP2,
         TP2Reached ? clrTeal : clrGreen,
         TP2Reached ? STYLE_SOLID : STYLE_DASH,
         1);

   HLine(PREFIX+"TP3",
         SignalTP3,
         TP3Reached ? clrTeal : clrGreen,
         TP3Reached ? STYLE_SOLID : STYLE_DASH,
         1);
}

//------------------------------------------------------------------
// Position helpers
//------------------------------------------------------------------
int CountOurPositions()
{
   int count=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol=PositionGetString(POSITION_SYMBOL);
      ulong magic=(ulong)PositionGetInteger(POSITION_MAGIC);

      if(symbol==_Symbol && magic==InpMagicNumber)
         count++;
   }

   return count;
}

bool PositionExists()
{
   return CountOurPositions()>0;
}

bool GetOurPosition(ulong &ticket)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);

      if(t==0)
         continue;

      if(!PositionSelectByTicket(t))
         continue;

      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)
      {
         ticket=t;
         return true;
      }
   }

   ticket=0;
   return false;
}

double CurrentPositionSL()
{
   ulong ticket;

   if(!GetOurPosition(ticket))
      return SignalSL;

   if(!PositionSelectByTicket(ticket))
      return SignalSL;

   return PositionGetDouble(POSITION_SL);
}

int PositionDirection()
{
   ulong ticket;

   if(!GetOurPosition(ticket))
      return 0;

   if(!PositionSelectByTicket(ticket))
      return 0;

   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   if(type==POSITION_TYPE_BUY)
      return 1;

   if(type==POSITION_TYPE_SELL)
      return -1;

   return 0;
}

bool DirectionAllowed(const int dir)
{
   if(InpTradeDirection==MIRAGE_BOTH)
      return true;

   if(InpTradeDirection==MIRAGE_BULLISH_ONLY && dir==1)
      return true;

   if(InpTradeDirection==MIRAGE_BEARISH_ONLY && dir==-1)
      return true;

   return false;
}

double NormalizeVolume(const double requested)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(step<=0)
      step=minLot;

   double lot=MathMax(minLot,MathMin(maxLot,requested));

   lot=MathFloor(lot/step+0.0000001)*step;

   int digits=0;
   double s=step;

   while(digits<8 && MathAbs(s-MathRound(s))>0.00000001)
   {
      s*=10.0;
      digits++;
   }

   return NormalizeDouble(lot,digits);
}

bool StopsAreValid(const int dir,
                   const double entry,
                   const double sl,
                   const double tp)
{
   int stopsLevel=(int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance=stopsLevel*_Point;

   if(minDistance<=0)
      return true;

   if(dir==1)
      return (entry-sl>=minDistance && tp-entry>=minDistance);

   return (sl-entry>=minDistance && entry-tp>=minDistance);
}

//------------------------------------------------------------------
// Trade open
//------------------------------------------------------------------
bool OpenTrade(const int dir,
               const double entry,
               const double wick,
               const double atr,
               const double score)
{
   if(!InpEnableTrading)
      return false;

   if(!DirectionAllowed(dir))
      return false;

   if(CountOurPositions()>=InpMaxConcurrent)
      return false;

   if(atr<=0)
      return false;

   double buffer=GetRiskBuffer();
   double dist=0.0;

   SignalEntry=entry;

   if(dir==1)
   {
      SignalSL=wick-atr*buffer;
      dist=MathAbs(SignalEntry-SignalSL);

      if(dist<atr*0.5)
      {
         SignalSL=SignalEntry-atr*0.5;
         dist=atr*0.5;
      }

      SignalTP1=SignalEntry+dist*GetTP1R();
      SignalTP2=SignalEntry+dist*GetTP2R();
      SignalTP3=SignalEntry+dist*GetTP3R();
   }
   else
   {
      SignalSL=wick+atr*buffer;
      dist=MathAbs(SignalSL-SignalEntry);

      if(dist<atr*0.5)
      {
         SignalSL=SignalEntry+atr*0.5;
         dist=atr*0.5;
      }

      SignalTP1=SignalEntry-dist*GetTP1R();
      SignalTP2=SignalEntry-dist*GetTP2R();
      SignalTP3=SignalEntry-dist*GetTP3R();
   }

   SignalEntry=NormalizeDouble(SignalEntry,_Digits);
   SignalSL=NormalizeDouble(SignalSL,_Digits);
   SignalTP1=NormalizeDouble(SignalTP1,_Digits);
   SignalTP2=NormalizeDouble(SignalTP2,_Digits);
   SignalTP3=NormalizeDouble(SignalTP3,_Digits);

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double actualEntry=(dir==1 ? ask : bid);

   if(dir==1)
   {
      if(SignalSL>=actualEntry || SignalTP3<=actualEntry)
         return false;
   }
   else
   {
      if(SignalSL<=actualEntry || SignalTP3>=actualEntry)
         return false;
   }

   if(!StopsAreValid(dir,actualEntry,SignalSL,SignalTP3))
      return false;

   double lots=NormalizeVolume(InpLotSize);

   if(lots<=0)
      return false;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   string comment=(dir==1 ?
                   "Mirage LSP LONG" :
                   "Mirage LSP SHORT");

   bool result=false;

   if(dir==1)
      result=trade.Buy(lots,_Symbol,0.0,SignalSL,SignalTP3,comment);
   else
      result=trade.Sell(lots,_Symbol,0.0,SignalSL,SignalTP3,comment);

   if(!result)
   {
      Print("Mirage EA order failed. Retcode=",
            trade.ResultRetcode(),
            " Description=",
            trade.ResultRetcodeDescription());

      return false;
   }

   LastSignalDir=dir;
   LastSignalScore=score;
   LastSignalText=(dir==1 ? "LONG OPEN" : "SHORT OPEN");
   TP1Reached=false;
   TP2Reached=false;
   TP3Reached=false;
   BEActive=false;

   SignalEntry=actualEntry;
   SignalEntry=NormalizeDouble(SignalEntry,_Digits);

   if(InpEnableAlerts)
   {
      string msg=StringFormat(
         "MIRAGE %s | %s | %s | Score %.0f | Entry %s | SL %s | TP1 %s | TP2 %s | TP3 %s",
         (dir==1 ? "LONG" : "SHORT"),
         _Symbol,
         ModeName(),
         score,
         DoubleToString(SignalEntry,_Digits),
         DoubleToString(SignalSL,_Digits),
         DoubleToString(SignalTP1,_Digits),
         DoubleToString(SignalTP2,_Digits),
         DoubleToString(SignalTP3,_Digits));

      Alert(msg);
      Print(msg);
   }

   DrawTradeLevels();
   ChartRedraw(0);

   return true;
}

//------------------------------------------------------------------
// Break-even / TP management
//------------------------------------------------------------------
void ManageOpenPosition()
{
   ulong ticket;

   if(!GetOurPosition(ticket))
      return;

   if(!PositionSelectByTicket(ticket))
      return;

   ENUM_POSITION_TYPE type=
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   double currentPrice=(type==POSITION_TYPE_BUY ? bid : ask);

   if(!TP1Reached)
   {
      bool hit=(type==POSITION_TYPE_BUY ?
                currentPrice>=SignalTP1 :
                currentPrice<=SignalTP1);

      if(hit)
      {
         TP1Reached=true;

         if(InpBreakEvenAfterTP1)
         {
            double be=NormalizeDouble(SignalEntry,_Digits);
            double currentTP=PositionGetDouble(POSITION_TP);

            trade.SetExpertMagicNumber(InpMagicNumber);

            if(trade.PositionModify(_Symbol,be,currentTP))
            {
               BEActive=true;

               if(InpEnableAlerts && InpAlertTP1)
               {
                  Alert("MIRAGE TP1 HIT | ",
                        _Symbol,
                        " | Stop Loss moved to ENTRY ",
                        DoubleToString(be,_Digits));
               }
            }
            else
            {
               Print("Mirage EA failed to move SL to breakeven. Retcode=",
                     trade.ResultRetcode(),
                     " Description=",
                     trade.ResultRetcodeDescription());
            }
         }
         else if(InpEnableAlerts && InpAlertTP1)
         {
            Alert("MIRAGE TP1 HIT | ",_Symbol);
         }
      }
   }

   if(!TP2Reached)
   {
      bool hit=(type==POSITION_TYPE_BUY ?
                currentPrice>=SignalTP2 :
                currentPrice<=SignalTP2);

      if(hit)
      {
         TP2Reached=true;

         if(InpEnableAlerts && InpAlertTP2)
            Alert("MIRAGE TP2 HIT | ",_Symbol);
      }
   }

   if(!TP3Reached)
   {
      bool hit=(type==POSITION_TYPE_BUY ?
                currentPrice>=SignalTP3 :
                currentPrice<=SignalTP3);

      if(hit)
      {
         TP3Reached=true;

         if(InpEnableAlerts && InpAlertTP3)
            Alert("MIRAGE TP3 HIT | ",_Symbol);
      }
   }

   DrawTradeLevels();
}

//------------------------------------------------------------------
// Dashboard
//------------------------------------------------------------------
void DrawDashboard()
{
   if(!InpShowDashboard)
   {
      DeleteObjectSafe(PREFIX+"DASH");
      return;
   }

   double htfClose=HTFClosedClose();
   double htfEma=HTFEMA(1);

   string bias="Off";

   if(InpUseHTFBias)
   {
      if(htfClose>0 && htfEma>0)
      {
         if(htfClose>htfEma)
            bias="Bullish";
         else if(htfClose<htfEma)
            bias="Bearish";
         else
            bias="Neutral";
      }
      else
         bias="Waiting";
   }

   string signal=
      (LastSignalDir==1 ? "LONG" :
       LastSignalDir==-1 ? "SHORT" : "WAIT");

   string trading=
      InpEnableTrading ? "AUTO TRADING ON" : "SIGNALS ONLY";

   int openCount=CountOurPositions();

   string text=
      "◆ MIRAGE LIQUIDITY SWEEP PRO EA\n"+
      "────────────────────────────\n"+
      "Mode        "+ModeName()+"\n"+
      "Direction   "+DirectionName()+"\n"+
      "Trading     "+trading+"\n"+
      "Lots        "+DoubleToString(InpLotSize,2)+"\n"+
      "Open        "+IntegerToString(openCount)+
                    " / "+IntegerToString(InpMaxConcurrent)+"\n"+
      "────────────────────────────\n"+
      "Market\n"+
      "HTF Bias    "+bias+"\n"+
      "Signal      "+signal+"\n"+
      "Last Score  "+DoubleToString(LastSignalScore,0)+"\n"+
      "Status      "+LastSignalText+"\n"+
      "Timeframe   "+EnumToString(_Period)+"\n"+
      "────────────────────────────\n";

   if(PositionExists())
   {
      text+="Trade\n"+
            "Entry       "+DoubleToString(SignalEntry,_Digits)+"\n"+
            "SL          "+DoubleToString(CurrentPositionSL(),_Digits)+
                          (BEActive ? "  (BE)" : "")+"\n"+
            "TP1         "+(TP1Reached ? "✓ " : "")+
                          DoubleToString(SignalTP1,_Digits)+"\n"+
            "TP2         "+(TP2Reached ? "✓ " : "")+
                          DoubleToString(SignalTP2,_Digits)+"\n"+
            "TP3         "+(TP3Reached ? "✓ " : "")+
                          DoubleToString(SignalTP3,_Digits)+"\n"+
            "R:R TP1     "+DoubleToString(GetTP1R(),1)+"R\n";
   }
   else
   {
      text+="Trade\n"+
            "Status      No open Mirage trade\n";
   }

   text+="────────────────────────────\n"+
         "Risk control: TP1 → SL = ENTRY\n"+
         "Magic       "+IntegerToString((int)InpMagicNumber);

   DeleteObjectSafe(PREFIX+"DASH");

   if(!ObjectCreate(0,PREFIX+"DASH",OBJ_LABEL,0,0,0))
      return;

   ObjectSetInteger(0,PREFIX+"DASH",OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,PREFIX+"DASH",OBJPROP_XDISTANCE,15);
   ObjectSetInteger(0,PREFIX+"DASH",OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,PREFIX+"DASH",OBJPROP_COLOR,clrGainsboro);
   ObjectSetInteger(0,PREFIX+"DASH",OBJPROP_FONTSIZE,9);
   ObjectSetString(0,PREFIX+"DASH",OBJPROP_FONT,"Consolas");
   ObjectSetString(0,PREFIX+"DASH",OBJPROP_TEXT,text);
}

void DrawWatermark()
{
   if(!InpShowWatermark)
   {
      DeleteObjectSafe(PREFIX+"WM");
      return;
   }

   DeleteObjectSafe(PREFIX+"WM");

   if(!ObjectCreate(0,PREFIX+"WM",OBJ_LABEL,0,0,0))
      return;

   ObjectSetInteger(0,PREFIX+"WM",OBJPROP_CORNER,CORNER_LEFT_LOWER);
   ObjectSetInteger(0,PREFIX+"WM",OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,PREFIX+"WM",OBJPROP_YDISTANCE,10);
   ObjectSetInteger(0,PREFIX+"WM",OBJPROP_COLOR,clrDimGray);
   ObjectSetInteger(0,PREFIX+"WM",OBJPROP_FONTSIZE,9);
   ObjectSetString(0,PREFIX+"WM",OBJPROP_TEXT,
                   "Mirage Liquidity Sweep Pro EA");
}

//------------------------------------------------------------------
// Signal processing
//------------------------------------------------------------------
void ProcessClosedBar()
{
   int need=MathMax(500,
                    InpSwingLength*3+
                    InpMaxSweepDistance+
                    InpVolumeMALength+
                    20);

   MqlRates r[];
   ArraySetAsSeries(r,true);

   int total=CopyRates(_Symbol,_Period,0,need,r);

   if(total<InpSwingLength*2+20)
      return;

   const int sh=1;
   const MqlRates &b=r[sh];

   int pivotShift=InpSwingLength+1;

   if(pivotShift+InpSwingLength<total)
   {
      if(IsPivotHigh(r,pivotShift,InpSwingLength,total))
      {
         double p=r[pivotShift].high;
         bool duplicate=false;

         if(ArraySize(Highs)>0 &&
            MathAbs(Highs[ArraySize(Highs)-1].price-p)<=_Point)
            duplicate=true;

         if(!duplicate)
            AddHigh(p,pivotShift);
      }

      if(IsPivotLow(r,pivotShift,InpSwingLength,total))
      {
         double p=r[pivotShift].low;
         bool duplicate=false;

         if(ArraySize(Lows)>0 &&
            MathAbs(Lows[ArraySize(Lows)-1].price-p)<=_Point)
            duplicate=true;

         if(!duplicate)
            AddLow(p,pivotShift);
      }
   }

   double atr=ATR(1);

   double htfClose=HTFClosedClose();
   double htfEma=HTFEMA(1);

   bool htfBull=(htfClose>0 &&
                 htfEma>0 &&
                 htfClose>htfEma);

   bool htfBear=(htfClose>0 &&
                 htfEma>0 &&
                 htfClose<htfEma);

   double htfBullComp=!InpUseHTFBias ? 0.5 :
                      (htfBull ? 1.0 : 0.0);

   double htfBearComp=!InpUseHTFBias ? 0.5 :
                      (htfBear ? 1.0 : 0.0);

   double volComp=VolumeComponent(r,sh,total);

   bool bullSweep=false;
   bool bearSweep=false;

   double bullLvl=0.0;
   double bearLvl=0.0;

   int bullLvlShift=-1;
   int bearLvlShift=-1;

   // Bullish sweep: price trades below a low then closes back above it.
   for(int j=ArraySize(Lows)-1;j>=0;j--)
   {
      if(Lows[j].used)
         continue;

      int age=Lows[j].shift-sh;

      if(age<0)
         continue;

      if(age>InpMaxSweepDistance)
      {
         Lows[j].used=true;
         continue;
      }

      double lvl=Lows[j].price;

      if(b.close<lvl)
      {
         Lows[j].used=true;
      }
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

   // Bearish sweep: price trades above a high then closes back below it.
   for(int j=ArraySize(Highs)-1;j>=0;j--)
   {
      if(Highs[j].used)
         continue;

      int age=Highs[j].shift-sh;

      if(age<0)
         continue;

      if(age>InpMaxSweepDistance)
      {
         Highs[j].used=true;
         continue;
      }

      double lvl=Highs[j].price;

      if(b.close>lvl)
      {
         Highs[j].used=true;
      }
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

   double bullScore=
      bullSweep ?
      SweepScore(1,bullLvl,b,atr,volComp,htfBullComp) :
      0.0;

   double bearScore=
      bearSweep ?
      SweepScore(-1,bearLvl,b,atr,volComp,htfBearComp) :
      0.0;

   bool bullQ=bullSweep && bullScore>=InpMinSweepScore;
   bool bearQ=bearSweep && bearScore>=InpMinSweepScore;

   if(bullQ)
   {
      MarkSweep("BUY",
                b,
                bullLvl,
                bullScore,
                InpBullColor,
                bullLvlShift);

      PendingDir=1;
      PendingShift=sh;
      PendingLevel=bullLvl;
      PendingWick=b.low;
      PendingScore=bullScore;

      LastSignalText="Bullish sweep found";

      if(!InpRequireCHoCH)
         PendingShift=sh-InpConfirmWindow-1;
   }

   if(bearQ)
   {
      MarkSweep("SELL",
                b,
                bearLvl,
                bearScore,
                InpBearColor,
                bearLvlShift);

      PendingDir=-1;
      PendingShift=sh;
      PendingLevel=bearLvl;
      PendingWick=b.high;
      PendingScore=bearScore;

      LastSignalText="Bearish sweep found";

      if(!InpRequireCHoCH)
         PendingShift=sh-InpConfirmWindow-1;
   }

   double minorHigh=0.0;
   double minorLow=0.0;

   bool gotMH=GetMinorHigh(r,total,InpStructureLength,minorHigh);
   bool gotML=GetMinorLow(r,total,InpStructureLength,minorLow);

   bool fireBull=false;
   bool fireBear=false;

   double sigScore=0.0;
   double sigWick=0.0;
   double sigLvl=0.0;

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
         fireBull=true;
         sigScore=PendingScore;
         sigWick=PendingWick;
         sigLvl=PendingLevel;
         PendingDir=0;
      }
      else if(PendingDir==-1 && gotML && b.close<minorLow)
      {
         fireBear=true;
         sigScore=PendingScore;
         sigWick=PendingWick;
         sigLvl=PendingLevel;
         PendingDir=0;
      }
   }
   else
   {
      fireBull=bullQ;
      fireBear=bearQ;

      if(fireBull)
      {
         sigScore=bullScore;
         sigWick=b.low;
         sigLvl=bullLvl;
      }

      if(fireBear)
      {
         sigScore=bearScore;
         sigWick=b.high;
         sigLvl=bearLvl;
      }
   }

   if(fireBull && !DirectionAllowed(1))
      fireBull=false;

   if(fireBear && !DirectionAllowed(-1))
      fireBear=false;

   if(fireBull && fireBear)
   {
      LastSignalText="Conflicting signal";
      return;
   }

   if(fireBull)
   {
      LastSignalDir=1;
      LastSignalScore=sigScore;
      LastSignalText="Bullish LONG setup";

      if(InpShowSLTP)
         HLine(PREFIX+"LEVEL",sigLvl,clrSlateGray,STYLE_DOT,1);

      if(!PositionExists())
         OpenTrade(1,b.close,sigWick,atr,sigScore);
   }
   else if(fireBear)
   {
      LastSignalDir=-1;
      LastSignalScore=sigScore;
      LastSignalText="Bearish SHORT setup";

      if(InpShowSLTP)
         HLine(PREFIX+"LEVEL",sigLvl,clrSlateGray,STYLE_DOT,1);

      if(!PositionExists())
         OpenTrade(-1,b.close,sigWick,atr,sigScore);
   }

   DrawDashboard();
   DrawWatermark();
   ChartRedraw(0);
}

//------------------------------------------------------------------
// Lifecycle
//------------------------------------------------------------------
int OnInit()
{
   ArrayResize(Highs,0);
   ArrayResize(Lows,0);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   ATRHandle=iATR(_Symbol,_Period,InpATRLength);

   if(ATRHandle==INVALID_HANDLE)
      return INIT_FAILED;

   HTFEMAHandle=iMA(_Symbol,
                    InpHTF,
                    InpHTFEMALength,
                    0,
                    MODE_EMA,
                    PRICE_CLOSE);

   if(HTFEMAHandle==INVALID_HANDLE)
      return INIT_FAILED;

   DrawDashboard();
   DrawWatermark();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(ATRHandle!=INVALID_HANDLE)
      IndicatorRelease(ATRHandle);

   if(HTFEMAHandle!=INVALID_HANDLE)
      IndicatorRelease(HTFEMAHandle);

   int total=ObjectsTotal(0,-1,-1);

   for(int i=total-1;i>=0;i--)
   {
      string n=ObjectName(0,i,-1,-1);

      if(StringFind(n,PREFIX)==0)
         ObjectDelete(0,n);
   }

   ChartRedraw(0);
}

void OnTick()
{
   if(IsNewBar())
      ProcessClosedBar();

   ManageOpenPosition();
   DrawDashboard();
   DrawWatermark();
}
