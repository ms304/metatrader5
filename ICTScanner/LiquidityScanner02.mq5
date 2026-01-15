//+------------------------------------------------------------------+
//|                                     SMC_Scanner_Basic.mq5         |
//|                                     Copyright 2024, TradingViewEA |
//|                                     Logic: PURE PRICE ACTION      |
//+------------------------------------------------------------------+
#property copyright "Trader77974"
#property version   "1.00"
#property strict

//--- INPUTS
input int    InpFractalBars = 5;    // Sensibilité pour trouver les sommets
input int    InpLookBack    = 300;  // Profondeur d'analyse
input bool   InpUseAlert    = true; // Alertes
input bool   InpDrawRemote  = true; // Dessin sur les graphiques

// Couleurs
input color  InpColorHigh   = clrRed;
input color  InpColorLow    = clrDodgerBlue;
input color  InpColorSweep  = clrMagenta;

//--- GLOBALS
struct SymbolState { string symbol; datetime lastAlertTime; };
SymbolState alerts[];
const string PREFIX = "SMC_Basic_"; 

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit() {
   EventSetTimer(5); // Scan toutes les 5 secondes
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); }

void OnTimer() {
   for(int i = 0; i < SymbolsTotal(true); i++)
      ScanSymbol(SymbolName(i, true));
}

//+------------------------------------------------------------------+
//| LOGIQUE SIMPLE                                                   |
//+------------------------------------------------------------------+
void ScanSymbol(string sym)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   int copied = CopyRates(sym, _Period, 0, InpLookBack + 10, rates);
   if(copied < InpLookBack) return;

   // 1. TROUVER LE MAÎTRE SOMMET (Le plus haut absolu de la période)
   int bestHighIndex = -1;
   double maxHighPrice = -1.0;
   
   // On parcourt tout l'historique
   for(int i = 3; i < InpLookBack; i++)
   {
      if(IsFractalUp(rates, i))
      {
         // C'est simple : on garde celui qui est le plus haut
         if(rates[i].high > maxHighPrice)
         {
            maxHighPrice = rates[i].high;
            bestHighIndex = i;
         }
      }
   }
   
   if(bestHighIndex == -1) return; // Rien trouvé

   // 2. VÉRIFIER LE SWEEP
   // Si le prix actuel est inférieur à ce sommet, on attend (résistance non testée)
   if(rates[0].high < maxHighPrice) return;

   // 3. TROUVER LA CIBLE (Le plus bas entre le sommet et maintenant)
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
   
   // Si on a déjà clôturé sous la target, c'est fini
   if(rates[0].close < minLowPrice) return;

   // 4. ACTION (Dessin & Alerte)
   if(InpDrawRemote)
   {
       DrawOnAllCharts(sym, 
                       rates[bestHighIndex].time, maxHighPrice, 
                       rates[bestLowIndex].time, minLowPrice, 
                       rates[0].time, rates[0].high);
   }

   // Alerte seulement si c'est nouveau (bougie précédente était sous le niveau)
   // ou si le prix vient juste de percer
   if(!IsAlertedRecently(sym, rates[0].time))
   {
      // Filtre : la bougie d'avant ne devait pas avoir déjà tout explosé
      if(rates[1].high <= maxHighPrice || (rates[0].high > maxHighPrice && rates[0].close < maxHighPrice))
      {
         string msg = "SMC BASIC SWEEP: " + sym;
         if(InpUseAlert) Alert(msg);
         RegisterAlert(sym, rates[0].time);
      }
   }
}

//+------------------------------------------------------------------+
//| DESSIN SIMPLE (Avec correctif flèche GRT)                        |
//+------------------------------------------------------------------+
void DrawOnAllCharts(string symbol, datetime tHigh, double pHigh, datetime tLow, double pLow, datetime tSweep, double pSweepHigh)
{
   long chartID = ChartFirst(); 
   while(chartID != -1)
   {
      if(ChartSymbol(chartID) == symbol)
      {
         // 1. High Line (Rouge)
         string objHigh = PREFIX + "High";
         if(ObjectFind(chartID, objHigh) < 0) ObjectCreate(chartID, objHigh, OBJ_TREND, 0, tHigh, pHigh, tSweep, pHigh);
         else { 
            ObjectSetDouble(chartID, objHigh, OBJPROP_PRICE, 0, pHigh); ObjectSetDouble(chartID, objHigh, OBJPROP_PRICE, 1, pHigh); 
            ObjectSetInteger(chartID, objHigh, OBJPROP_TIME, 0, tHigh); ObjectSetInteger(chartID, objHigh, OBJPROP_TIME, 1, tSweep); 
         }
         ObjectSetInteger(chartID, objHigh, OBJPROP_COLOR, InpColorHigh);
         ObjectSetInteger(chartID, objHigh, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(chartID, objHigh, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(chartID, objHigh, OBJPROP_WIDTH, 2);

         // 2. Target Line (Bleue)
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

         // 3. Arrow (Signal) - Position ajustée
         string objArrow = PREFIX + "Signal";
         double gap = GetDynamicGap(pSweepHigh); // Calcul intelligent de l'écart
         
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

//+------------------------------------------------------------------+
//| UTILS                                                            |
//+------------------------------------------------------------------+
double GetDynamicGap(double price) {
   // Permet à la flèche d'être visible sur Bitcoin, Gold, Forex et Shitcoins
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
