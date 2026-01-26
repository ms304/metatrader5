//+------------------------------------------------------------------+
//|                                         Ichimoku_Kijun_Bounce.mq5|
//|                          Copyright 2026, T0W3RBU5T3R. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, T0W3RBU5T3R."
#property link      "https://www.mql5.com"
#property version   "1.02"

#include <Trade\Trade.mqh>

// On garde les variables globales du code original
MqlRates mql_rates[];
double kijun_sen_buffer[];
double tenkan_sen_buffer[]; // Non utilisé ici mais gardé pour la structure
double senkou_span_a_buffer[];
double senkou_span_b_buffer[];
double chikou_span_buffer[];

int OnInit()
  {
   // Initialisation des séries comme dans l'original
   ArraySetAsSeries(mql_rates, true);
   ArraySetAsSeries(kijun_sen_buffer, true);
   ArraySetAsSeries(tenkan_sen_buffer, true);
   ArraySetAsSeries(senkou_span_a_buffer, true);
   ArraySetAsSeries(senkou_span_b_buffer, true);
   ArraySetAsSeries(chikou_span_buffer, true);

   printf("--- DÉBUT DU SCANNER KIJUN BOUNCE ---");

   bool onlySymbolsInMarketwatch = true;
   int stotal = SymbolsTotal(onlySymbolsInMarketwatch);

   for(int sindex = 0; sindex < stotal; sindex++)
     {
      string sname = SymbolName(sindex, onlySymbolsInMarketwatch);
      CheckKijunPullback(sname);
     }

   printf("--- FIN DU SCANNER ---");
   return(INIT_SUCCEEDED);
  }

void OnTick() {}

void CheckKijunPullback(string sname)
  {
   // On récupère un peu plus de bougies pour analyser la séquence (10 bougies)
   if(CopyRates(sname, PERIOD_CURRENT, 0, 10, mql_rates) <= 0) return;

   int tenkan_sen = 9;
   int kijun_sen = 26;
   int senkou_span_b = 52;

   int handle = iIchimoku(sname, PERIOD_CURRENT, tenkan_sen, kijun_sen, senkou_span_b);
   
   if(handle != INVALID_HANDLE)
     {
      // Récupération de la Kijun-Sen (on a besoin des 5 dernières valeurs au moins)
      if(CopyBuffer(handle, KIJUNSEN_LINE, 0, 10, kijun_sen_buffer) > 5)
        {
         // --- LOGIQUE BULLISH : PULLBACK SUR KIJUN ---
         
         // 1. Le prix était au-dessus de la Kijun il y a 3 bougies
         bool wasAbove = mql_rates[3].close > kijun_sen_buffer[3];
         
         // 2. Pullback : Le bas de la bougie 1 ou 2 a touché/frôlé la Kijun
         // On vérifie si le Low est passé sous ou proche de la Kijun alors que la clôture est restée saine
         bool pullbackOccurred = (mql_rates[2].low <= kijun_sen_buffer[2] && mql_rates[2].close >= kijun_sen_buffer[2]) ||
                                 (mql_rates[1].low <= kijun_sen_buffer[1] && mql_rates[1].close >= kijun_sen_buffer[1]);

         // 3. Reprise : La clôture actuelle (ou précédente) repart à la hausse au-dessus de la Kijun
         bool resumption = mql_rates[1].close > mql_rates[2].high && mql_rates[0].close > kijun_sen_buffer[0];

         if(wasAbove && pullbackOccurred && resumption)
           {
            printf(sname + " : [ACHAT] Pullback et rebond sur Kijun détecté.");
           }


         // --- LOGIQUE BEARISH : PULLBACK SUR KIJUN ---
         
         // 1. Le prix était en-dessous de la Kijun
         bool wasBelow = mql_rates[3].close < kijun_sen_buffer[3];
         
         // 2. Pullback : Le haut de la bougie a touché la Kijun
         bool pullbackBearish = (mql_rates[2].high >= kijun_sen_buffer[2] && mql_rates[2].close <= kijun_sen_buffer[2]) ||
                                (mql_rates[1].high >= kijun_sen_buffer[1] && mql_rates[1].close <= kijun_sen_buffer[1]);

         // 3. Reprise : Clôture sous le bas du pullback
         bool resumptionBearish = mql_rates[1].close < mql_rates[2].low && mql_rates[0].close < kijun_sen_buffer[0];

         if(wasBelow && pullbackBearish && resumptionBearish)
           {
            printf(sname + " : [VENTE] Pullback et rejet sous Kijun détecté.");
           }
        }
      
      // Nettoyage des buffers pour ce symbole
      IndicatorRelease(handle); 
     }
  }
