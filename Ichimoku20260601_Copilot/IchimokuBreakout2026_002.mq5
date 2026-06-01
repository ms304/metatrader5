//+------------------------------------------------------------------+
#property version "1.000"

//---------------- INPUTS ----------------
input int InpTenkan = 9;
input int InpKijun  = 26;
input int InpSenkouB= 52;

//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(30);
   Print("Scanner Ichimoku PRO lancé");
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

   IndicatorRelease(h);
   return d;
}

//+------------------------------------------------------------------+
bool BreakUp(double prev,double now,double level)
{
   return (prev < level && now > level);
}

bool BreakDown(double prev,double now,double level)
{
   return (prev > level && now < level);
}

//+------------------------------------------------------------------+
bool PullbackBuy(Data &d)
{
   return (d.prevClose <= d.kijun && d.close > d.kijun);
}

bool PullbackSell(Data &d)
{
   return (d.prevClose >= d.kijun && d.close < d.kijun);
}

//+------------------------------------------------------------------+
void Scan()
{
   int total=SymbolsTotal(true);

   string kumoBuy="", kumoSell="";
   string kijunBuy="", kijunSell="";
   string pullBuy="", pullSell="";

   int cKumoBuy=0, cKumoSell=0;
   int cKijunBuy=0, cKijunSell=0;
   int cPullBuy=0, cPullSell=0;

   for(int i=0;i<total;i++)
   {
      string symbol = SymbolName(i,true);

      Data d = GetData(symbol);
      if(!d.valid) continue;

      double cloudTop=MathMax(d.ssa,d.ssb);
      double cloudBot=MathMin(d.ssa,d.ssb);

      if(BreakUp(d.prevClose,d.close,cloudTop))
      {
         kumoBuy += symbol + ", ";
         cKumoBuy++;
         continue;
      }

      if(BreakDown(d.prevClose,d.close,cloudBot))
      {
         kumoSell += symbol + ", ";
         cKumoSell++;
         continue;
      }

      if(d.close > cloudTop &&
         BreakUp(d.prevClose,d.close,d.kijun))
      {
         kijunBuy += symbol + ", ";
         cKijunBuy++;
         continue;
      }

      if(d.close < cloudBot &&
         BreakDown(d.prevClose,d.close,d.kijun))
      {
         kijunSell += symbol + ", ";
         cKijunSell++;
         continue;
      }

      if(d.close > cloudTop && PullbackBuy(d))
      {
         pullBuy += symbol + ", ";
         cPullBuy++;
         continue;
      }

      if(d.close < cloudBot && PullbackSell(d))
      {
         pullSell += symbol + ", ";
         cPullSell++;
         continue;
      }
   }

   string dash="=== ICHIMOKU PRO DASHBOARD ===\n\n";

   dash += "BREAKOUT KUMO\n";
   dash += "BUY  ("+IntegerToString(cKumoBuy)+"): "+kumoBuy+"\n";
   dash += "SELL ("+IntegerToString(cKumoSell)+"): "+kumoSell+"\n\n";

   dash += "BREAK KIJUN\n";
   dash += "BUY  ("+IntegerToString(cKijunBuy)+"): "+kijunBuy+"\n";
   dash += "SELL ("+IntegerToString(cKijunSell)+"): "+kijunSell+"\n\n";

   dash += "PULLBACK\n";
   dash += "BUY  ("+IntegerToString(cPullBuy)+"): "+pullBuy+"\n";
   dash += "SELL ("+IntegerToString(cPullSell)+"): "+pullSell+"\n";

   Comment(dash);
   Print(dash);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   Scan();
}
//+------------------------------------------------------------------+
