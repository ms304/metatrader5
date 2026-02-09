//+------------------------------------------------------------------+
//|                               Scanner_Ichimoku_Percent_Signed.mq5|
//|                                  Copyright 2026, Assistant IA    |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property copyright "t0"
#property link      "https://www.mql5.com"
#property version   "1.20"
#property strict

//--- INPUTS
input group "Paramètres Ichimoku"
input int      InpTenkan         = 9;      // Tenkan-sen
input int      InpKijun          = 26;     // Kijun-sen
input int      InpSenkou         = 52;     // Senkou Span B

input group "Paramètres du Scanner"
input double   InpThresholdPercent = 0.10; // Seuil d'alerte en % (ex: 0.1%)
input int      InpScanSeconds    = 60;     // Fréquence du scan en secondes
input bool     InpUseAlert       = true;   // Alerte Pop-up
input bool     InpPrintLog       = true;   // Journal Expert

//--- Variables globales
int extTimerId = 0;

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(InpScanSeconds);
   Print("Scanner Ichimoku (Signé) Démarré.");
   Print("Seuil: +/- ", InpThresholdPercent, "%");
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Désinitialisation                                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Print("Scanner Arrêté.");
  }

//+------------------------------------------------------------------+
//| Timer                                                            |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ScanMarket();
  }

//+------------------------------------------------------------------+
//| Fonction principale de scan                                      |
//+------------------------------------------------------------------+
void ScanMarket()
  {
   int totalSymbols = SymbolsTotal(true); 
   
   for(int i = 0; i < totalSymbols; i++)
     {
      string symbol = SymbolName(i, true);
      
      double price = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(price <= 0) continue;

      double kijunValue = GetKijunValue(symbol);
      if(kijunValue == 0) continue; 
      
      // --- CALCUL DU POURCENTAGE SIGNÉ ---
      // (Prix - Kijun) / Prix * 100
      // Si Prix > Kijun, résultat positif. Si Prix < Kijun, résultat négatif.
      double deviationRaw = price - kijunValue;
      double deviationPercent = (deviationRaw / price) * 100.0;
      
      // On vérifie la valeur absolue pour le seuil (pour déclencher l'alerte peu importe le sens)
      if(MathAbs(deviationPercent) <= InpThresholdPercent)
        {
         string positionDesc;
         
         if(deviationPercent > 0) 
            positionDesc = "AU-DESSUS (Support?)";
         else if(deviationPercent < 0) 
            positionDesc = "EN-DESSOUS (Résist.?)";
         else 
            positionDesc = "SUR LA KIJUN";

         // Formatage du message
         // %.3f affiche 3 décimales. Le "+" force l'affichage du signe plus pour les positifs
         string msg = StringFormat("SCAN: %s | %s | Écart: %+.3f%% | Prix: %.5f | Kijun: %.5f", 
                                   symbol, positionDesc, deviationPercent, price, kijunValue);
         
         if(InpPrintLog) Print(msg);
         if(InpUseAlert) Alert(msg);
        }
     }
  }

//+------------------------------------------------------------------+
//| Récupère la Kijun                                                |
//+------------------------------------------------------------------+
double GetKijunValue(string symbol)
  {
   int handle = iIchimoku(symbol, Period(), InpTenkan, InpKijun, InpSenkou);
   
   if(handle == INVALID_HANDLE) return 0.0;
   
   double buffer[];
   ArraySetAsSeries(buffer, true);
   
   int copied = CopyBuffer(handle, 1, 0, 1, buffer);
   
   double result = 0.0;
   if(copied > 0) result = buffer[0];
   
   IndicatorRelease(handle); 
   
   return result;
  }
//+------------------------------------------------------------------+
