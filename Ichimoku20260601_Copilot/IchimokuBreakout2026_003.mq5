//+------------------------------------------------------------------+
#property version "1.000"

//---------------- INPUTS ----------------
input int InpTenkan = 9;
input int InpKijun  = 26;
input int InpSenkouB= 52;

//================ PERSISTANCE =================
string lastSignal[500];
int persistCount[500];

//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(10);
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}
//+------------------------------------------------------------------+
void OnTick(){}

//+------------------------------------------------------------------+
struct Data
{
   double close,prevClose;
   double kijun,ssa,ssb;
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

   double kijun[],ssa[],ssb[],close[];

   ArraySetAsSeries(kijun,true);
   ArraySetAsSeries(ssa,true);
   ArraySetAsSeries(ssb,true);
   ArraySetAsSeries(close,true);

   if(CopyBuffer(h,1,0,1,kijun)<1 ||
      CopyBuffer(h,2,0,1,ssa)<1 ||
      CopyBuffer(h,3,0,1,ssb)<1 ||
      CopyClose(symbol,Period(),0,2,close)<2)
   {
      IndicatorRelease(h);
      return d;
   }

   d.kijun=kijun[0];
   d.ssa=ssa[0];
   d.ssb=ssb[0];
   d.close=close[0];
   d.prevClose=close[1];

   double top=MathMax(d.ssa,d.ssb);
   double bot=MathMin(d.ssa,d.ssb);

   if(d.close>top) d.cloud="AU-DESSUS";
   else if(d.close<bot) d.cloud="EN-DESSOUS";
   else d.cloud="DANS";

   d.valid=true;
   IndicatorRelease(h);
   return d;
}

//+------------------------------------------------------------------+
bool BreakUp(double prev,double now,double level)
{
   return (prev<level && now>level);
}

bool BreakDown(double prev,double now,double level)
{
   return (prev>level && now<level);
}

bool PullbackBuy(Data &d)
{
   return (d.close>d.kijun && d.prevClose<=d.kijun);
}

bool PullbackSell(Data &d)
{
   return (d.close<d.kijun && d.prevClose>=d.kijun);
}

//+------------------------------------------------------------------+
void UpdatePersistence(int i,string signal)
{
   if(lastSignal[i]==signal)
      persistCount[i]++;
   else
   {
      lastSignal[i]=signal;
      persistCount[i]=1;
   }
}

//+------------------------------------------------------------------+
void DrawDashboard(string &lines[], int total)
{
   string bg="BG";
   ObjectDelete(0,bg);

   ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,650);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,400);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrBlack);

   for(int i=0;i<50;i++)
      ObjectDelete(0,"TXT_"+IntegerToString(i));

   for(int i=0;i<total;i++)
   {
      string name="TXT_"+IntegerToString(i);

      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,20);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,30 + i*15);

      ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
      ObjectSetString(0,name,OBJPROP_FONT,"Consolas");

      ObjectSetString(0,name,OBJPROP_TEXT,lines[i]);
   }
}

//+------------------------------------------------------------------+
void Scan()
{
   string lines[200];
   int idx=0;

   int total=SymbolsTotal(true);
   int count=0;

   lines[idx++]="ICHIMOKU PRO SCANNER";
   lines[idx++]="---------------------";

   for(int i=0;i<total;i++)
   {
      string symbol=SymbolName(i,true);
      Data d=GetData(symbol);
      if(!d.valid) continue;

      double top=MathMax(d.ssa,d.ssb);
      double bot=MathMin(d.ssa,d.ssb);

      string signal="";

      if(BreakUp(d.prevClose,d.close,top))
         signal="BUY KUMO";
      else if(BreakDown(d.prevClose,d.close,bot))
         signal="SELL KUMO";
      else if(d.cloud=="AU-DESSUS" && BreakUp(d.prevClose,d.close,d.kijun))
         signal="BUY KIJUN";
      else if(d.cloud=="EN-DESSOUS" && BreakDown(d.prevClose,d.close,d.kijun))
         signal="SELL KIJUN";
      else if(d.cloud=="AU-DESSUS" && PullbackBuy(d))
         signal="BUY PULLBACK";
      else if(d.cloud=="EN-DESSOUS" && PullbackSell(d))
         signal="SELL PULLBACK";

      if(signal!="")
      {
         UpdatePersistence(i,signal);

         lines[idx++]=symbol+" "+signal+" ("+IntegerToString(persistCount[i])+")";
         count++;
      }
   }

   lines[idx++]="---------------------";
   lines[idx++]="TOTAL: "+IntegerToString(count);

   DrawDashboard(lines,idx);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   Scan();
}
//+------------------------------------------------------------------+
