//+------------------------------------------------------------------+
//|                                     Simple_SMC_EA_Signals.mq5    |
//|                  V3: Avec Alertes et Flèches                     |
//+------------------------------------------------------------------+
#property copyright "SMC Signals"
#property version   "1.03"
#include <Trade\Trade.mqh>

//--- INPUTS
input int      SwingLength = 20;       // J'ai augmenté à 20 pour filtrer le bruit
input bool     UseAlerts   = true;     // Activer les alertes sonores/pop-up
input int      MagicNumber = 123456;   

//--- VARIABLES
CTrade trade;
int trendBias = 0; 
double lastSwingHigh = 0;
double lastSwingLow = 0;

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Lignes Swing
   ObjectCreate(0, "SMC_High_Line", OBJ_HLINE, 0, 0, 0);
   ObjectSetInteger(0, "SMC_High_Line", OBJPROP_COLOR, clrLimeGreen); // Vert clair
   ObjectSetInteger(0, "SMC_High_Line", OBJPROP_WIDTH, 2);
   
   ObjectCreate(0, "SMC_Low_Line", OBJ_HLINE, 0, 0, 0);
   ObjectSetInteger(0, "SMC_Low_Line", OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, "SMC_Low_Line", OBJPROP_WIDTH, 2);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectDelete(0, "SMC_High_Line");
   ObjectDelete(0, "SMC_Low_Line");
   ObjectsDeleteAll(0, "SMC_Arrow_"); // Supprime les flèches au nettoyage
   Comment("");
  }

//+------------------------------------------------------------------+
//| Main Logic                                                       |
//+------------------------------------------------------------------+
void OnTick()
  {
   double prevClose = iClose(_Symbol, _Period, 1);
   if(prevClose == 0) return; 
   
   // Vérification nouvelle bougie pour ne pas alerter à chaque tick
   static datetime lastCandleTime = 0;
   datetime currentCandleTime = iTime(_Symbol, _Period, 0);
   bool isNewCandle = (lastCandleTime != currentCandleTime);

   // 1. Détection des Swings
   int highIndex = iHighest(_Symbol, _Period, MODE_HIGH, SwingLength, 1);
   int lowIndex  = iLowest(_Symbol, _Period, MODE_LOW, SwingLength, 1);
   double currentHigh = iHigh(_Symbol, _Period, highIndex);
   double currentLow  = iLow(_Symbol, _Period, lowIndex);

   if(lastSwingHigh == 0) lastSwingHigh = currentHigh;
   if(lastSwingLow == 0) lastSwingLow = currentLow;

   // 2. LOGIQUE DE SIGNAL (Uniquement à la clôture de la bougie)
   if(isNewCandle)
   {
      lastCandleTime = currentCandleTime; // Maj temps

      // --- SIGNAL D'ACHAT (CASSURE HAUSSIERE) ---
      if (prevClose > lastSwingHigh)
      {
         // On ne donne le signal que si la tendance change (pour éviter 50 alertes de suite)
         if(trendBias != 1)
         {
            trendBias = 1; 
            
            // A. Alerte Sonore et Pop-up
            if(UseAlerts) Alert("SMC: SIGNAL ACHAT sur ", _Symbol, " (BOS Haussier)");
            
            // B. Dessiner Flèche Bleue
            string arrowName = "SMC_Arrow_Up_" + TimeToString(currentCandleTime);
            ObjectCreate(0, arrowName, OBJ_ARROW_UP, 0, iTime(_Symbol, _Period, 1), iLow(_Symbol, _Period, 1));
            ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrBlue);
            ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
         }
         lastSwingHigh = currentHigh; 
      }

      // --- SIGNAL DE VENTE (CASSURE BAISSIERE) ---
      else if (prevClose < lastSwingLow)
      {
         if(trendBias != -1)
         {
            trendBias = -1;
            
            // A. Alerte Sonore et Pop-up
            if(UseAlerts) Alert("SMC: SIGNAL VENTE sur ", _Symbol, " (BOS Baissier)");
            
            // B. Dessiner Flèche Rouge
            string arrowName = "SMC_Arrow_Down_" + TimeToString(currentCandleTime);
            ObjectCreate(0, arrowName, OBJ_ARROW_DOWN, 0, iTime(_Symbol, _Period, 1), iHigh(_Symbol, _Period, 1));
            ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
         }
         lastSwingLow = currentLow; 
      }
      
      // Mise à jour des swings sans changement de tendance
      else 
      {
         if(trendBias == 1 && currentHigh > lastSwingHigh) lastSwingHigh = currentHigh;
         if(trendBias == -1 && currentLow < lastSwingLow) lastSwingLow = currentLow;
      }
   }

   // 3. VISUEL
   ObjectMove(0, "SMC_High_Line", 0, 0, lastSwingHigh);
   ObjectMove(0, "SMC_Low_Line", 0, 0, lastSwingLow);
   
   string trendText = (trendBias == 1) ? "HAUSSIER (Chercher Achat)" : (trendBias == -1) ? "BAISSIER (Chercher Vente)" : "NEUTRE (Range)";
   Comment("\n === SMC SIGNALS V3 === \n Tendance : ", trendText);
  }
