//+------------------------------------------------------------------+
//|                                     SMC_Scanner_VisualFix.mq5     |
//|                                     Copyright 2024, TradingViewEA |
//|                                     Logic: Better Arrow placement |
//+------------------------------------------------------------------+
#property copyright "Trader77974"
#property version   "5.10"
#property strict

//--- INPUTS
input int               InpFractalBars = 5;          
input int               InpLookBack    = 300;        
input bool              InpUseAlert    = true;       
input bool              InpDrawRemote  = true;       
input color             InpColorHigh   = clrRed;     
input color             InpColorLow    = clrDodgerBlue; 
input color             InpColorSweep  = clrMagenta; 

//--- GLOBALS
struct SymbolState {
   string symbol;
   datetime lastAlertTime;
};
SymbolState alerts[];
const string PREFIX = "SMC_Auto_"; 

//+------------------------------------------------------------------+
//| OnInit & Timer                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   EventSetTimer(5);
   Print("SMC Scanner: Fix Visuel Flèche activé.");
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) { EventKillTimer(); }
void OnTimer() {
   for(int i = 0; i < SymbolsTotal(true); i++)
      ScanSymbol(SymbolName(i, true));
}

//+------------------------------------------------------------------+
//| LOGIQUE SCANNER                                                  |
//+------------------------------------------------------------------+
void ScanSymbol(string sym)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   int copied = CopyRates(sym, _Period, 0, InpLookBack + 10, rates);
   if(copied < InpLookBack) return;

   // 1. HIGH
   int bestHighIndex = -1;
   double maxHighPrice = -1.0;
   double currentHigh = rates[0].high;
   
   for(int i = 3; i < InpLookBack; i++) {
      if(IsFractalUp(rates, i)) {
         if(rates[i].high < currentHigh) {
             if(rates[i].high > maxHighPrice) {
                 maxHighPrice = rates[i].high;
                 bestHighIndex = i;
             }
         }
      }
   }
   if(bestHighIndex == -1) return;

   int highIndex = bestHighIndex;
   double highPrice = maxHighPrice;
   datetime highTime = rates[bestHighIndex].time;

   // 2. LOW
   int bestLowIndex = -1;
   double minLowPrice = DBL_MAX; 
   for(int i = 2; i < highIndex; i++) {
      if(IsFractalDown(rates, i)) {
         if(rates[i].low < minLowPrice) {
            minLowPrice = rates[i].low;
            bestLowIndex = i;
         }
      }
   }
   if(bestLowIndex == -1) return;

   double lowPrice = minLowPrice;
   datetime lowTime = rates[bestLowIndex].time;

   // 3. SWEEP
   bool isFreshSweep = false;
   datetime sweepTime = rates[0].time;
   double sweepHighPoint = rates[0].high;

   if(rates[0].high > highPrice) isFreshSweep = true;
   if(rates[0].close < lowPrice) return;

   // 4. EXECUTION
   if(isFreshSweep)
   {
      if(InpDrawRemote)
         DrawOnAllCharts(sym, highTime, highPrice, lowTime, lowPrice, sweepTime, sweepHighPoint);

      if(!IsAlertedRecently(sym, rates[0].time))
      {
         string msg = "SMC SWEEP: " + sym + "\nHigh Broken: " + DoubleToString(highPrice, _Digits);
         if(InpUseAlert) Alert(msg);
         RegisterAlert(sym, rates[0].time);
      }
   }
}

//+------------------------------------------------------------------+
//| DESSIN (CORRECTION FLÈCHE ICI)                                   |
//+------------------------------------------------------------------+
void DrawOnAllCharts(string symbol, datetime tHigh, double pHigh, datetime tLow, double pLow, datetime tSweep, double pSweepHigh)
{
   long chartID = ChartFirst(); 
   while(chartID != -1)
   {
      if(ChartSymbol(chartID) == symbol)
      {
         // 1. High Line
         string objHigh = PREFIX + "High";
         if(ObjectFind(chartID, objHigh) < 0) ObjectCreate(chartID, objHigh, OBJ_TREND, 0, tHigh, pHigh, tSweep, pHigh);
         else { 
            ObjectSetDouble(chartID, objHigh, OBJPROP_PRICE, 0, pHigh); ObjectSetDouble(chartID, objHigh, OBJPROP_PRICE, 1, pHigh); 
            ObjectSetInteger(chartID, objHigh, OBJPROP_TIME, 0, tHigh); ObjectSetInteger(chartID, objHigh, OBJPROP_TIME, 1, tSweep); 
         }
         ObjectSetInteger(chartID, objHigh, OBJPROP_COLOR, InpColorHigh);
         ObjectSetInteger(chartID, objHigh, OBJPROP_STYLE, STYLE_DOT);

         // 2. Low Target
         string objLow = PREFIX + "Target";
         datetime futureTime = TimeCurrent() + PeriodSeconds(_Period) * 50; 
         if(ObjectFind(chartID, objLow) < 0) ObjectCreate(chartID, objLow, OBJ_TREND, 0, tLow, pLow, futureTime, pLow);
         else { 
            ObjectSetDouble(chartID, objLow, OBJPROP_PRICE, 0, pLow); ObjectSetDouble(chartID, objLow, OBJPROP_PRICE, 1, pLow);
            ObjectSetInteger(chartID, objLow, OBJPROP_TIME, 0, tLow); ObjectSetInteger(chartID, objLow, OBJPROP_TIME, 1, futureTime); 
         }
         ObjectSetInteger(chartID, objLow, OBJPROP_COLOR, InpColorLow);
         ObjectSetInteger(chartID, objLow, OBJPROP_RAY_RIGHT, true);
         ObjectSetString(chartID, objLow, OBJPROP_TEXT, "TARGET");

         // 3. FLÈCHE (CORRECTION VISUELLE)
         string objArrow = PREFIX + "Signal";
         
         // Calcul d'un écart proportionnel (0.05% du prix) pour être toujours visible mais pas trop loin
         // Sur le Gold (2600), ça fait ~1.3 points d'écart. Sur EURUSD, ~0.0005.
         double gap = pSweepHigh * 0.0005; 
         
         if(ObjectFind(chartID, objArrow) < 0) ObjectCreate(chartID, objArrow, OBJ_ARROW_DOWN, 0, tSweep, pSweepHigh + gap);
         else { 
            ObjectSetInteger(chartID, objArrow, OBJPROP_TIME, 0, tSweep); 
            ObjectSetDouble(chartID, objArrow, OBJPROP_PRICE, 0, pSweepHigh + gap); 
         }
         
         ObjectSetInteger(chartID, objArrow, OBJPROP_COLOR, InpColorSweep);
         ObjectSetInteger(chartID, objArrow, OBJPROP_WIDTH, 3);
         
         // IMPORTANT: On ancre le BAS de la flèche sur le point défini.
         // Comme c'est une flèche vers le bas, la pointe sera exactement à (High + gap)
         // Le corps de la flèche sera au-dessus.
         ObjectSetInteger(chartID, objArrow, OBJPROP_ANCHOR, ANCHOR_BOTTOM);

         ChartRedraw(chartID);
      }
      chartID = ChartNext(chartID);
   }
}

//+------------------------------------------------------------------+
//| HELPERS                                                          |
//+------------------------------------------------------------------+
bool IsFractalUp(MqlRates &rates[], int index) {
   if(index < InpFractalBars || index > ArraySize(rates) - InpFractalBars - 1) return false;
   double center = rates[index].high;
   for(int i = 1; i <= InpFractalBars; i++) {
      if(rates[index - i].high >= center) return false;
      if(rates[index + i].high >= center) return false;
   }
   return true;
}

bool IsFractalDown(MqlRates &rates[], int index) {
   if(index < InpFractalBars || index > ArraySize(rates) - InpFractalBars - 1) return false;
   double center = rates[index].low;
   for(int i = 1; i <= InpFractalBars; i++) {
      if(rates[index - i].low <= center) return false;
      if(rates[index + i].low <= center) return false;
   }
   return true;
}

bool IsAlertedRecently(string sym, datetime barTime) {
   for(int i=0; i<ArraySize(alerts); i++) {
      if(alerts[i].symbol == sym) {
         if(alerts[i].lastAlertTime == barTime) return true;
         return false;
      }
   }
   return false;
}

void RegisterAlert(string sym, datetime barTime) {
   for(int i=0; i<ArraySize(alerts); i++) {
      if(alerts[i].symbol == sym) {
         alerts[i].lastAlertTime = barTime;
         return;
      }
   }
   int s = ArraySize(alerts);
   ArrayResize(alerts, s+1);
   alerts[s].symbol = sym;
   alerts[s].lastAlertTime = barTime;
}
