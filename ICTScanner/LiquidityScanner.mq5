//+------------------------------------------------------------------+
//|                                     SMC_Scanner_AutoTF.mq5        |
//|                                     Copyright 2024, TradingViewEA |
//|                                     Logic: Auto Timeframe Adapt   |
//+------------------------------------------------------------------+
#property copyright "Trader77974"
#property version   "4.00"
#property strict

//--- INPUTS
// Note : Plus d'input "InpTimeframe", on utilise l'UT du graphique
input int               InpFractalBars = 5;          // Sensibilité Fractale
input int               InpLookBack    = 300;        // Historique analysé
input bool              InpUseAlert    = true;       // Alertes Popups
input bool              InpDrawRemote  = true;       // Dessiner sur les autres graphiques ouverts
input color             InpColorHigh   = clrRed;     // Couleur High Liquidité
input color             InpColorLow    = clrDodgerBlue; // Couleur Low Liquidité (Target)
input color             InpColorSweep  = clrMagenta; // Couleur Signal

//--- GLOBALS
struct SymbolState {
   string symbol;
   datetime lastAlertTime;
};
SymbolState alerts[];
const string PREFIX = "SMC_Auto_"; 

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(5); // Scan toutes les 5 sec
   
   // On affiche sur quelle UT on va travailler
   Print("SMC Scanner: Démarré sur l'unité de temps: ", EnumToString(_Period));
   Print("Je scanne tout le Market Watch en ", EnumToString(_Period));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| OnTimer (Boucle Principale)                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Boucle sur tous les symboles du Market Watch
   for(int i = 0; i < SymbolsTotal(true); i++)
   {
      string symbol = SymbolName(i, true);
      ScanSymbol(symbol);
   }
}

//+------------------------------------------------------------------+
//| Logique Analyse + Dispatch Dessin                                |
//+------------------------------------------------------------------+
void ScanSymbol(string sym)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // MODIFICATION ICI : On utilise _Period au lieu de InpTimeframe
   // _Period récupère automatiquement l'UT du graphique où est l'EA
   int copied = CopyRates(sym, _Period, 0, InpLookBack + 10, rates);
   if(copied < InpLookBack) return;

   // -- 1. LOGIQUE SMC --
   int highIndex = -1;
   double highPrice = 0;
   datetime highTime = 0;
   
   int lowIndex = -1;
   double lowPrice = 0;
   datetime lowTime = 0;

   // Chercher High
   for(int i = 3; i < InpLookBack; i++) {
      if(IsFractalUp(rates, i)) {
         highIndex = i; highPrice = rates[i].high; highTime = rates[i].time;
         break; 
      }
   }
   if(highIndex == -1) return;

   // Chercher Low (après le High)
   for(int i = 2; i < highIndex; i++) {
      if(IsFractalDown(rates, i)) {
         lowIndex = i; lowPrice = rates[i].low; lowTime = rates[i].time;
         break; 
      }
   }
   if(lowIndex == -1) return;

   // Vérifier Sweep
   bool isSweep = false;
   datetime sweepTime = rates[0].time;
   
   // Si bougie 0 ou 1 casse le high
   if(rates[0].high > highPrice || rates[1].high > highPrice) {
      isSweep = true;
      if(rates[1].high > highPrice) sweepTime = rates[1].time;
   }
   
   // Invalidation si on est déjà sous le Low
   if(rates[0].close < lowPrice) return;

   // -- 2. ACTION SI SETUP VALIDE --
   if(isSweep)
   {
      // A. Dessiner sur TOUS les graphiques ouverts correspondant à ce symbole
      if(InpDrawRemote)
      {
         DrawOnAllCharts(sym, highTime, highPrice, lowTime, lowPrice, sweepTime, rates[0].high);
      }

      // B. Alerte
      if(!IsAlertedRecently(sym, rates[0].time))
      {
         string msg = "SMC SWEEP (" + EnumToString(_Period) + "): " + sym + "\nTarget Low: " + DoubleToString(lowPrice, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
         if(InpUseAlert) Alert(msg);
         RegisterAlert(sym, rates[0].time);
      }
   }
}

//+------------------------------------------------------------------+
//| FONCTION Dessin sur graphiques distants                          |
//+------------------------------------------------------------------+
void DrawOnAllCharts(string symbol, datetime tHigh, double pHigh, datetime tLow, double pLow, datetime tSweep, double pSweepHigh)
{
   long chartID = ChartFirst(); // Prendre le premier graphique ouvert
   
   while(chartID != -1)
   {
      // On ne dessine que si le symbole correspond
      if(ChartSymbol(chartID) == symbol)
      {
         // 1. Ligne High (Rouge) - Résistance cassée
         string objHigh = PREFIX + "High";
         if(ObjectFind(chartID, objHigh) < 0) 
         {
            ObjectCreate(chartID, objHigh, OBJ_TREND, 0, tHigh, pHigh, tSweep, pHigh);
         }
         else 
         { 
            ObjectSetDouble(chartID, objHigh, OBJPROP_PRICE, 0, pHigh);
            ObjectSetDouble(chartID, objHigh, OBJPROP_PRICE, 1, pHigh);
            ObjectSetInteger(chartID, objHigh, OBJPROP_TIME, 0, tHigh);
            ObjectSetInteger(chartID, objHigh, OBJPROP_TIME, 1, tSweep); 
         }
         
         ObjectSetInteger(chartID, objHigh, OBJPROP_COLOR, InpColorHigh);
         ObjectSetInteger(chartID, objHigh, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(chartID, objHigh, OBJPROP_WIDTH, 2);
         ObjectSetInteger(chartID, objHigh, OBJPROP_RAY_RIGHT, false);

         // 2. Ligne Low Target (Bleue) - Objectif
         string objLow = PREFIX + "Target";
         // On projette la ligne dans le futur selon l'UT actuelle (_Period)
         datetime futureTime = TimeCurrent() + PeriodSeconds(_Period) * 20;
         
         if(ObjectFind(chartID, objLow) < 0) 
         {
            ObjectCreate(chartID, objLow, OBJ_TREND, 0, tLow, pLow, futureTime, pLow);
         }
         else 
         { 
            ObjectSetDouble(chartID, objLow, OBJPROP_PRICE, 0, pLow);
            ObjectSetDouble(chartID, objLow, OBJPROP_PRICE, 1, pLow);
            ObjectSetInteger(chartID, objLow, OBJPROP_TIME, 0, tLow);
            ObjectSetInteger(chartID, objLow, OBJPROP_TIME, 1, futureTime); 
         }
         
         ObjectSetInteger(chartID, objLow, OBJPROP_COLOR, InpColorLow);
         ObjectSetInteger(chartID, objLow, OBJPROP_WIDTH, 2);
         ObjectSetInteger(chartID, objLow, OBJPROP_RAY_RIGHT, true);
         ObjectSetString(chartID, objLow, OBJPROP_TEXT, "LIQUIDITY TARGET (" + EnumToString(_Period) + ")");

         // 3. Flèche Signal (Sur la mèche du sweep)
         string objArrow = PREFIX + "Signal";
         if(ObjectFind(chartID, objArrow) < 0) 
         {
            ObjectCreate(chartID, objArrow, OBJ_ARROW_DOWN, 0, tSweep, pSweepHigh + _Point*10);
         }
         else 
         { 
            ObjectSetInteger(chartID, objArrow, OBJPROP_TIME, 0, tSweep); 
            ObjectSetDouble(chartID, objArrow, OBJPROP_PRICE, 0, pSweepHigh + _Point*10); 
         }
         
         ObjectSetInteger(chartID, objArrow, OBJPROP_COLOR, InpColorSweep);
         ObjectSetInteger(chartID, objArrow, OBJPROP_WIDTH, 3);
         
         ChartRedraw(chartID);
      }
      
      chartID = ChartNext(chartID);
   }
}

//+------------------------------------------------------------------+
//| Helpers (Fractals & Alerts)                                      |
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
