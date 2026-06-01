//+------------------------------------------------------------------+
#property version "ICHIMOKU PRO SCANNER V2"

//---------------- INPUTS ----------------
input int InpTenkan = 9;
input int InpKijun  = 26;
input int InpSenkouB= 52;

//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(10);
   Print("Scanner Ichimoku PRO V2 lancé");
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason){ EventKillTimer(); }
void OnTick(){}

//+------------------------------------------------------------------+
struct Data
{
   double close,prevClose;
   double tenkan,kijun,ssa,ssb;
   bool valid;

   string cloud;
};

//+------------------------------------------------------------------+
Data GetData(string symbol)
{
   Data d;
   d.valid=false;

   int h=iIchimoku(symbol,Period(),InpTenkan,InpKijun,InpSenkouB);
   if(h==INVALID_HANDLE) return d;

   double tenkan[],kijun[],ssa[],ssb[],close[];

   ArraySetAsSeries(tenkan,true);
   ArraySetAsSeries(kijun,true);
   ArraySetAsSeries(ssa,true);
   ArraySetAsSeries(ssb,true);
   ArraySetAsSeries(close,true);

   if(CopyBuffer(h,0,0,1,tenkan)<1 ||
      CopyBuffer(h,1,0,1,kijun)<1 ||
      CopyBuffer(h,2,0,1,ssa)<1 ||
      CopyBuffer(h,3,0,1,ssb)<1 ||
      CopyClose(symbol,Period(),0,2,close)<2)
   {
      IndicatorRelease(h);
      return d;
   }

   d.tenkan = tenkan[0];
   d.kijun  = kijun[0];
   d.ssa    = ssa[0];
   d.ssb    = ssb[0];
   d.close  = close[0];
   d.prevClose = close[1];

   d.valid=true;

   double top=MathMax(d.ssa,d.ssb);
   double bot=MathMin(d.ssa,d.ssb);

   if(d.close > top) d.cloud="AU-DESSUS";
   else if(d.close < bot) d.cloud="EN-DESSOUS";
   else d.cloud="DANS";

   IndicatorRelease(h);
   return d;
}

//+------------------------------------------------------------------+
// ✅ BREAKS
bool BreakUp(double prev,double now,double level)
{
   return (prev < level && now > level);
}

bool BreakDown(double prev,double now,double level)
{
   return (prev > level && now < level);
}

//+------------------------------------------------------------------+
// ✅ PULLBACK
bool PullbackBuy(Data &d)
{
   return (d.close > d.kijun && d.prevClose <= d.kijun);
}

bool PullbackSell(Data &d)
{
   return (d.close < d.kijun && d.prevClose >= d.kijun);
}

//+------------------------------------------------------------------+
void Scan()
{
   int total=SymbolsTotal(true);
   int count=0;

   for(int i=0;i<total;i++)
   {
      string symbol=SymbolName(i,true);

      Data d=GetData(symbol);
      if(!d.valid) continue;

      double cloudTop=MathMax(d.ssa,d.ssb);
      double cloudBot=MathMin(d.ssa,d.ssb);

      //========================
      // 🔥 BREAKOUT KUMO
      if(BreakUp(d.prevClose,d.close,cloudTop))
      {
         Print(symbol," BUY BREAKOUT KUMO");
         count++;
         continue;
      }

      if(BreakDown(d.prevClose,d.close,cloudBot))
      {
         Print(symbol," SELL BREAKOUT KUMO");
         count++;
         continue;
      }

      //========================
      // 🔥 BREAK KIJUN
      if(d.cloud=="AU-DESSUS" &&
         BreakUp(d.prevClose,d.close,d.kijun))
      {
         Print(symbol," BUY BREAK KIJUN");
         count++;
         continue;
      }

      if(d.cloud=="EN-DESSOUS" &&
         BreakDown(d.prevClose,d.close,d.kijun))
      {
         Print(symbol," SELL BREAK KIJUN");
         count++;
         continue;
      }

      //========================
      // 🔥 PULLBACK
      if(d.cloud=="AU-DESSUS" && PullbackBuy(d))
      {
         Print(symbol," BUY PULLBACK KIJUN");
         count++;
         continue;
      }

      if(d.cloud=="EN-DESSOUS" && PullbackSell(d))
      {
         Print(symbol," SELL PULLBACK KIJUN");
         count++;
         continue;
      }
   }

   Print("TOTAL SETUPS PRO: ",count);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   Scan();
}
//+------------------------------------------------------------------+
