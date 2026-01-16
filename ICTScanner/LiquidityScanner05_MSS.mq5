//+------------------------------------------------------------------+
//|                                     SMC_Scanner_MSS_Short.mq5    |
//|                                     Copyright 2024, Trader77974  |
//|                                     Logic: SWEEP + RE-ENTRY + MSS|
//+------------------------------------------------------------------+
#property copyright "Trader77974"
#property version   "15.00"
#property strict

//--- INPUTS
input int    InpFractalBars = 5;    // Sensibilité des sommets/creux
input int    InpLookBack    = 300;  // Historique d'analyse
input int    InpSweepMemory = 15;   // Nombre de bougies pour détecter le sweep récent
input bool   InpUseAlert    = true; 
input bool   InpDrawRemote  = true; 

// Couleurs
input color  InpColorHigh   = clrRed;       // Liquidité Haute
input color  InpColorLow    = clrDodgerBlue; // Cible (Target)
input color  InpColorMSS    = clrOrange;     // Ligne de changement de structure
input color  InpColorSweep  = clrMagenta;

//--- GLOBALS
struct SymbolState { string symbol; datetime lastAlertTime; };
SymbolState alerts[];
const string PREFIX = "SMC_MSS_"; 

//+------------------------------------------------------------------+
//| Init / Deinit                                                    |
//+------------------------------------------------------------------+
int OnInit() {
   EventSetTimer(5);
   Print("SMC Scanner: Détection Sweep + MSS activée.");
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason) { EventKillTimer(); ObjectsDeleteAll(0, PREFIX); }

void OnTimer() {
   for(int i = 0; i < SymbolsTotal(true); i++)
      ScanSymbol(SymbolName(i, true));
}

//+------------------------------------------------------------------+
//| LOGIQUE PRINCIPALE                                               |
//+------------------------------------------------------------------+
void ScanSymbol(string sym)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   int copied = CopyRates(sym, _Period, 0, InpLookBack, rates);
   if(copied < InpLookBack) return;

   // 1. DÉFINIR LE POINT LE PLUS HAUT RÉCENT (Le sommet du Sweep)
   double sweepHighPrice = 0;
   int sweepHighIndex = 0;
   
   for(int k=0; k<InpSweepMemory; k++) {
      if(rates[k].high > sweepHighPrice) {
         sweepHighPrice = rates[k].high;
         sweepHighIndex = k;
      }
   }

   // 2. TROUVER LA LIQUIDITÉ HAUTE (L'ancien sommet fractale qui a été "sweep")
   int oldHighIndex = -1;
   double oldHighPrice = -1.0;
   
   for(int i = sweepHighIndex + 1; i < InpLookBack - InpFractalBars; i++)
   {
      if(IsFractalUp(rates, i))
      {
         if(rates[i].high < sweepHighPrice) // Il faut que le prix récent soit monté plus haut
         {
             oldHighPrice = rates[i].high;
             oldHighIndex = i;
             break; // On prend le plus proche
         }
      }
   }
   
   if(oldHighIndex == -1) return;

   // 3. TROUVER LE MSS LEVEL (Le plus bas entre Old High et Sweep High)
   // C'est le "creux" que le prix doit casser pour valider le changement de structure
   double mssLevelPrice = DBL_MAX;
   int mssLevelIndex = -1;

   for(int j = sweepHighIndex; j < oldHighIndex; j++)
   {
      if(rates[j].low < mssLevelPrice)
      {
         mssLevelPrice = rates[j].low;
         mssLevelIndex = j;
      }
   }

   if(mssLevelIndex == -1) return;

   // 4. VALIDATIONS ICT
   
   // A. Réintégration : Le prix doit être revenu sous l'ancien High
   bool isReintegrated = (rates[0].close < oldHighPrice);
   
   // B. MSS : Le prix doit avoir clôturé SOUS le mssLevelPrice
   bool isMSSValidated = (rates[0].close < mssLevelPrice);

   if(!isReintegrated || !isMSSValidated) return;

   // 5. TROUVER LA CIBLE (Le "Weak Low" ou Liquidité Basse)
   int targetLowIndex = -1;
   double targetLowPrice = DBL_MAX;
   for(int i = 1; i < oldHighIndex; i++) {
      if(rates[i].low < targetLowPrice) {
         targetLowPrice = rates[i].low;
         targetLowIndex = i;
      }
   }
   
   // Si le prix a déjà atteint la cible, le setup est fini
   if(rates[0].close <= targetLowPrice) return;

   // 6. DESSIN ET ALERTE
   if(InpDrawRemote)
   {
       DrawSMC(sym, rates[oldHighIndex].time, oldHighPrice, 
                    rates[targetLowIndex].time, targetLowPrice, 
                    rates[sweepHighIndex].time, sweepHighPrice,
                    rates[mssLevelIndex].time, mssLevelPrice);
   }

   if(!IsAlertedRecently(sym, rates[sweepHighIndex].time))
   {
      string msg = "SMC SHORT: " + sym + " | Sweep High + MSS validé !";
      if(InpUseAlert) Alert(msg);
      RegisterAlert(sym, rates[sweepHighIndex].time);
   }
}

//+------------------------------------------------------------------+
//| FONCTIONS DE DESSIN                                              |
//+------------------------------------------------------------------+
void DrawSMC(string symbol, datetime tHigh, double pHigh, datetime tLow, double pLow, datetime tSweep, double pSweep, datetime tMSS, double pMSS)
{
   long chartID = ChartFirst(); 
   while(chartID != -1)
   {
      if(ChartSymbol(chartID) == symbol)
      {
         // Ligne Liquidité Haute (Sweeped)
         CreateLine(chartID, PREFIX+"Liq", tHigh, pHigh, tSweep, pHigh, InpColorHigh, STYLE_DOT, 1);
         
         // Ligne MSS (Trigger)
         CreateLine(chartID, PREFIX+"MSS", tMSS, pMSS, TimeCurrent(), pMSS, InpColorMSS, STYLE_SOLID, 2);
         
         // Ligne Target
         CreateLine(chartID, PREFIX+"Target", tLow, pLow, TimeCurrent() + 3600, pLow, InpColorLow, STYLE_DASH, 1);

         // Label MSS
         if(ObjectFind(chartID, PREFIX+"MSS_Label") < 0) {
            ObjectCreate(chartID, PREFIX+"MSS_Label", OBJ_TEXT, 0, TimeCurrent(), pMSS);
            ObjectSetString(chartID, PREFIX+"MSS_Label", OBJPROP_TEXT, "  MSS (Entry)");
            ObjectSetInteger(chartID, PREFIX+"MSS_Label", OBJPROP_COLOR, InpColorMSS);
         } else ObjectSetDouble(chartID, PREFIX+"MSS_Label", OBJPROP_PRICE, 0, pMSS);

         ChartRedraw(chartID);
      }
      chartID = ChartNext(chartID);
   }
}

void CreateLine(long cid, string name, datetime t1, double p1, datetime t2, double p2, color clr, ENUM_LINE_STYLE style, int width) {
   if(ObjectFind(cid, name) < 0) ObjectCreate(cid, name, OBJ_TREND, 0, t1, p1, t2, p2);
   else {
      ObjectSetInteger(cid, name, OBJPROP_TIME, 0, t1); ObjectSetDouble(cid, name, OBJPROP_PRICE, 0, p1);
      ObjectSetInteger(cid, name, OBJPROP_TIME, 1, t2); ObjectSetDouble(cid, name, OBJPROP_PRICE, 1, p2);
   }
   ObjectSetInteger(cid, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(cid, name, OBJPROP_STYLE, style);
   ObjectSetInteger(cid, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(cid, name, OBJPROP_RAY_RIGHT, false);
}

//+------------------------------------------------------------------+
//| UTILS                                                            |
//+------------------------------------------------------------------+
bool IsFractalUp(MqlRates &rates[], int index) {
   if(index < InpFractalBars || index > ArraySize(rates) - InpFractalBars - 1) return false;
   for(int i = 1; i <= InpFractalBars; i++) {
      if(rates[index - i].high >= rates[index].high || rates[index + i].high >= rates[index].high) return false;
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
