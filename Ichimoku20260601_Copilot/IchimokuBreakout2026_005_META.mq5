#property version "1.30"
#property strict
#property description "Ichimoku Pro Scanner + Forcing + Max Lots"

//--- INPUTS
input int InpTenkan = 9;
input int InpKijun = 26;
input int InpSenkouB = 52;
input int InpForceUp = 75;
input int InpForceDown = 25;
input int TimerSeconds = 5;

//--- PERSISTANCE
string lastSignal[500];
int persistCount[500];
string symbolList[500];
datetime lastBarTime[500];

//+------------------------------------------------------------------+
int OnInit(){
   EventSetTimer(TimerSeconds);
   for(int i=0;i<500;i++){
      lastSignal[i]=""; persistCount[i]=0; symbolList[i]=""; lastBarTime[i]=0;
   }
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int r){ EventKillTimer(); ObjectsDeleteAll(0,"ICH_"); }

//+------------------------------------------------------------------+
struct Data{
   double close,prevClose,low,high;
   double kijun,ssa,ssb;
   double range,pctPos;
   bool valid; string cloud;
};
//+------------------------------------------------------------------+
bool SymbolReady(string s){
   if(!SymbolSelect(s,true)) return false;
   if(!SymbolIsSynchronized(s)) return false;
   if(Bars(s,Period()) < InpSenkouB+InpKijun+5) return false;
   return true;
}
//+------------------------------------------------------------------+
Data GetData(string symbol){
   Data d; d.valid=false;
   if(!SymbolReady(symbol)) return d;
   ResetLastError();
   int h=iIchimoku(symbol,Period(),InpTenkan,InpKijun,InpSenkouB);
   if(h==INVALID_HANDLE) return d;
   double k[],a[],b[],c[],l[],hi[];
   ArraySetAsSeries(k,true); ArraySetAsSeries(a,true);
   ArraySetAsSeries(b,true); ArraySetAsSeries(c,true);
   bool ok = CopyBuffer(h,1,0,1,k)>=1 && CopyBuffer(h,2,0,1,a)>=1 && CopyBuffer(h,3,0,1,b)>=1
          && CopyClose(symbol,Period(),0,2,c)>=2 && CopyLow(symbol,Period(),0,1,l)>=1 && CopyHigh(symbol,Period(),0,1,hi)>=1;
   if(!ok){ IndicatorRelease(h); return d; }
   d.kijun=k[0]; d.ssa=a[0]; d.ssb=b[0];
   d.close=c[0]; d.prevClose=c[1]; d.low=l[0]; d.high=hi[0];
   d.range=d.high-d.low; d.pctPos=d.range>0? (d.close-d.low)/d.range*100.0 : 50.0;
   double top=MathMax(d.ssa,d.ssb), bot=MathMin(d.ssa,d.ssb);
   d.cloud = d.close>top? "AU-DESSUS" : d.close<bot? "EN-DESSOUS" : "DANS";
   d.valid=true; IndicatorRelease(h); return d;
}
//+------------------------------------------------------------------+
int GetIndex(string s){ for(int i=0;i<500;i++){ if(symbolList[i]==""){symbolList[i]=s;return i;} if(symbolList[i]==s) return i;} return 0;}
void UpdatePersistence(string s,string sig,datetime bt){ int i=GetIndex(s); if(lastSignal[i]==sig){ if(lastBarTime[i]!=bt){persistCount[i]++; lastBarTime[i]=bt;}} else {lastSignal[i]=sig; persistCount[i]=1; lastBarTime[i]=bt;}}

//+------------------------------------------------------------------+
// CALCUL MAX LOTS (inspiré de ton script)
double CalcMaxLots(string sym){
   double price = SymbolInfoDouble(sym, SYMBOL_ASK);
   if(price==0) price = SymbolInfoDouble(sym, SYMBOL_BID);
   double margin1=0.0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, sym, 1.0, price, margin1) || margin1<=0) return 0.0;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double maxLots = freeMargin / margin1;
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step>0) maxLots = MathFloor(maxLots/step)*step;
   double maxVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(maxLots>maxVol) maxLots = maxVol;
   double minVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   if(maxLots<minVol) maxLots=0;
   return maxLots;
}
//+------------------------------------------------------------------+
void DrawDashboard(string &lines[],int total){
   string bg="ICH_BG"; ObjectDelete(0,bg);
   int h=30+total*16+10;
   ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,10); ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,20);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,520); ObjectSetInteger(0,bg,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,clrBlack);
   ObjectsDeleteAll(0,"ICH_TXT");
   for(int i=0;i<total;i++){
      string n="ICH_TXT_"+(string)i;
      ObjectCreate(0,n,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,n,OBJPROP_XDISTANCE,20); ObjectSetInteger(0,n,OBJPROP_YDISTANCE,30+i*16);
      ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9); ObjectSetString(0,n,OBJPROP_FONT,"Consolas");
      ObjectSetString(0,n,OBJPROP_TEXT,lines[i]);
      color col=clrWhite; if(StringFind(lines[i],"BUY")>=0) col=clrLime; if(StringFind(lines[i],"SELL")>=0) col=clrTomato;
      ObjectSetInteger(0,n,OBJPROP_COLOR,col);
   }
}
//+------------------------------------------------------------------+
void Scan(){
   string lines[]; ArrayResize(lines,300); int idx=0;
   lines[idx++]="ICHIMOKU PRO SCANNER | Max Lots live";
   lines[idx++]="----------------------------------------";
   int total=SymbolsTotal(true), count=0;
   double freeM = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   lines[idx++]=StringFormat("Marge Libre: %.2f %s", freeM, AccountInfoString(ACCOUNT_CURRENCY));
   lines[idx++]="----------------------------------------";

   for(int i=0;i<total && i<200;i++){
      string sym=SymbolName(i,true);
      Data d=GetData(sym); if(!d.valid) continue;
      double top=MathMax(d.ssa,d.ssb), bot=MathMin(d.ssa,d.ssb); string sig="";
      if(d.prevClose<top && d.close>top) sig="BUY KUMO";
      else if(d.prevClose>bot && d.close<bot) sig="SELL KUMO";
      else if(d.cloud=="AU-DESSUS" && d.prevClose<d.kijun && d.close>d.kijun) sig="BUY KIJUN";
      else if(d.cloud=="EN-DESSOUS" && d.prevClose>d.kijun && d.close<d.kijun) sig="SELL KIJUN";
      else if(d.cloud=="AU-DESSUS" && d.low<=d.kijun && d.close>d.kijun) sig="BUY PULLBACK";
      else if(d.cloud=="EN-DESSOUS" && d.high>=d.kijun && d.close<d.kijun) sig="SELL PULLBACK";
      if(sig!=""){
         datetime bt=iTime(sym,Period(),0); UpdatePersistence(sym,sig,bt); int p=persistCount[GetIndex(sym)];
         string force="→"; if(d.pctPos>=InpForceUp) force="↑"; else if(d.pctPos<=InpForceDown) force="↓";
         double maxL = CalcMaxLots(sym);
         lines[idx++]=StringFormat("%-10s %-12s (%2d) %s%3.0f%% Lot:%.2f", sym, sig, p, force, d.pctPos, maxL);
         count++;
      }
   }
   lines[idx++]="----------------------------------------";
   lines[idx++]=StringFormat("TOTAL: %d | %s",count,TimeToString(TimeCurrent(),TIME_MINUTES));
   DrawDashboard(lines,idx);
}
//+------------------------------------------------------------------+
void OnTimer(){ Scan(); }
void OnTick(){}
