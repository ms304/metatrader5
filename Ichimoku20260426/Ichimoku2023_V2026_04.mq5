//+------------------------------------------------------------------+
//|                                         Ichimoku2026_Scanner.mq5 |
//|                          Copyright 2026, Invest Data Systems FR. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
// Version avec suivi de confirmation post-détection
// Signal initial  : transition false -> true (haussier strict)
// Signal confirmé : prix BID > prix_détection ET > SSA_détection ET > SSB_détection
//                   pendant N ticks consécutifs (confirmationTicks)
// Scan            : À chaque nouveau tick

#property copyright "Copyright 2026, Invest Data Systems France."
#property link      "https://ntic974.blogspot.com"
#property version   "1.03"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Paramètres d'entrée                                              |
//+------------------------------------------------------------------+
input bool enableTrading      = true;
input int  tenkan_period      = 9;
input int  kijun_period       = 26;
input int  senkou_b_period    = 52;
input int  confirmationTicks  = 10;   // Nombre de ticks consécutifs requis pour confirmer

//+------------------------------------------------------------------+
//| Structure de suivi par symbole                                   |
//+------------------------------------------------------------------+
struct SymbolState
  {
   string   name;

   // --- État Ichimoku ---
   bool     prevSignal;        // Signal validé au tick précédent (pour détecter la transition)

   // --- Suivi de confirmation ---
   bool     inConfirmation;    // true : une détection est en cours de confirmation
   bool     confirmed;         // true : signal confirmé déjà émis (évite les doublons)

   double   detectionPrice;    // Close au moment de la détection initiale
   double   detectionSSA;      // Senkou Span A au moment de la détection
   double   detectionSSB;      // Senkou Span B au moment de la détection

   int      confirmCount;      // Nombre de ticks consécutifs où la persistance est vérifiée
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

      // Capturer l'état réel au démarrage (sans alerter)
      double ssa0, ssb0;
      g_states[i].prevSignal = IchimokuBullishStrict(g_states[i].name, ssa0, ssb0);

      if(g_states[i].prevSignal)
        {
         alreadyCount++;
         alreadyValid += g_states[i].name + " ";
        }
     }

   printf("[Ichimoku Scanner] Initialisé sur " + string(g_symbolCount) + " symboles.");
   printf("[Ichimoku Scanner] Déjà validés au démarrage (" + string(alreadyCount) + ") : " + alreadyValid);
   printf("[Ichimoku Scanner] Confirmation requise : " + string(confirmationTicks) + " ticks consécutifs.");
   printf("[Ichimoku Scanner] En attente de nouvelles transitions...");
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
      string sname = g_states[i].name;
      double ssa0  = 0.0;
      double ssb0  = 0.0;
      bool   curSignal = IchimokuBullishStrict(sname, ssa0, ssb0);

      double bid    = SymbolInfoDouble(sname, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(sname, SYMBOL_DIGITS);

      //----------------------------------------------------------------
      // 1. Détection de transition false -> true
      //----------------------------------------------------------------
      if(curSignal && !g_states[i].prevSignal)
        {
         // Récupérer le close de la bougie courante comme prix de référence
         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         double refPrice = bid; // fallback
         if(CopyRates(sname, PERIOD_CURRENT, 0, 1, rates) > 0)
            refPrice = rates[0].close;

         // Initialiser le suivi de confirmation
         g_states[i].inConfirmation = true;
         g_states[i].confirmed      = false;
         g_states[i].confirmCount   = 0;
         g_states[i].detectionPrice = refPrice;
         g_states[i].detectionSSA   = ssa0;
         g_states[i].detectionSSB   = ssb0;

         string msg = "[Ichimoku Scanner] SIGNAL HAUSSIER STRICT : " + sname
                      + " | TF: " + tf
                      + " | Prix détection: " + DoubleToString(refPrice, digits)
                      + " | SSA: " + DoubleToString(ssa0, digits)
                      + " | SSB: " + DoubleToString(ssb0, digits)
                      + " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

         printf(msg);
         Alert(msg);
         SendNotification(msg);
        }

      //----------------------------------------------------------------
      // 2. Suivi de confirmation (si une détection est en cours)
      //----------------------------------------------------------------
      if(g_states[i].inConfirmation)
        {
         // Vérifier si le signal Ichimoku est toujours validé
         if(!curSignal)
           {
            // Signal invalidé : reset du suivi
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
            // Signal toujours validé : vérifier la persistance du prix
            bool priceAboveDetection = (bid > g_states[i].detectionPrice);
            bool priceAboveSSA       = (bid > g_states[i].detectionSSA);
            bool priceAboveSSB       = (bid > g_states[i].detectionSSB);
            bool persistenceOK       = (priceAboveDetection && priceAboveSSA && priceAboveSSB);

            if(persistenceOK)
              {
               g_states[i].confirmCount++;
              }
            else
              {
               // La persistance est rompue : on remet le compteur à zéro
               // mais on reste en mode "inConfirmation" (le signal Ichimoku tient encore)
               if(g_states[i].confirmCount > 0)
                 {
                  string breakMsg = "[Ichimoku Scanner] PERSISTANCE ROMPUE : " + sname
                                    + " | BID: " + DoubleToString(bid, digits)
                                    + " > PrixDét: " + string(priceAboveDetection ? "OK" : "KO")
                                    + " > SSA: " + string(priceAboveSSA ? "OK" : "KO")
                                    + " > SSB: " + string(priceAboveSSB ? "OK" : "KO")
                                    + " | Compteur remis à 0"
                                    + " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
                  printf(breakMsg);
                 }
               g_states[i].confirmCount = 0;
            }

            // 3. Vérification du seuil de confirmation
            if(!g_states[i].confirmed && g_states[i].confirmCount >= confirmationTicks)
              {
               g_states[i].confirmed = true;

               string confMsg = "[Ichimoku Scanner] *** SIGNAL CONFIRMÉ *** : " + sname
                                + " | TF: " + tf
                                + " | BID: " + DoubleToString(bid, digits)
                                + " | Ticks persistants: " + string(g_states[i].confirmCount)
                                + " | PrixDét: " + DoubleToString(g_states[i].detectionPrice, digits)
                                + " | SSA réf: " + DoubleToString(g_states[i].detectionSSA, digits)
                                + " | SSB réf: " + DoubleToString(g_states[i].detectionSSB, digits)
                                + " | " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);

               printf(confMsg);
               Alert(confMsg);
               SendNotification(confMsg);
              }
           }
        }

      // Mémoriser l'état courant
      g_states[i].prevSignal = curSignal;
     }
  }

//+------------------------------------------------------------------+
//| Calcule le signal haussier strict et retourne SSA/SSB courants   |
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

   double close0  = mql_rates[0].close;
   double ssa0    = senkou_span_a_buffer[0];
   double ssb0    = senkou_span_b_buffer[0];
   double tenkan0 = tenkan_sen_buffer[0];
   double kijun0  = kijun_sen_buffer[0];

   double cs        = chikou_span_buffer[26];
   double ssb_cs    = senkou_span_b_buffer[26];
   double ssa_cs    = senkou_span_a_buffer[27];
   double tenkan_cs = tenkan_sen_buffer[27];
   double kijun_cs  = kijun_sen_buffer[26];

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

   bool priceAboveCloud = (close0 > ssb0 && close0 > ssa0);
   bool priceAboveLines = (close0 > tenkan0 && close0 > kijun0);
   bool chikouValidated = (cs > tenkan_cs && cs > kijun_cs && cs > ssa_cs && cs > ssb_cs);

   // Exposer SSA/SSB courants pour le suivi de confirmation
   out_ssa = ssa0;
   out_ssb = ssb0;

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
