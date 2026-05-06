//+------------------------------------------------------------------+
//|                                         Ichimoku2026_Scanner.mq5 |
//|                          Copyright 2026, Invest Data Systems FR. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
// v1.04 - Correctifs et améliorations :
//   - Signal Ichimoku calculé sur la bougie [1] (clôturée) → stabilité
//   - Persistance : BID >= niveau - tolérance (points paramétrables)
//   - Prix de référence détection = close[1] (cohérent avec le signal)
//   - SSA/SSB de référence pris sur [1] également
//   - Chikou Span décalé correctement depuis [1] → indices [27]/[28]
// Signal initial  : transition false -> true (haussier strict, bougie clôturée)
// Signal confirmé : BID >= niveaux de référence pendant N ticks consécutifs
// Scan            : À chaque nouveau tick

#property copyright "Copyright 2026, Invest Data Systems France."
#property link      "https://ntic974.blogspot.com"
#property version   "1.04"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Paramètres d'entrée                                              |
//+------------------------------------------------------------------+
input bool enableTrading              = true;
input int  tenkan_period              = 9;
input int  kijun_period               = 26;
input int  senkou_b_period            = 52;
input int  confirmationTicks          = 10; // Ticks consécutifs requis pour confirmer
input int  persistenceTolerancePoints = 2;  // Tolérance en points sous le prix de détection
                                             // (0 = condition stricte BID >= detectionPrice)

//+------------------------------------------------------------------+
//| Structure de suivi par symbole                                   |
//+------------------------------------------------------------------+
struct SymbolState
  {
   string   name;

   // --- État Ichimoku ---
   bool     prevSignal;       // Signal bougie [1] mémorisé au tick précédent

   // --- Suivi de confirmation ---
   bool     inConfirmation;   // true : détection en cours de confirmation
   bool     confirmed;        // true : signal confirmé déjà émis (anti-doublon)

   double   detectionPrice;   // Close[1] au moment de la détection initiale
   double   detectionSSA;     // Senkou Span A[1] au moment de la détection
   double   detectionSSB;     // Senkou Span B[1] au moment de la détection

   int      confirmCount;     // Ticks consécutifs où la persistance est vérifiée
  };

//+------------------------------------------------------------------+
//| Variables globales                                               |
//+------------------------------------------------------------------+
CTrade      trade;
SymbolState g_states[];
int         g_symbolCount = 0;

//+------------------------------------------------------------------+
//| Buffers Ichimoku (réutilisés à chaque appel)                     |
//+------------------------------------------------------------------+
double tenkan_sen_buffer[];
double kijun_sen_buffer[];
double senkou_span_a_buffer[];
double senkou_span_b_buffer[];
double chikou_span_buffer[];
MqlRates mql_rates[];

//+------------------------------------------------------------------+
//| Initialisation                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ArraySetAsSeries(mql_rates,            true);
   ArraySetAsSeries(tenkan_sen_buffer,    true);
   ArraySetAsSeries(kijun_sen_buffer,     true);
   ArraySetAsSeries(senkou_span_a_buffer, true);
   ArraySetAsSeries(senkou_span_b_buffer, true);
   ArraySetAsSeries(chikou_span_buffer,   true);

   bool onlyMarketWatch = true;
   g_symbolCount = SymbolsTotal(onlyMarketWatch);
   ArrayResize(g_states, g_symbolCount);

   string alreadyValid = "";
   int    alreadyCount = 0;

   for(int i = 0; i < g_symbolCount; i++)
     {
      g_states[i].name           = SymbolName(i, onlyMarketWatch);
      g_states[i].inConfirmation = false;
      g_states[i].confirmed      = false;
      g_states[i].confirmCount   = 0;
      g_states[i].detectionPrice = 0.0;
      g_states[i].detectionSSA   = 0.0;
      g_states[i].detectionSSB   = 0.0;

      // État réel au démarrage sur bougie [1] — sans alerter
      double ssa1, ssb1;
      g_states[i].prevSignal = IchimokuBullishStrict(g_states[i].name, ssa1, ssb1);

      if(g_states[i].prevSignal)
        {
         alreadyCount++;
         alreadyValid += g_states[i].name + " ";
        }
     }

   printf("[Ichimoku Scanner v1.04] Initialisé sur " + string(g_symbolCount) + " symboles.");
   printf("[Ichimoku Scanner] Déjà validés au démarrage (" + string(alreadyCount) + ") : " + alreadyValid);
   printf("[Ichimoku Scanner] Confirmation : " + string(confirmationTicks)
          + " ticks | Tolérance persistance : " + string(persistenceTolerancePoints) + " points.");
   printf("[Ichimoku Scanner] Signal sur bougie clôturée [1]. En attente de transitions...");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Déinitialisation                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ArrayFree(g_states);
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   string tf = EnumToString(_Period);

   for(int i = 0; i < g_symbolCount; i++)
     {
      string sname     = g_states[i].name;
      double ssa1      = 0.0;
      double ssb1      = 0.0;
      bool   curSignal = IchimokuBullishStrict(sname, ssa1, ssb1);

      double bid    = SymbolInfoDouble(sname, SYMBOL_BID);
      double point  = SymbolInfoDouble(sname, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(sname, SYMBOL_DIGITS);

      // Tolérance convertie en prix
      double tolerance = persistenceTolerancePoints * point;

      //----------------------------------------------------------------
      // 1. Détection de transition false -> true (bougie clôturée [1])
      //----------------------------------------------------------------
      if(curSignal && !g_states[i].prevSignal)
        {
         // Prix de référence = close[1] (bougie clôturée ayant déclenché le signal)
         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         double refPrice = bid; // fallback si CopyRates échoue
         if(CopyRates(sname, PERIOD_CURRENT, 0, 2, rates) >= 2)
            refPrice = rates[1].close;

         // Initialiser le suivi de confirmation
         g_states[i].inConfirmation = true;
         g_states[i].confirmed      = false;
         g_states[i].confirmCount   = 0;
         g_states[i].detectionPrice = refPrice;
         g_states[i].detectionSSA   = ssa1;
         g_states[i].detectionSSB   = ssb1;

         string msg = "[Ichimoku Scanner] SIGNAL HAUSSIER STRICT : " + sname
                      + " | TF: " + tf
                      + " | Close[1]: " + DoubleToString(refPrice, digits)
                      + " | SSA[1]: "   + DoubleToString(ssa1, digits)
                      + " | SSB[1]: "   + DoubleToString(ssb1, digits)
                      + " | BID: "      + DoubleToString(bid, digits)
                      + " | "           + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

         printf(msg);
         Alert(msg);
         SendNotification(msg);
        }

      //----------------------------------------------------------------
      // 2. Suivi de confirmation (si une détection est en cours)
      //----------------------------------------------------------------
      if(g_states[i].inConfirmation)
        {
         if(!curSignal)
           {
            // Signal Ichimoku invalidé sur bougie clôturée → annulation complète
            string resetMsg = "[Ichimoku Scanner] SUIVI ANNULÉ : " + sname
                              + " | Signal invalidé après " + string(g_states[i].confirmCount) + " ticks"
                              + " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
            printf(resetMsg);

            g_states[i].inConfirmation = false;
            g_states[i].confirmed      = false;
            g_states[i].confirmCount   = 0;
           }
         else
           {
            // Persistance : BID >= niveau_référence - tolérance
            bool priceAboveDetection = (bid >= g_states[i].detectionPrice - tolerance);
            bool priceAboveSSA       = (bid >= g_states[i].detectionSSA   - tolerance);
            bool priceAboveSSB       = (bid >= g_states[i].detectionSSB   - tolerance);
            bool persistenceOK       = (priceAboveDetection && priceAboveSSA && priceAboveSSB);

            if(persistenceOK)
              {
               g_states[i].confirmCount++;
              }
            else
              {
               // Persistance rompue → reset compteur, suivi maintenu
               if(g_states[i].confirmCount > 0)
                 {
                  string breakMsg = "[Ichimoku Scanner] PERSISTANCE ROMPUE : " + sname
                                    + " | BID: "         + DoubleToString(bid, digits)
                                    + " | vs Close[1]: " + string(priceAboveDetection ? "OK" : "KO")
                                    + " SSA: "           + string(priceAboveSSA ? "OK" : "KO")
                                    + " SSB: "           + string(priceAboveSSB ? "OK" : "KO")
                                    + " | Tol: "         + string(persistenceTolerancePoints) + "pts"
                                    + " | Compteur remis à 0"
                                    + " | "              + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
                  printf(breakMsg);
                 }
               g_states[i].confirmCount = 0;
              }

            // Seuil de confirmation atteint → signal confirmé (une seule fois)
            if(!g_states[i].confirmed && g_states[i].confirmCount >= confirmationTicks)
              {
               g_states[i].confirmed = true;

               string confMsg = "[Ichimoku Scanner] *** SIGNAL CONFIRMÉ *** : " + sname
                                + " | TF: "             + tf
                                + " | BID: "            + DoubleToString(bid, digits)
                                + " | Ticks: "          + string(g_states[i].confirmCount)
                                + " | Close[1] réf: "   + DoubleToString(g_states[i].detectionPrice, digits)
                                + " | SSA[1] réf: "     + DoubleToString(g_states[i].detectionSSA, digits)
                                + " | SSB[1] réf: "     + DoubleToString(g_states[i].detectionSSB, digits)
                                + " | "                 + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

               printf(confMsg);
               Alert(confMsg);
               SendNotification(confMsg);
              }
           }
        }

      // Mémoriser l'état courant pour le prochain tick
      g_states[i].prevSignal = curSignal;
     }
  }

//+------------------------------------------------------------------+
//| Signal haussier strict sur bougie CLÔTURÉE [1]                  |
//| Retourne SSA[1] et SSB[1] via les paramètres de sortie           |
//+------------------------------------------------------------------+
bool IchimokuBullishStrict(string sname, double &out_ssa, double &out_ssb)
  {
   int max    = 64;
   int handle = iIchimoku(sname, PERIOD_CURRENT, tenkan_period, kijun_period, senkou_b_period);

   if(handle == INVALID_HANDLE)
      return false;

   int nbt   = CopyBuffer(handle, TENKANSEN_LINE,   0, max, tenkan_sen_buffer);
   int nbk   = CopyBuffer(handle, KIJUNSEN_LINE,    0, max, kijun_sen_buffer);
   int nbssa = CopyBuffer(handle, SENKOUSPANA_LINE, 0, max, senkou_span_a_buffer);
   int nbssb = CopyBuffer(handle, SENKOUSPANB_LINE, 0, max, senkou_span_b_buffer);
   int nbc   = CopyBuffer(handle, CHIKOUSPAN_LINE,  0, max, chikou_span_buffer);

   if(nbt <= 0 || nbk <= 0 || nbssa <= 0 || nbssb <= 0 || nbc <= 0)
     {
      IndicatorRelease(handle);
      return false;
     }

   if(CopyRates(sname, PERIOD_CURRENT, 0, 32, mql_rates) <= 0)
     {
      IndicatorRelease(handle);
      return false;
     }

   // --- Bougie clôturée [1] pour toutes les valeurs courantes ---
   double close1  = mql_rates[1].close;
   double ssa1    = senkou_span_a_buffer[1];
   double ssb1    = senkou_span_b_buffer[1];
   double tenkan1 = tenkan_sen_buffer[1];
   double kijun1  = kijun_sen_buffer[1];

   // --- Chikou Span : décalé de 26 bougies depuis [1] → indices [27]/[28] ---
   double cs        = chikou_span_buffer[27];
   double ssb_cs    = senkou_span_b_buffer[27];
   double ssa_cs    = senkou_span_a_buffer[28]; // SSA décalé d'une bougie supplémentaire
   double tenkan_cs = tenkan_sen_buffer[28];
   double kijun_cs  = kijun_sen_buffer[27];

   IndicatorRelease(handle);

   ArrayFree(senkou_span_b_buffer);
   ArrayFree(senkou_span_a_buffer);
   ArrayFree(tenkan_sen_buffer);
   ArrayFree(kijun_sen_buffer);
   ArrayFree(chikou_span_buffer);
   ArrayFree(mql_rates);

   ArraySetAsSeries(mql_rates,            true);
   ArraySetAsSeries(tenkan_sen_buffer,    true);
   ArraySetAsSeries(kijun_sen_buffer,     true);
   ArraySetAsSeries(senkou_span_a_buffer, true);
   ArraySetAsSeries(senkou_span_b_buffer, true);
   ArraySetAsSeries(chikou_span_buffer,   true);

   bool priceAboveCloud = (close1 > ssb1 && close1 > ssa1);
   bool priceAboveLines = (close1 > tenkan1 && close1 > kijun1);
   bool chikouValidated = (cs > tenkan_cs && cs > kijun_cs && cs > ssa_cs && cs > ssb_cs);

   // Exposer SSA/SSB de la bougie clôturée pour le suivi de confirmation
   out_ssa = ssa1;
   out_ssb = ssb1;

   return (priceAboveCloud && priceAboveLines && chikouValidated);
  }

//+------------------------------------------------------------------+
//| Retourne true uniquement sur la première bougie d'un nouveau bar |
//+------------------------------------------------------------------+
bool isNewBar()
  {
   static datetime last_time = 0;
   datetime lastbar_time = SeriesInfoInteger(Symbol(), Period(), SERIES_LASTBAR_DATE);

   if(last_time == 0)
     {
      last_time = lastbar_time;
      return false;
     }

   if(last_time != lastbar_time)
     {
      last_time = lastbar_time;
      return true;
     }

   return false;
  }
//+------------------------------------------------------------------+
