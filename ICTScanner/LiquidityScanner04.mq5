//+------------------------------------------------------------------+
//|                                     SMC_Scanner_Memory.mq5        |
//|                                     Copyright 2024, TradingViewEA |
//|                                     Logic: SWEEP MEMORY (RECENT)  |
//+------------------------------------------------------------------+
#property copyright "Trader77974"
#property version   "14.00"
#property strict

//--- INPUTS
input int    InpFractalBars = 5;    // Sensibilité
input int    InpLookBack    = 300;  // Historique
input int    InpSweepMemory = 10;   // [NOUVEAU] Regarder les cassures des X dernières bougies
input bool   InpUseAlert    = true; 
input bool   InpDrawRemote  = true; 

// Couleurs
input color  InpColorHigh   = clrRed;
input color  InpColorLow    = clrDodgerBlue;
input color  InpColorSweep  = clrMagenta;

//--- GLOBALS
struct SymbolState { string symbol; datetime lastAlertTime; };
SymbolState alerts[];
const string PREFIX = "SMC_Mem_"; 

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit() {
   EventSetTimer(5);
   Print("SMC Memory: Je détecte les sweeps récents (mémoire de ", InpSweepMemory, " bougies).");
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) { EventKillTimer(); }

void OnTimer() {
   for(int i = 0; i < SymbolsTotal(true); i++)
      ScanSymbol(SymbolName(i, true));
}

//+------------------------------------------------------------------+
//| LOGIQUE AVEC MÉMOIRE                                             |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| LOGIQUE AVEC RÉINTÉGRATION (FAKEOUT)                             |
//+------------------------------------------------------------------+
void ScanSymbol(string sym)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   int copied = CopyRates(sym, _Period, 0, InpLookBack + 20, rates);
   if(copied < InpLookBack) return;

   // 1. DÉFINIR LE "PLAFOND RÉCENT" (Le Sweep)
   double recentMaxHigh = 0;
   int recentMaxIndex = 0;
   
   for(int k=0; k<InpSweepMemory; k++) {
      if(rates[k].high > recentMaxHigh) {
         recentMaxHigh = rates[k].high;
         recentMaxIndex = k;
      }
   }

   // 2. TROUVER LA LIQUIDITÉ HAUTE CASSÉE (Ligne Rouge)
   int bestHighIndex = -1;
   double maxBrokenHighPrice = -1.0;
   
   for(int i = InpSweepMemory + 1; i < InpLookBack; i++)
   {
      if(IsFractalUp(rates, i))
      {
         double fractalPrice = rates[i].high;
         
         // Condition A : Le sommet doit avoir été dépassé par le mouvement récent
         if(fractalPrice <= recentMaxHigh) 
         {
             if(fractalPrice > maxBrokenHighPrice)
             {
                 maxBrokenHighPrice = fractalPrice;
                 bestHighIndex = i;
             }
         }
      }
   }
   
   if(bestHighIndex == -1) return; // Pas de cassure détectée

   // 3. TROUVER LA CIBLE (LOW)
   int bestLowIndex = -1;
   double minLowPrice = DBL_MAX;
   
   for(int i = 1; i < bestHighIndex; i++)
   {
      if(rates[i].low < minLowPrice)
      {
         minLowPrice = rates[i].low;
         bestLowIndex = i;
      }
   }
   
   if(bestLowIndex == -1) return;
   
   // Si on a déjà atteint la target finale (le plus bas), le setup est périmé
   if(rates[0].close < minLowPrice) return;


   // --- [NOUVEAU] 4. VALIDATION DE LA RÉINTÉGRATION ---
   // On vérifie si le prix actuel est repassé SOUS la liquidité (Ligne Rouge)
   // Cela confirme que c'était bien une prise de liquidité (mèche) et non une continuation haussière.
   
   double currentPrice = rates[0].close; // Prix actuel
   
   // Si le prix est encore AU-DESSUS du niveau, on attend (pas d'alerte)
   if(currentPrice >= maxBrokenHighPrice) return;

   // ---------------------------------------------------


   // 5. ACTION (DESSIN & ALERTE)
   if(InpDrawRemote)
   {
       DrawOnAllCharts(sym, 
                       rates[bestHighIndex].time, maxBrokenHighPrice, 
                       rates[bestLowIndex].time, minLowPrice, 
                       rates[recentMaxIndex].time, rates[recentMaxIndex].high);
   }

   if(!IsAlertedRecently(sym, rates[recentMaxIndex].time))
   {
      // Message un peu plus précis
      string msg = "SMC FAKEOUT (Rejection): " + sym + " est repassé sous le High";
      if(InpUseAlert) Alert(msg);
      
      RegisterAlert(sym, rates[recentMaxIndex].time);
   }
}

//+------------------------------------------------------------------+
//| DESSIN & UTILS                                                   |
//+------------------------------------------------------------------+
void DrawOnAllCharts(string symbol, datetime tHigh, double pHigh, datetime tLow, double pLow, datetime tSweep, double pSweepHigh)
{
   long chartID = ChartFirst(); 
   while(chartID != -1)
   {
      if(ChartSymbol(chartID) == symbol)
      {
         // High Line
         string objHigh = PREFIX + "High";
         if(ObjectFind(chartID, objHigh) < 0) ObjectCreate(chartID, objHigh, OBJ_TREND, 0, tHigh, pHigh, tSweep, pHigh);
         else { 
            ObjectSetDouble(chartID, objHigh, OBJPROP_PRICE, 0, pHigh); ObjectSetDouble(chartID, objHigh, OBJPROP_PRICE, 1, pHigh); 
            ObjectSetInteger(chartID, objHigh, OBJPROP_TIME, 0, tHigh); ObjectSetInteger(chartID, objHigh, OBJPROP_TIME, 1, tSweep); 
         }
         ObjectSetInteger(chartID, objHigh, OBJPROP_COLOR, InpColorHigh);
         ObjectSetInteger(chartID, objHigh, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(chartID, objHigh, OBJPROP_WIDTH, 2);
         ObjectSetInteger(chartID, objHigh, OBJPROP_RAY_RIGHT, false);

         // Target
         string objLow = PREFIX + "Target";
         datetime futureTime = TimeCurrent() + PeriodSeconds(_Period) * 50; 
         if(ObjectFind(chartID, objLow) < 0) ObjectCreate(chartID, objLow, OBJ_TREND, 0, tLow, pLow, futureTime, pLow);
         else { 
            ObjectSetDouble(chartID, objLow, OBJPROP_PRICE, 0, pLow); ObjectSetDouble(chartID, objLow, OBJPROP_PRICE, 1, pLow);
            ObjectSetInteger(chartID, objLow, OBJPROP_TIME, 0, tLow); ObjectSetInteger(chartID, objLow, OBJPROP_TIME, 1, futureTime); 
         }
         ObjectSetInteger(chartID, objLow, OBJPROP_COLOR, InpColorLow);
         ObjectSetInteger(chartID, objLow, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(chartID, objLow, OBJPROP_WIDTH, 2);

         // Arrow
         string objArrow = PREFIX + "Signal";
         double gap = GetDynamicGap(pSweepHigh);
         if(ObjectFind(chartID, objArrow) < 0) ObjectCreate(chartID, objArrow, OBJ_ARROW_DOWN, 0, tSweep, pSweepHigh + gap);
         else { 
            ObjectSetInteger(chartID, objArrow, OBJPROP_TIME, 0, tSweep); 
            ObjectSetDouble(chartID, objArrow, OBJPROP_PRICE, 0, pSweepHigh + gap); 
         }
         ObjectSetInteger(chartID, objArrow, OBJPROP_COLOR, InpColorSweep);
         ObjectSetInteger(chartID, objArrow, OBJPROP_WIDTH, 3);
         ObjectSetInteger(chartID, objArrow, OBJPROP_ANCHOR, ANCHOR_BOTTOM);

         ChartRedraw(chartID);
      }
      chartID = ChartNext(chartID);
   }
}

double GetDynamicGap(double price) {
   double percent = 0.0005; 
   if(price < 500) percent = 0.002;
   if(price < 10) percent = 0.01;
   if(price < 0.1) percent = 0.025; 
   return price * percent;
}

bool IsFractalUp(MqlRates &rates[], int index) {
   if(index < InpFractalBars || index > ArraySize(rates) - InpFractalBars - 1) return false;
   double center = rates[index].high;
   for(int i = 1; i <= InpFractalBars; i++) {
      if(rates[index - i].high >= center) return false;
      if(rates[index + i].high >= center) return false;
   }
   return true;
}

bool IsAlertedRecently(string sym, datetime barTime) {
   for(int i=0; i<ArraySize(alerts); i++) if(alerts[i].symbol == sym && alerts[i].lastAlertTime == barTime) return true;
   return false;
}

void RegisterAlert(string sym, datetime barTime) {
   for(int i=0; i<ArraySize(alerts); i++) if(alerts[i].symbol == sym) { alerts[i].lastAlertTime = barTime; return; }
   int s = ArraySize(alerts); ArrayResize(alerts, s+1); alerts[s].symbol = sym; alerts[s].lastAlertTime = barTime;
}
