#property version "1.10"
#property strict

input int InpTenkan = 9;
input int InpKijun = 26;
input int InpSenkouB = 52;

string lastSignal[500];
int persistCount[500];
string symbolList[500];

int OnInit(){
   EventSetTimer(5);
   for(int i=0; i<500; i++){
      lastSignal[i] = "";
      persistCount[i] = 0;
      symbolList[i] = "";
   }
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason){ EventKillTimer(); ObjectsDeleteAll(0,"ICH_"); }

struct Data{
   double close,prevClose,low,high;
   double kijun,ssa,ssb;
   bool valid; string cloud;
};

Data GetData(string symbol){
   Data d; d.valid=false;
   int h=iIchimoku(symbol,PERIOD_CURRENT,InpTenkan,InpKijun,InpSenkouB);
   if(h==INVALID_HANDLE) return d;

   double k[],a[],b[],c[],l[],h1[];
   ArraySetAsSeries(k,true); ArraySetAsSeries(a,true);
   ArraySetAsSeries(b,true); ArraySetAsSeries(c,true);

   bool ok = CopyBuffer(h,1,0,1,k)>=1
          && CopyBuffer(h,2,0,1,a)>=1
          && CopyBuffer(h,3,0,1,b)>=1
          && CopyClose(symbol,PERIOD_CURRENT,0,2,c)>=2
          && CopyLow(symbol,PERIOD_CURRENT,0,1,l)>=1
          && CopyHigh(symbol,PERIOD_CURRENT,0,1,h1)>=1;

   if(!ok){ IndicatorRelease(h); return d; }

   d.kijun=k[0]; d.ssa=a[0]; d.ssb=b[0];
   d.close=c[0]; d.prevClose=c[1]; d.low=l[0]; d.high=h1[0];

   double top=MathMax(d.ssa,d.ssb), bot=MathMin(d.ssa,d.ssb);
   d.cloud = d.close>top? "AU-DESSUS" : d.close<bot? "EN-DESSOUS" : "DANS";
   d.valid=true;
   IndicatorRelease(h);
   return d;
}

int GetIndex(string sym){
   for(int i=0;i<500;i++){
      if(symbolList[i]==""){ symbolList[i]=sym; return i; }
      if(symbolList[i]==sym) return i;
   }
   return 0;
}
void UpdatePersistence(string sym,string sig){
   int i=GetIndex(sym);
   if(lastSignal[i]==sig) persistCount[i]++; else {lastSignal[i]=sig; persistCount[i]=1;}
}

void DrawDashboard(string &lines[], int total){
   string bg="ICH_BG"; ObjectDelete(0,bg);
   int h=30 + total*16 + 10;
   ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,10);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,380);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrBlack);

   ObjectsDeleteAll(0,"ICH_TXT");
   for(int i=0;i<total;i++){
      string n="ICH_TXT_"+(string)i;
      ObjectCreate(0,n,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,n,OBJPROP_XDISTANCE,20);
      ObjectSetInteger(0,n,OBJPROP_YDISTANCE,30+i*16);
      ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9);
      ObjectSetString(0,n,OBJPROP_FONT,"Consolas");
      ObjectSetString(0,n,OBJPROP_TEXT,lines[i]);
      color col=clrWhite;
      if(StringFind(lines[i],"BUY")>=0) col=clrLime;
      if(StringFind(lines[i],"SELL")>=0) col=clrTomato;
      ObjectSetInteger(0,n,OBJPROP_COLOR,col);
   }
}

void Scan(){
   string lines[]; ArrayResize(lines,200); int idx=0;
   lines[idx++]="ICHIMOKU PRO SCANNER";
   lines[idx++]="---------------------";
   int total=SymbolsTotal(true), count=0;
   for(int i=0;i<total && i<200;i++){
      string sym=SymbolName(i,true); Data d=GetData(sym); if(!d.valid) continue;
      double top=MathMax(d.ssa,d.ssb), bot=MathMin(d.ssa,d.ssb);
      string sig="";
      if(d.prevClose<top && d.close>top) sig="BUY KUMO";
      else if(d.prevClose>bot && d.close<bot) sig="SELL KUMO";
      else if(d.cloud=="AU-DESSUS" && d.prevClose<d.kijun && d.close>d.kijun) sig="BUY KIJUN";
      else if(d.cloud=="EN-DESSOUS" && d.prevClose>d.kijun && d.close<d.kijun) sig="SELL KIJUN";
      else if(d.cloud=="AU-DESSUS" && d.low<=d.kijun && d.close>d.kijun) sig="BUY PULLBACK";
      else if(d.cloud=="EN-DESSOUS" && d.high>=d.kijun && d.close<d.kijun) sig="SELL PULLBACK";
      if(sig!=""){
         UpdatePersistence(sym,sig);
         int p=persistCount[GetIndex(sym)];
         lines[idx++]=StringFormat("%-8s %-13s (%d)",sym,sig,p);
         count++;
      }
   }
   lines[idx++]="---------------------";
   lines[idx++]=StringFormat("TOTAL: %d | %s",count,TimeToString(TimeCurrent(),TIME_MINUTES));
   DrawDashboard(lines,idx);
}
void OnTimer(){ Scan(); }
void OnTick(){}
