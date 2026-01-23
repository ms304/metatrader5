//+------------------------------------------------------------------+
//|                                       SMC_Market_Scanner.mq5     |
//|               Scanner Multi-Devises SMC (Market Watch)           |
//+------------------------------------------------------------------+
#property copyright "SMC Multi-Scanner"
#property version   "2.04"

//--- INPUTS ---
input group "--- PARAMETRES SMC ---"
input int      LookbackPeriod = 20;      // Période Liquidité (Swing High/Low)
input double   DisplacementFactor = 1.2;  // Force du mouvement (x ATR)
input bool     FilterByTrend = true;     // Filtre Tendance (EMA 200)

input group "--- REGLAGES SCANNER ---"
input bool     ScanClosedBar = true;     // True = Scan bougie clôturée
input int      RefreshSeconds = 10;      // Scan toutes les X secondes

input group "--- SECURITE RESSOURCES ---"
input int      MaxExecutionTimeMS = 3000; // Pause si le scan dure + de 3s
input bool     EnableSafetyPause  = true; // Activer la protection CPU

//--- VARIABLES GLOBALES ---
struct SymbolState {
   string name;
   int handleATR;
   int handleMA;
   datetime lastAlertTime;
};

SymbolState watchedSymbols[];
int   totalSymbols = 0;
ulong lastScanDuration = 0; // Utilisation de ulong pour GetTickCount64()

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   totalSymbols = SymbolsTotal(true); 
   
   if(totalSymbols == 0) {
      Print("Erreur: Aucun symbole dans le Market Watch !");
      return(INIT_FAILED);
   }

   ArrayResize(watchedSymbols, totalSymbols);
   
   for(int i = 0; i < totalSymbols; i++)
     {
      string symName = SymbolName(i, true);
      watchedSymbols[i].name = symName;
      watchedSymbols[i].lastAlertTime = 0;
      
      watchedSymbols[i].handleATR = iATR(symName, _Period, 14);
      watchedSymbols[i].handleMA  = iMA(symName, _Period, 200, 0, MODE_EMA, PRICE_CLOSE);
     }
     
   EventSetTimer(RefreshSeconds);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Désinitialisation                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < totalSymbols; i++) {
      IndicatorRelease(watchedSymbols[i].handleATR);
      IndicatorRelease(watchedSymbols[i].handleMA);
   }
   Comment("");
  }

//+------------------------------------------------------------------+
//| Timer Function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // --- 1. CHRONOMETRE & SECURITE CPU ---
   ulong startTick = GetTickCount64();
   
   // Si le dernier scan était trop lourd, on saute un tour pour laisser respirer le PC
   if(EnableSafetyPause && lastScanDuration > (ulong)MaxExecutionTimeMS)
     {
      Comment("⚠️ SCAN EN PAUSE (Surcharge CPU)\nTemps dernier scan: " + (string)lastScanDuration + " ms");
      lastScanDuration = 0; // Reset pour le prochain tour
      return;
     }

   string scannerStatus = "SMC SCANNER ACTIF\n";
   scannerStatus += "Actifs: " + (string)totalSymbols + "\n";
   scannerStatus += "Latence scan: " + (string)lastScanDuration + " ms\n";
   scannerStatus += "----------------------------\n";
   
   // --- 2. BOUCLE DE SCAN ---
   for(int i = 0; i < totalSymbols; i++)
     {
      if(_StopFlag) return; // Arrêt propre si l'EA est stoppé

      string sym = watchedSymbols[i].name;
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int needed = LookbackPeriod + 5;
      
      if(CopyRates(sym, _Period, 0, needed, rates) < needed) continue;
      
      int idx = ScanClosedBar ? 1 : 0; 
      if(rates[idx].time == watchedSymbols[i].lastAlertTime) continue;

      // Calcul Liquidité
      double lowestLow = 999999.0;
      double highestHigh = 0.0;
      for(int k = idx + 1; k <= idx + LookbackPeriod; k++) {
         if(rates[k].low < lowestLow) lowestLow = rates[k].low;
         if(rates[k].high > highestHigh) highestHigh = rates[k].high;
      }

      // Récupération Indicateurs
      double atrVal[1], maVal[1];
      if(CopyBuffer(watchedSymbols[i].handleATR, 0, idx, 1, atrVal) <= 0) continue;
      if(CopyBuffer(watchedSymbols[i].handleMA, 0, idx, 1, maVal) <= 0) continue;
      
      double close = rates[idx].close;
      double open  = rates[idx].open;
      double bodySize = MathAbs(close - open);

      // --- LOGIQUE SMC ---
      // Achat
      if(rates[idx].low < lowestLow && close > lowestLow && close > open) {
         if(bodySize > atrVal[0] * DisplacementFactor) {
            if(!FilterByTrend || close > maVal[0]) SendAlert(sym, "BUY", rates[idx].time, i);
         }
      }
      // Vente
      else if(rates[idx].high > highestHigh && close < highestHigh && close < open) {
         if(bodySize > atrVal[0] * DisplacementFactor) {
            if(!FilterByTrend || close < maVal[0]) SendAlert(sym, "SELL", rates[idx].time, i);
         }
      }
     }
     
   // --- 3. MESURE FINALE DE PERFORMANCE ---
   lastScanDuration = GetTickCount64() - startTick;
   
   Comment(scannerStatus + "Dernier scan à: " + TimeToString(TimeCurrent(), TIME_SECONDS));
  }

//+------------------------------------------------------------------+
//| Envoi de l'alerte                                                |
//+------------------------------------------------------------------+
void SendAlert(string symbol, string type, datetime time, int index)
  {
   string icon = (type == "BUY") ? "🟢" : "🔴";
   string msg = icon + " SMC " + type + ": " + symbol + " (" + EnumToString(_Period) + ")";
   
   Alert(msg);
   SendNotification(msg);
   watchedSymbols[index].lastAlertTime = time;
  }
