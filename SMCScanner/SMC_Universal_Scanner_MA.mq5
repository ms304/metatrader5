//+------------------------------------------------------------------+
//|                                       SMC_Market_Scanner.mq5     |
//|               Scanner Multi-Devises SMC (Market Watch)           |
//|                  Liquidity Sweep + Rejection + Displacement      |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|                                       SMC_Market_Scanner.mq5     |
//|               Scanner Multi-Devises SMC (Market Watch)           |
//+------------------------------------------------------------------+
#property copyright "SMC Multi-Scanner"
#property version   "2.01"

// NOTE : J'ai retiré la ligne "indicator_plots" qui causait l'erreur.

//--- INPUTS ---
input group "--- PARAMETRES SMC ---"
input int      LookbackPeriod = 20;      // Période Liquidité (Swing High/Low)
input double   DisplacementFactor = 1.2;  // Force du mouvement (x ATR)
input bool     FilterByTrend = true;     // Filtre Tendance (EMA 200)

input group "--- REGLAGES SCANNER ---"
input bool     ScanClosedBar = true;     // True = Scan bougie clôturée (recommandé)
input int      RefreshSeconds = 10;      // Scan toutes les X secondes

//--- VARIABLES GLOBALES ---
struct SymbolState {
   string name;
   int handleATR;
   int handleMA;
   datetime lastAlertTime;
};

SymbolState watchedSymbols[];
int totalSymbols = 0;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // 1. Récupérer tous les symboles du Market Watch
   totalSymbols = SymbolsTotal(true); 
   
   if(totalSymbols == 0) {
      Alert("Erreur: Aucun symbole dans le Market Watch !");
      return(INIT_FAILED);
   }

   ArrayResize(watchedSymbols, totalSymbols);
   
   Print("------------------------------------------------");
   Print("SMC Scanner: Initialisation de ", totalSymbols, " actifs...");

   // 2. Créer les handles pour chaque symbole
   for(int i = 0; i < totalSymbols; i++)
     {
      string symName = SymbolName(i, true);
      watchedSymbols[i].name = symName;
      watchedSymbols[i].lastAlertTime = 0;
      
      // Création des indicateurs pour ce symbole spécifique
      watchedSymbols[i].handleATR = iATR(symName, _Period, 14);
      watchedSymbols[i].handleMA  = iMA(symName, _Period, 200, 0, MODE_EMA, PRICE_CLOSE);
      
      if(watchedSymbols[i].handleATR == INVALID_HANDLE || watchedSymbols[i].handleMA == INVALID_HANDLE) {
         Print("Erreur handle pour: ", symName);
      }
     }
     
   Print("SMC Scanner: Prêt ! Scanne toutes les ", RefreshSeconds, " secondes.");
   
   // On utilise un Timer plutôt que OnTick pour ne pas surcharger le CPU
   EventSetTimer(RefreshSeconds);
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Désinitialisation                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   // Nettoyage des handles
   for(int i = 0; i < totalSymbols; i++) {
      IndicatorRelease(watchedSymbols[i].handleATR);
      IndicatorRelease(watchedSymbols[i].handleMA);
   }
   Comment("");
  }

//+------------------------------------------------------------------+
//| Timer Function (Le coeur du scanner)                             |
//+------------------------------------------------------------------+
void OnTimer()
  {
   string scannerStatus = "SMC SCANNER ACTIF (" + EnumToString(_Period) + ")\n";
   scannerStatus += "Actifs surveillés: " + IntegerToString(totalSymbols) + "\n";
   scannerStatus += "----------------------------\n";
   
   // Boucle sur tous les symboles
   for(int i = 0; i < totalSymbols; i++)
     {
      string sym = watchedSymbols[i].name;
      
      // --- 1. RECUPERATION DES PRIX ---
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      
      // On récupère les 3 dernières bougies + le Lookback nécessaire
      // Index 0 = en cours, Index 1 = clôturée
      int needed = LookbackPeriod + 5;
      if(CopyRates(sym, _Period, 0, needed, rates) < needed) continue; // Pas assez de data, on passe
      
      // Index de référence pour l'analyse (1 = bougie clôturée)
      int idx = ScanClosedBar ? 1 : 0; 
      
      // Si on a déjà alerté sur cette bougie, on passe
      if(rates[idx].time == watchedSymbols[i].lastAlertTime) continue;

      double close = rates[idx].close;
      double open  = rates[idx].open;
      double high  = rates[idx].high;
      double low   = rates[idx].low;

      // --- 2. CALCUL SWING HIGH/LOW (LIQUIDITÉ) ---
      // On cherche le plus bas/haut entre idx+1 et idx+Lookback
      double lowestLow = 999999.0;
      double highestHigh = 0.0;
      
      for(int k = idx + 1; k <= idx + LookbackPeriod; k++) {
         if(rates[k].low < lowestLow) lowestLow = rates[k].low;
         if(rates[k].high > highestHigh) highestHigh = rates[k].high;
      }

      // --- 3. INDICATEURS (ATR & MA) ---
      double atrVal[], maVal[];
      if(CopyBuffer(watchedSymbols[i].handleATR, 0, idx, 1, atrVal) <= 0) continue;
      if(CopyBuffer(watchedSymbols[i].handleMA, 0, idx, 1, maVal) <= 0) continue;
      
      double currentATR = atrVal[0];
      double ema200 = maVal[0];
      double bodySize = MathAbs(close - open);

      // --- 4. ANALYSE DU SETUP SMC ---
      
      // A. SETUP BUY (Long)
      // Sweep du Low + Clôture au-dessus + Bougie Verte + Déplacement + Tendance
      if(low < lowestLow && close > lowestLow && close > open) 
        {
         if(bodySize > currentATR * DisplacementFactor)
           {
            if(!FilterByTrend || close > ema200) 
              {
               SendAlert(sym, "BUY", rates[idx].time, i);
               continue; // On passe au suivant
              }
           }
        }

      // B. SETUP SELL (Short)
      // Sweep du High + Clôture en-dessous + Bougie Rouge + Déplacement + Tendance
      if(high > highestHigh && close < highestHigh && close < open) 
        {
         if(bodySize > currentATR * DisplacementFactor)
           {
            if(!FilterByTrend || close < ema200) 
              {
               SendAlert(sym, "SELL", rates[idx].time, i);
              }
           }
        }
     }
     
   Comment(scannerStatus + "Dernier scan: " + TimeToString(TimeCurrent(), TIME_SECONDS));
  }

//+------------------------------------------------------------------+
//| Envoi de l'alerte                                                |
//+------------------------------------------------------------------+
void SendAlert(string symbol, string type, datetime time, int index)
  {
   string icon = (type == "BUY") ? "🟢" : "🔴";
   string msg = icon + " SMC ALERTE: " + symbol + " (" + EnumToString(_Period) + ")\n";
   msg += "Type: " + type + " (Turtle Soup)\n";
   msg += "Prix: " + DoubleToString(SymbolInfoDouble(symbol, SYMBOL_BID), 2);
   
   Alert(msg);
   SendNotification(msg); // Push mobile
   
   // Mémorise l'heure pour ne pas spammer la même alerte
   watchedSymbols[index].lastAlertTime = time;
  }
//+------------------------------------------------------------------+
