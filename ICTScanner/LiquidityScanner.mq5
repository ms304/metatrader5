//+------------------------------------------------------------------+
//|                                     SMC_Scanner_PureSimple.mq5    |
//|                                     Copyright 2024, TradingViewEA |
//|                                     Logic: Highest High & Sweep   |
//+------------------------------------------------------------------+
#property copyright "Trader77974"
#property version   "8.00"
#property strict

//--- PARAMÈTRES SIMPLES
input int    InpFractalBars = 5;    // Sensibilité pour définir un sommet (5 est standard)
input int    InpLookBack    = 300;  // Combien de bougies on regarde en arrière
input bool   InpUseAlert    = true; // Activer les alertes
input bool   InpDrawRemote  = true; // Dessiner les lignes

// Couleurs
input color  InpColorHigh   = clrRed;
input color  InpColorLow    = clrDodgerBlue;
input color  InpColorSweep  = clrMagenta;

//--- GLOBALS
struct SymbolState { string symbol; datetime lastAlertTime; };
SymbolState alerts[];
const string PREFIX = "SMC_Simple_"; 

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
//| LA LOGIQUE PURE                                                  |
//+------------------------------------------------------------------+
void ScanSymbol(string sym)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // On récupère les données
   int copied = CopyRates(sym, _Period, 0, InpLookBack + 10, rates);
   if(copied < InpLookBack) return;

   // -------------------------------------------------------
   // ÉTAPE 1 : TROUVER LE SOMMET MAJEUR (Le plus haut Fractal)
   // -------------------------------------------------------
   int highestIndex = -1;
   double highestPrice = -1.0;
   
   // On parcourt l'historique pour trouver le BOSS (le plus haut sommet)
   // On ignore les 2 premières bougies pour s'assurer que le fractal est bien formé
   for(int i = 3; i < InpLookBack; i++)
   {
      if(IsFractalUp(rates, i))
      {
         // On cherche simplement le plus haut de la période
         // Mais il doit être EN DESSOUS du prix actuel ou PROCHE (pour être sweepé maintenant)
         // Ici, on prend le plus haut tout court dans l'historique visible.
         if(rates[i].high > highestPrice)
         {
            highestPrice = rates[i].high;
            highestIndex = i;
         }
      }
   }
   
   if(highestIndex == -1) return; // Pas de sommet trouvé

   // -------------------------------------------------------
   // ÉTAPE 2 : VÉRIFIER SI ON EST EN TRAIN DE LE CASSER
   // -------------------------------------------------------
   double currentPrice = rates[0].high; // Prix actuel (Mèche)
   
   // Si le sommet trouvé est BEAUCOUP plus haut que le prix actuel, on n'y est pas encore.
   // On ne s'intéresse qu'aux cas où le prix actuel est entrain de dépasser ce sommet.
   if(currentPrice < highestPrice) return; 

   // -------------------------------------------------------
   // ÉTAPE 3 : TROUVER LE CREUX (TARGET)
   // -------------------------------------------------------
   // Le creux doit être entre le Sommet Majeur et Maintenant
   int lowestIndex = -1;
   double lowestPrice = DBL_MAX;
   
   for(int i = 1; i < highestIndex; i++)
   {
      // On cherche le point le plus bas absolu dans cette zone
      if(rates[i].low < lowestPrice)
      {
         lowestPrice = rates[i].low;
         lowestIndex = i;
      }
   }
   
   if(lowestIndex == -1) return;
   
   // Si le prix a déjà cassé le bas, le setup est invalidé (déjà fini)
   if(rates[0].close < lowestPrice) return;

   // -------------------------------------------------------
   // ÉTAPE 4 : DESSINER ET ALERTER
   // -------------------------------------------------------
   
   // On vérifie que c'est une cassure "fraîche" (la bougie précédente était en dessous ou proche)
   // Cela évite de spammer si le prix est au-dessus depuis 50 bougies.
   bool isFresh = false;
   if(rates[1].high <= highestPrice || rates[0].high > highestPrice) isFresh = true;
   
   if(isFresh)
   {
      if(InpDrawRemote)
         DrawOnAllCharts(sym, rates[highestIndex].time, highestPrice, rates[lowestIndex].time, lowestPrice, rates[0].time, rates[0].high);

      if(!IsAlertedRecently(sym, rates[0].time))
      {
         string msg = "LIQUIDITY SWEEP: " + sym + "\nHigh: " + DoubleToString(highestPrice, _Digits);
         if(InpUseAlert) Alert(msg);
         RegisterAlert(sym, rates[0].time);
      }
   }
}

//+------------------------------------------------------------------+
//| FONCTIONS GRAPHIQUES (Lignes & Flèches)                          |
//+------------------------------------------------------------------+
void DrawOnAllCharts(string symbol, datetime tHigh, double pHigh, datetime tLow, double pLow, datetime tSweep, double pSweepHigh)
{
   long chartID = ChartFirst(); 
   while(chartID != -1)
   {
      if(ChartSymbol(chartID) == symbol)
      {
         // 1. Ligne ROUGE (High)
         string objHigh = PREFIX + "High";
         if(ObjectFind(chartID, objHigh) < 0) ObjectCreate(chartID, objHigh, OBJ_TREND, 0, tHigh, pHigh, tSweep, pHigh);
         else { 
            ObjectSetDouble(chartID, objHigh, OBJPROP_PRICE, 0, pHigh); ObjectSetDouble(chartID, objHigh, OBJPROP_PRICE, 1, pHigh); 
            ObjectSetInteger(chartID, objHigh, OBJPROP_TIME, 0, tHigh); ObjectSetInteger(chartID, objHigh, OBJPROP_TIME, 1, tSweep); 
         }
         ObjectSetInteger(chartID, objHigh, OBJPROP_COLOR, InpColorHigh);
         ObjectSetInteger(chartID, objHigh, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(chartID, objHigh, OBJPROP_RAY_RIGHT, false);

         // 2. Ligne BLEUE (Target)
         string objLow = PREFIX + "Target";
         datetime futureTime = TimeCurrent() + PeriodSeconds(_Period) * 50; 
         if(ObjectFind(chartID, objLow) < 0) ObjectCreate(chartID, objLow, OBJ_TREND, 0, tLow, pLow, futureTime, pLow);
         else { 
            ObjectSetDouble(chartID, objLow, OBJPROP_PRICE, 0, pLow); ObjectSetDouble(chartID, objLow, OBJPROP_PRICE, 1, pLow);
            ObjectSetInteger(chartID, objLow, OBJPROP_TIME, 0, tLow); ObjectSetInteger(chartID, objLow, OBJPROP_TIME, 1, futureTime); 
         }
         ObjectSetInteger(chartID, objLow, OBJPROP_COLOR, InpColorLow);
         ObjectSetInteger(chartID, objLow, OBJPROP_RAY_RIGHT, true);

         // 3. Flèche (Calcul d'écart universel)
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

//+------------------------------------------------------------------+
//| UTILS                                                            |
//+------------------------------------------------------------------+
double GetDynamicGap(double price) {
   // Ajuste la position de la flèche selon la taille du prix (Crypto vs Forex vs Gold)
   double percent = 0.0005; 
   if(price < 500) percent = 0.002;
   if(price < 10) percent = 0.01;
   if(price < 0.1) percent = 0.03; 
   return price * percent;
}

bool IsFractalUp(MqlRates &rates[], int index) {
   if(index < InpFractalBars || index > ArraySize(rates) - InpFractalBars - 1) return false;
   double center = rates[index].high;
   // Le fractal doit être le plus haut des X barres à gauche et à droite
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
   for(int i=0; i<ArraySize(alerts); i++) {
       if(alerts[i].symbol == sym) { alerts[i].lastAlertTime = barTime; return; }
   }
   int s = ArraySize(alerts); ArrayResize(alerts, s+1); alerts[s].symbol = sym; alerts[s].lastAlertTime = barTime;
}
